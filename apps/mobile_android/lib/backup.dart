import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Full round-trip backup and restore for the signed-in user's data.
/// See [docs/backup_restore.md](../../../docs/backup_restore.md) for the
/// archive layout. Format is identical to the web side — a backup made
/// on either surface restores cleanly on the other.
///
/// All work happens against Supabase directly (not the local
/// `LocalRunStore`) because the backend is the canonical source of
/// truth for a user's history. Running this without network connectivity
/// fails fast.
class BackupService {
  BackupService({required this.api}) : _client = Supabase.instance.client;

  final ApiClient api;
  final SupabaseClient _client;

  static const _format = 'run-app-backup';
  static const _version = 1;

  /// Build a `.zip` and write it to [outputFile]. Returns the file.
  ///
  /// Tracks are archived in their raw gzipped form — the same bytes
  /// that live in the `runs` Storage bucket — so restore can upload
  /// them verbatim without re-encoding.
  Future<File> createBackup({
    required File outputFile,
    void Function(BackupProgress)? onProgress,
  }) async {
    final userId = api.userId;
    if (userId == null) throw Exception('Not authenticated');

    onProgress?.call(const BackupProgress.stage('runs'));
    final runs = await api.fetchRunRowsRaw();

    onProgress?.call(const BackupProgress.stage('routes'));
    final routesData = await _client
        .from('routes')
        .select()
        .eq('user_id', userId);
    final routes = (routesData as List).cast<Map<String, dynamic>>();

    onProgress?.call(const BackupProgress.stage('profile'));
    final profile = await _client
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    final userSettings = await _client
        .from('user_settings')
        .select('prefs')
        .eq('user_id', userId)
        .maybeSingle();

    final archive = Archive();

    // Runs — strip user_id so the archive is re-homeable.
    final runsOut = runs.map((r) {
      final copy = Map<String, dynamic>.from(r);
      copy.remove('user_id');
      return copy;
    }).toList();
    _addJson(archive, 'runs.json', runsOut);

    final routesOut = routes.map((r) {
      final copy = Map<String, dynamic>.from(r);
      copy.remove('user_id');
      return copy;
    }).toList();
    _addJson(archive, 'routes.json', routesOut);

    _addJson(archive, 'profile.json', {
      'profile': profile == null ? null : _withoutKey(profile, 'id'),
      'settings_prefs': userSettings == null ? <String, dynamic>{} : (userSettings['prefs'] ?? {}),
    });

    // Tracks — raw gzipped bytes from Storage.
    final runsWithTracks = runs
        .where((r) => r['track_url'] is String && (r['track_url'] as String).isNotEmpty)
        .toList();
    var i = 0;
    for (final r in runsWithTracks) {
      onProgress?.call(BackupProgress.tracks(i, runsWithTracks.length));
      try {
        final bytes = await api.downloadTrackBytes(r['track_url'] as String);
        archive.addFile(ArchiveFile('tracks/${r['id']}.json.gz', bytes.length, bytes));
      } catch (e) {
        debugPrint('track download failed ${r['id']}: $e');
      }
      i++;
    }
    onProgress?.call(BackupProgress.tracks(runsWithTracks.length, runsWithTracks.length));

    _addJson(archive, 'manifest.json', {
      'format': _format,
      'version': _version,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'exported_by_user_id': userId,
      'exported_from': 'mobile_android',
      'counts': {
        'runs': runs.length,
        'routes': routes.length,
        'goals': 0,
        'tracks': runsWithTracks.length,
      },
    });

    onProgress?.call(const BackupProgress.stage('writing'));
    final encoded = ZipEncoder().encode(archive);
    await outputFile.writeAsBytes(encoded, flush: true);
    onProgress?.call(const BackupProgress.done());
    return outputFile;
  }

  /// Read [zipFile] and upsert its contents against the signed-in user.
  /// Additive — never deletes existing data.
  Future<RestoreResult> restore({
    required File zipFile,
    bool generateNewIds = false,
    void Function(RestoreProgress)? onProgress,
  }) async {
    final userId = api.userId;
    if (userId == null) throw Exception('Not authenticated');

    onProgress?.call(const RestoreProgress.stage('reading'));
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

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

    final result = RestoreResult();

    // Profile first.
    final profile = _readJson(archive, 'profile.json');
    if (profile != null) {
      onProgress?.call(const RestoreProgress.stage('profile'));
      try {
        if (profile['profile'] is Map<String, dynamic>) {
          final row = Map<String, dynamic>.from(profile['profile'] as Map);
          row['id'] = userId;
          await _client.from('user_profiles').upsert(row);
          result.profileRestored = true;
        }
        final prefs = profile['settings_prefs'];
        if (prefs is Map && prefs.isNotEmpty) {
          await _client.from('user_settings').upsert({
            'user_id': userId,
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
        final data = await _client
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
            await api.uploadTrackBytes(
              userId: userId,
              runId: newId,
              gzippedBytes: trackBytes,
            );
            trackUrl = '$userId/$newId.json.gz';
            result.tracksUploaded++;
          } catch (e) {
            result.warnings.add('track $origId: $e');
          }
        }

        final ev = r['event_id'];
        final eventId = (ev is String && validEventIds.contains(ev)) ? ev : null;

        r['id'] = newId;
        r['user_id'] = userId;
        r['event_id'] = eventId;
        r['track_url'] = trackUrl;

        try {
          await api.upsertRunRowRaw(r);
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
        r['user_id'] = userId;
        try {
          await _client.from('routes').upsert(r);
          result.routesImported++;
        } catch (e) {
          result.warnings.add('route $origId: $e');
        }
        i++;
      }
    }

    onProgress?.call(const RestoreProgress.done());
    return result;
  }

  // ----- helpers -----

  void _addJson(Archive archive, String path, Object body) {
    final bytes = utf8.encode(jsonEncode(body));
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  dynamic _readJson(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    final body = utf8.decode(file.content as List<int>);
    return jsonDecode(body);
  }

  Map<String, dynamic> _withoutKey(Map<String, dynamic> m, String key) {
    final copy = Map<String, dynamic>.from(m);
    copy.remove(key);
    return copy;
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
