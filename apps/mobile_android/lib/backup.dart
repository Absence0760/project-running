import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'backup_server_client.dart';
import 'local_route_store.dart';
import 'local_run_store.dart';

/// Full round-trip backup and restore for the signed-in user's data.
/// See [docs/backup_restore.md](../../../docs/backup_restore.md) for the
/// archive layout. Format is identical to the web side — a backup made
/// on either surface restores cleanly on the other.
///
/// `createBackup` and the online `restore` path require an authenticated
/// `ApiClient`. The offline `_restoreOffline` path reads the archive
/// into a `LocalRunStore` only — no Supabase, no network — so the
/// constructor accepts `api: null` to support that "I just installed
/// the app and want my old runs back" workflow on a release build that
/// hasn't configured Supabase credentials yet. The screen layer
/// (`settings_screen._restoreBackup`) only requires `runStore` for the
/// offline branch; it picks `api`-less mode when `api` is null.
class BackupService {
  BackupService({this.api, BackupServerClient? serverClient})
      : _client = api == null ? null : _maybeClient(),
        _serverClient = serverClient;

  /// Try to grab `Supabase.instance.client` without throwing when
  /// Supabase wasn't initialized. Release builds without
  /// `--dart-define=SUPABASE_URL=...` skip the `Supabase.initialize`
  /// call entirely; constructing this service must still succeed so
  /// the offline-restore path can run.
  static SupabaseClient? _maybeClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  final ApiClient? api;
  final SupabaseClient? _client;
  /// Optional injection for the Go-service backup path. When null
  /// or unconfigured (no LIVE_HUB_URL), createBackup goes straight
  /// to the local writer. Tests pass a fake to assert the
  /// server-first → local-fallback dance.
  final BackupServerClient? _serverClient;

  static const _format = 'run-app-backup';
  static const _version = 1;

  /// Bounded concurrency for parallel track downloads. Six is empirical:
  /// enough to amortize per-request latency on cellular, low enough that
  /// peak in-flight memory is small (6 × ~50 KB gzipped tracks ≈ 300 KB)
  /// and a typical phone's connection pool isn't saturated.
  static const _kTrackDownloadConcurrency = 6;

  /// Build a `.zip` and write it to [outputFile]. Returns the file.
  ///
  /// Tracks are archived in their raw gzipped form — the same bytes
  /// that live in the `runs` Storage bucket — so restore can upload
  /// them verbatim without re-encoding.
  ///
  /// **Streaming + parallel:** rather than buffering the whole archive
  /// in memory before encoding (which OOMs on phones at ~2 000 runs),
  /// this opens a `ZipFileEncoder` writing incrementally to disk and
  /// downloads tracks in bounded-concurrency batches. Each track is
  /// added to the encoder as soon as it lands and its in-memory copy
  /// is dropped. Peak heap is roughly
  /// `_kTrackDownloadConcurrency × average-track-size`, regardless of
  /// total run count. See [decisions.md § 66](../../../docs/decisions.md#66-backup-zip-writes-stream-to-disk-and-download-tracks-in-bounded-batches).
  Future<File> createBackup({
    required File outputFile,
    void Function(BackupProgress)? onProgress,
  }) async {
    final api = this.api;
    final client = _client;
    if (api == null || client == null) {
      throw Exception('Backup unavailable — Supabase is not configured.');
    }
    final userId = api.userId;
    if (userId == null) throw Exception('Not authenticated');

    // Server-first: when the Go service is configured + the user has
    // a session, ask the server to build the archive and stream the
    // signed-URL response straight to disk. Cheaper for the device
    // (no fan-out downloads, no zip encode) and uses less cellular.
    // Any failure (HTTP non-200, IO error, server cap-overflow) falls
    // through to the local writer — never blocks the user from
    // getting a backup because the server hiccuped. See
    // [decisions.md § 66] for the trade-off (server caps at 5000
    // runs; the local writer covers the rest of the long tail).
    final didServer = await tryServerBackup(
      serverClient: _serverClient,
      accessToken: client.auth.currentSession?.accessToken,
      outputFile: outputFile,
      onProgress: onProgress,
    );
    if (didServer) return outputFile;

    onProgress?.call(const BackupProgress.stage('runs'));
    final runs = await api.fetchRunRowsRaw();

    onProgress?.call(const BackupProgress.stage('routes'));
    final routesData = await client
        .from('routes')
        .select()
        .eq('user_id', userId);
    final routes = (routesData as List).cast<Map<String, dynamic>>();

    onProgress?.call(const BackupProgress.stage('profile'));
    // Self-read via RPC — sensitive columns are column-level revoked from
    // direct SELECT (migration 20260707_001).
    final profile = await client.rpc('get_my_profile');
    final userSettings = await client
        .from('user_settings')
        .select('prefs')
        .eq('user_id', userId)
        .maybeSingle();

    // Strip user_id so the archive is re-homeable (restore stamps the
    // new owner's uid).
    final runsOut = runs.map((r) {
      final copy = Map<String, dynamic>.from(r);
      copy.remove('user_id');
      return copy;
    }).toList();
    final routesOut = routes.map((r) {
      final copy = Map<String, dynamic>.from(r);
      copy.remove('user_id');
      return copy;
    }).toList();

    final runsWithTracks = runs
        .where((r) =>
            r['track_url'] is String &&
            (r['track_url'] as String).isNotEmpty)
        .toList();

    final prefsRow = userSettings;
    final settingsPrefs =
        (prefsRow != null && prefsRow['prefs'] is Map)
            ? Map<String, dynamic>.from(prefsRow['prefs'] as Map)
            : const <String, dynamic>{};
    return writeBackupZipStreaming(
      outputFile: outputFile,
      runsOut: runsOut,
      routesOut: routesOut,
      profile: profile is Map ? Map<String, dynamic>.from(profile) : null,
      settingsPrefs: settingsPrefs,
      userId: userId,
      exportedFrom: 'mobile_android',
      runsWithTracks: runsWithTracks,
      fetchTrackBytes: (path) => api.downloadTrackBytes(path),
      concurrency: _kTrackDownloadConcurrency,
      onProgress: onProgress,
    );
  }

  /// Server-first attempt + partial-file cleanup, pulled out as a
  /// static helper so the orchestration is unit-testable without a
  /// live Supabase session.
  ///
  /// Returns `true` when the server path was attempted **and**
  /// succeeded — the caller treats the [outputFile] as a finished
  /// backup. Returns `false` when:
  ///
  /// * the server is unconfigured (null client or empty baseUrl),
  /// * the access token is null or empty,
  /// * the server attempt failed (HTTP non-200, IO error, etc.) —
  ///   any partial [outputFile] is deleted before falling through
  ///   so the local writer doesn't see a half-written file.
  ///
  /// Never throws. The local writer always gets a clean attempt
  /// either way, so a transient server hiccup can't block a
  /// power-user backup.
  @visibleForTesting
  static Future<bool> tryServerBackup({
    required BackupServerClient? serverClient,
    required String? accessToken,
    required File outputFile,
    void Function(BackupProgress)? onProgress,
  }) async {
    if (serverClient == null || !serverClient.isConfigured) return false;
    if (accessToken == null || accessToken.isEmpty) return false;
    onProgress?.call(const BackupProgress.stage('server'));
    try {
      await serverClient.fetchBackupToFile(
        accessToken: accessToken,
        outputFile: outputFile,
      );
      onProgress?.call(const BackupProgress.done());
      return true;
    } catch (e) {
      debugPrint('[backup] server path failed, falling back to local: $e');
      // Clean up any partial download so the local writer doesn't
      // see a half-written file. Safe to ignore the inner delete
      // exception — the local writer will overwrite anyway, this
      // is belt-and-braces.
      if (outputFile.existsSync()) {
        try {
          outputFile.deleteSync();
        } catch (_) {}
      }
      return false;
    }
  }

  /// Pure(-ish) writer extracted from [createBackup] so the streaming
  /// + parallel-download contract is testable without booting an
  /// `ApiClient` / Supabase. The caller hands us already-fetched run
  /// + route + profile data and a `fetchTrackBytes` callback that
  /// returns the gzipped bytes for a given storage path. The writer
  /// owns the `ZipFileEncoder` lifecycle, the bounded-concurrency
  /// download loop, and the manifest.
  @visibleForTesting
  static Future<File> writeBackupZipStreaming({
    required File outputFile,
    required List<Map<String, dynamic>> runsOut,
    required List<Map<String, dynamic>> routesOut,
    required Map<String, dynamic>? profile,
    required Map<String, dynamic> settingsPrefs,
    required String userId,
    required String exportedFrom,
    required List<Map<String, dynamic>> runsWithTracks,
    required Future<Uint8List> Function(String path) fetchTrackBytes,
    int concurrency = _kTrackDownloadConcurrency,
    void Function(BackupProgress)? onProgress,
  }) async {
    if (concurrency < 1) {
      throw ArgumentError.value(
          concurrency, 'concurrency', 'must be >= 1');
    }
    if (outputFile.existsSync()) outputFile.deleteSync();

    final encoder = ZipFileEncoder();
    encoder.create(outputFile.path);
    var tracksAdded = 0;
    try {
      // JSON metadata first — small + cheap.
      _writeJsonEntry(encoder, 'runs.json', runsOut);
      _writeJsonEntry(encoder, 'routes.json', routesOut);
      _writeJsonEntry(encoder, 'profile.json', {
        'profile': profile == null ? null : _withoutKeyMap(profile, 'id'),
        'settings_prefs': settingsPrefs,
      });

      onProgress?.call(BackupProgress.tracks(0, runsWithTracks.length));
      // Parallel download in bounded batches. Each batch's bytes are
      // written to the encoder + dropped before the next batch fires,
      // so peak heap is O(concurrency × avg-track-size) regardless of
      // total run count.
      for (var i = 0; i < runsWithTracks.length; i += concurrency) {
        final batch = runsWithTracks
            .skip(i)
            .take(concurrency)
            .toList(growable: false);
        final pulls = await Future.wait(
          batch.map((r) async {
            final url = r['track_url'] as String;
            final id = r['id'] as String;
            try {
              final bytes = await fetchTrackBytes(url);
              return (id, bytes);
            } catch (e) {
              debugPrint('track download failed $id: $e');
              return null;
            }
          }),
          eagerError: false,
        );
        for (final result in pulls) {
          if (result == null) continue;
          final (id, bytes) = result;
          encoder.addArchiveFile(
            ArchiveFile.bytes('tracks/$id.json.gz', bytes),
          );
          tracksAdded++;
        }
        onProgress?.call(BackupProgress.tracks(
          (i + batch.length).clamp(0, runsWithTracks.length),
          runsWithTracks.length,
        ));
      }

      _writeJsonEntry(encoder, 'manifest.json', {
        'format': _format,
        'version': _version,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'exported_by_user_id': userId,
        'exported_from': exportedFrom,
        'counts': {
          'runs': runsOut.length,
          'routes': routesOut.length,
          'goals': 0,
          'tracks': tracksAdded,
        },
      });

      onProgress?.call(const BackupProgress.stage('writing'));
    } finally {
      await encoder.close();
    }
    onProgress?.call(const BackupProgress.done());
    return outputFile;
  }

  /// Read [zipFile] and restore its contents.
  ///
  /// Two modes:
  ///
  /// * **Online** — the user is signed in. Runs + routes + profile are
  ///   upserted directly to Supabase; track blobs are re-homed to the
  ///   signed-in user's Storage bucket. This is the normal path.
  /// * **Offline-first** — no session, but a [runStore] and/or
  ///   [routeStore] are supplied. Data is hydrated into the local
  ///   stores marked as not-yet-synced; `SyncService` takes over the
  ///   upload once the user signs in. Profile + settings are skipped
  ///   with a warning — those keys don't apply to an anonymous user.
  ///
  /// Additive either way — never deletes existing data.
  Future<RestoreResult> restore({
    required File zipFile,
    bool generateNewIds = false,
    LocalRunStore? runStore,
    LocalRouteStore? routeStore,
    void Function(RestoreProgress)? onProgress,
  }) async {
    // `api == null` happens on a release build that wasn't given
    // SUPABASE_URL/ANON_KEY at compile time — the offline restore
    // path is the only one we can drive in that case. `api != null`
    // but `userId == null` is the "have credentials, not signed in"
    // case, which also routes through offline.
    final api = this.api;
    final offline = api == null || api.userId == null;

    if (offline && runStore == null && routeStore == null) {
      throw Exception(
        'Sign in first, or pass a local store to restore offline.',
      );
    }

    onProgress?.call(const RestoreProgress.stage('reading'));
    // Stream-decode from disk rather than `zipFile.readAsBytes()`. For
    // a multi-hundred-megabyte backup, the old path held the entire
    // ZIP in RAM (and then again as `[name, bytes]` pairs in the
    // worker isolate during decode). `InputFileStream` reads chunks
    // on demand and lazy-loads per-file contents — peak heap is
    // bounded by the largest single track, not the whole archive.
    final fileStream = InputFileStream(zipFile.path);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(fileStream);
    } catch (e) {
      await fileStream.close();
      rethrow;
    }

    final manifest = _readJson(archive, 'manifest.json');
    if (manifest == null || manifest['format'] != _format) {
      throw Exception('Not a valid backup — missing or wrong manifest.json');
    }
    final version = (manifest['version'] as num?)?.toInt() ?? 0;
    if (version > _version) {
      throw Exception(
        'Backup is from a newer version ($version). Update the app before restoring.',
      );
    }

    try {
    if (offline) {
      return await _restoreOffline(
        archive: archive,
        runStore: runStore,
        routeStore: routeStore,
        generateNewIds: generateNewIds,
        onProgress: onProgress,
      );
    }

    // Online path — we're signed in. `offline` is false here, which
    // means `api != null && api.userId != null` — Dart's flow analysis
    // already promotes `api` to non-null off the early-return above.
    // The constructor's `_client = api == null ? null : _maybeClient()`
    // invariant means `_client != null` whenever `api != null`, but
    // the analyzer can't promote a class field across statements, so
    // `_client!` is needed. Capture into stable locals so later
    // branches survive promotion-loss across awaits.
    final apiNonNull = api;
    final client = _client!;
    final uid = apiNonNull.userId!;
    final result = RestoreResult();

    // Profile first.
    final profile = _readJson(archive, 'profile.json');
    if (profile != null) {
      onProgress?.call(const RestoreProgress.stage('profile'));
      try {
        if (profile['profile'] is Map<String, dynamic>) {
          final row = Map<String, dynamic>.from(profile['profile'] as Map);
          // Strip server-managed fields. subscription_tier /
          // subscription_at are managed by the RevenueCat webhook;
          // parkrun_number is bound to the live integration row. The
          // 20260718_001 INSERT WITH CHECK + 20260624_001 UPDATE
          // trigger reject these for non-service-role callers anyway,
          // but stripping here means the rest of the profile
          // restores cleanly instead of the upsert silently failing.
          row.remove('subscription_tier');
          row.remove('subscription_at');
          row.remove('parkrun_number');
          row['id'] = uid;
          await client.from('user_profiles').upsert(row);
          result.profileRestored = true;
        }
        final prefs = profile['settings_prefs'];
        if (prefs is Map && prefs.isNotEmpty) {
          await client.from('user_settings').upsert({
            'user_id': uid,
            'prefs': prefs,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } catch (e) {
        result.warnings.add('profile: $e');
      }
    }

    // Runs + tracks.
    final runs = _readJson(archive, 'runs.json') as List?;
    if (runs != null) {
      // Resolve incoming event_ids against the DB so we don't FK-fail.
      final incomingEventIds = runs
          .whereType<Map>()
          .map((r) => r['event_id'])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final validEventIds = <String>{};
      if (incomingEventIds.isNotEmpty) {
        final data = await client
            .from('events')
            .select('id')
            .inFilter('id', incomingEventIds);
        for (final e in data as List) {
          validEventIds.add((e as Map)['id'] as String);
        }
      }

      var i = 0;
      for (final entry in runs) {
        onProgress?.call(RestoreProgress.runs(i, runs.length));
        if (entry is! Map) { i++; continue; }
        final r = Map<String, dynamic>.from(entry);
        final origId = r['id'] as String;
        final newId = generateNewIds ? _randomUuid() : origId;

        // Upload track from archive.
        String? trackUrl;
        final trackFile = archive.findFile('tracks/$origId.json.gz');
        if (trackFile != null) {
          try {
            final trackBytes = Uint8List.fromList(trackFile.content as List<int>);
            await apiNonNull.uploadTrackBytes(
              userId: uid,
              runId: newId,
              gzippedBytes: trackBytes,
            );
            trackUrl = '$uid/$newId.json.gz';
            result.tracksUploaded++;
          } catch (e) {
            result.warnings.add('track $origId: $e');
          }
        }

        final ev = r['event_id'];
        final eventId = (ev is String && validEventIds.contains(ev)) ? ev : null;

        r['id'] = newId;
        r['user_id'] = uid;
        r['event_id'] = eventId;
        r['track_url'] = trackUrl;

        try {
          await apiNonNull.upsertRunRowRaw(r);
          result.runsImported++;
        } catch (e) {
          result.warnings.add('run $origId: $e');
        }
        i++;
      }
    }

    // Routes.
    final routes = _readJson(archive, 'routes.json') as List?;
    if (routes != null) {
      var i = 0;
      for (final entry in routes) {
        onProgress?.call(RestoreProgress.routes(i, routes.length));
        if (entry is! Map) { i++; continue; }
        final r = Map<String, dynamic>.from(entry);
        final origId = r['id'];
        final newId = generateNewIds ? _randomUuid() : origId;
        r['id'] = newId;
        r['user_id'] = uid;
        try {
          await client.from('routes').upsert(r);
          result.routesImported++;
        } catch (e) {
          result.warnings.add('route $origId: $e');
        }
        i++;
      }
    }

    onProgress?.call(const RestoreProgress.done());
    return result;
    } finally {
      await fileStream.close();
    }
  }

  /// Offline-first restore. Hydrates local stores and leaves the
  /// SyncService to push to Supabase on next sign-in.
  ///
  /// Tracks are decoded from the archive and attached to the in-memory
  /// `Run` object rather than re-gzipped to disk — once the user signs
  /// in, `ApiClient.saveRun` re-gzips and uploads, matching the normal
  /// save path. That means a big backup temporarily lives in memory
  /// during the restore loop; for typical libraries (hundreds of runs,
  /// not tens of thousands) this is fine. If that breaks someday, stage
  /// the `.json.gz` blobs to the cache dir keyed on run id instead.
  Future<RestoreResult> _restoreOffline({
    required Archive archive,
    required LocalRunStore? runStore,
    required LocalRouteStore? routeStore,
    required bool generateNewIds,
    required void Function(RestoreProgress)? onProgress,
  }) async {
    final result = RestoreResult();
    result.warnings.add(
      'Restoring offline — runs are queued locally and will sync once you '
      'sign in. Profile and settings were skipped.',
    );

    // Runs.
    if (runStore != null) {
      final runs = _readJson(archive, 'runs.json') as List?;
      if (runs != null) {
        var i = 0;
        for (final entry in runs) {
          onProgress?.call(RestoreProgress.runs(i, runs.length));
          if (entry is! Map) { i++; continue; }
          final r = Map<String, dynamic>.from(entry);
          final origId = r['id'] as String;
          final newId = generateNewIds ? _randomUuid() : origId;

          final track = _decodeTrack(archive, origId);

          try {
            final run = cm.Run(
              id: newId,
              startedAt: DateTime.parse(r['started_at'] as String),
              duration: Duration(seconds: (r['duration_s'] as num).toInt()),
              distanceMetres: (r['distance_m'] as num).toDouble(),
              track: track,
              routeId: r['route_id'] as String?,
              source: cm.RunSource.values.firstWhere(
                (s) => s.name == (r['source'] as String?),
                orElse: () => cm.RunSource.app,
              ),
              externalId: r['external_id'] as String?,
              // Older backups (pre-Apr 2026) may lack
              // metadata.activity_type. The DB CHECK trigger
              // requires it on insert, so coalesce to 'run' on
              // restore. The user can still edit it afterwards.
              metadata: () {
                final m = r['metadata'] is Map
                    ? Map<String, dynamic>.from(r['metadata'] as Map)
                    : <String, dynamic>{};
                m['activity_type'] ??= 'run';
                return m;
              }(),
              createdAt: r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null,
            );
            await runStore.save(run);
            result.runsImported++;
            if (track.isNotEmpty) result.tracksUploaded++;
          } catch (e) {
            result.warnings.add('run $origId: $e');
          }
          i++;
        }
      }
    } else {
      result.warnings.add('runs: no LocalRunStore supplied — skipped');
    }

    // Routes.
    if (routeStore != null) {
      final routes = _readJson(archive, 'routes.json') as List?;
      if (routes != null) {
        var i = 0;
        for (final entry in routes) {
          onProgress?.call(RestoreProgress.routes(i, routes.length));
          if (entry is! Map) { i++; continue; }
          final r = Map<String, dynamic>.from(entry);
          final origId = r['id'] as String;
          final newId = generateNewIds ? _randomUuid() : origId;
          try {
            final waypoints = <cm.Waypoint>[];
            final wp = r['waypoints'];
            if (wp is List) {
              for (final w in wp) {
                if (w is! Map) continue;
                waypoints.add(cm.Waypoint(
                  lat: (w['lat'] as num).toDouble(),
                  lng: (w['lng'] as num).toDouble(),
                  elevationMetres: (w['ele'] as num?)?.toDouble(),
                ));
              }
            }
            final route = cm.Route(
              id: newId,
              userId: r['user_id'] as String? ?? '',
              name: r['name'] as String? ?? 'Route',
              waypoints: waypoints,
              distanceMetres: (r['distance_m'] as num?)?.toDouble() ?? 0,
              elevationGainMetres:
                  (r['elevation_m'] as num?)?.toDouble() ?? 0,
              isPublic: r['is_public'] == true,
              surface: r['surface'] as String?,
              tags: (r['tags'] as List?)?.cast<String>() ?? const [],
              featured: r['featured'] == true,
              runCount: (r['run_count'] as num?)?.toInt() ?? 0,
              createdAt: r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null,
            );
            await routeStore.save(route);
            result.routesImported++;
          } catch (e) {
            result.warnings.add('route $origId: $e');
          }
          i++;
        }
      }
    }

    onProgress?.call(const RestoreProgress.done());
    return result;
  }

  List<cm.Waypoint> _decodeTrack(Archive archive, String runId) {
    final file = archive.findFile('tracks/$runId.json.gz');
    if (file == null) return const [];
    try {
      final gz = file.content as List<int>;
      final raw = GZipDecoder().decodeBytes(gz);
      final body = utf8.decode(raw);
      final list = jsonDecode(body) as List;
      return [
        for (final w in list)
          if (w is Map)
            cm.Waypoint(
              lat: (w['lat'] as num).toDouble(),
              lng: (w['lng'] as num).toDouble(),
              elevationMetres: (w['ele'] as num?)?.toDouble(),
              timestamp: w['ts'] is String
                  ? DateTime.tryParse(w['ts'] as String)
                  : null,
            ),
      ];
    } catch (e) {
      debugPrint('[backup._decodeTrack] $e');
      return const [];
    }
  }

  // ----- helpers -----

  /// Serialise [body] to JSON and write it as an `ArchiveFile.bytes`
  /// entry to the open [encoder]. Used by the streaming
  /// `writeBackupZipStreaming` writer for the manifest + runs/routes/
  /// profile metadata; the on-the-fly write avoids buffering the
  /// whole encoded payload in RAM.
  static void _writeJsonEntry(
      ZipFileEncoder encoder, String path, Object body) {
    final bytes = utf8.encode(jsonEncode(body));
    encoder.addArchiveFile(ArchiveFile.bytes(path, bytes));
  }

  /// Return a shallow copy of [m] without [key]. Static — `_withoutKey`
  /// below is an instance method retained for the older online-restore
  /// path; this duplicates the shape so the new static writer doesn't
  /// need an instance.
  static Map<String, dynamic> _withoutKeyMap(
      Map<String, dynamic> m, String key) {
    final copy = Map<String, dynamic>.from(m);
    copy.remove(key);
    return copy;
  }

  dynamic _readJson(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    final body = utf8.decode(file.content as List<int>);
    return jsonDecode(body);
  }

  String _randomUuid() => const Uuid().v4();
}

class BackupProgress {
  final String stage; // runs | routes | profile | tracks | writing | done
  final int current;
  final int total;
  const BackupProgress._(this.stage, this.current, this.total);
  const BackupProgress.stage(String s) : this._(s, 0, 1);
  const BackupProgress.tracks(int c, int t) : this._('tracks', c, t);
  const BackupProgress.done() : this._('done', 1, 1);
  @override
  String toString() => '$stage ($current/$total)';
}

class RestoreProgress {
  final String stage; // reading | profile | runs | routes | done
  final int current;
  final int total;
  const RestoreProgress._(this.stage, this.current, this.total);
  const RestoreProgress.stage(String s) : this._(s, 0, 1);
  const RestoreProgress.runs(int c, int t) : this._('runs', c, t);
  const RestoreProgress.routes(int c, int t) : this._('routes', c, t);
  const RestoreProgress.done() : this._('done', 1, 1);
  @override
  String toString() => '$stage ($current/$total)';
}

class RestoreResult {
  int runsImported = 0;
  int routesImported = 0;
  int tracksUploaded = 0;
  bool profileRestored = false;
  final List<String> warnings = [];
}
