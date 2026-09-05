import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Persists watch-run payloads that arrive before the user has signed in.
///
/// When WatchIngest receives a run and the user is not authenticated, the
/// payload is written to disk under `<documents>/watch_ingest_queue/<uuid>.json`
/// rather than being discarded. On the next sign-in event, `drain` replays
/// every queued file and deletes each one on success.
///
/// The previous behaviour silently dropped watch runs received before sign-in
/// because the in-process `pending` buffer in WatchIngestBridge.swift was lost
/// on app restart. See docs/architecture/decisions.md for the full rationale.
///
/// **Shared-device owner-tag (added 2026-05).** Each queued file carries
/// the user_id who was most recently signed in on the phone — the
/// "intended adopter" of the payload. `drain` skips files whose stamp
/// names a different user from the one currently signed in. Without the
/// stamp, a watch payload that arrived during user A's signed-out window
/// would drain to user B the next time B signed in on the same device
/// (RLS accepts the row because it embeds B's user_id from the caller).
/// The stamp is written from main.dart's auth-state listener via
/// [setLastKnownOwner] — see the WearAuthBridge mirror for the same
/// owner-tracking pattern on the watch-session side.
class WatchIngestQueue {
  static const _uuid = Uuid();
  static const _lastOwnerFilename = 'last_owner.txt';

  /// Suffix for an entry [drain] can never parse. Renaming takes it out of the
  /// `.json` glob every listing here uses, so it stops being retried on every
  /// sign-in and stops inflating [pendingCount] — but it is kept, not deleted,
  /// because the alternative is silently destroying a real run over what may
  /// be a decoder bug.
  static const _rejectedSuffix = '.rejected';

  /// How long a rejected entry is kept before the sweep drops it. Mirrors the
  /// bounded-retention rule the other local caches follow: a payload nothing
  /// can read is residue, and it carries GPS.
  static const _rejectedRetention = Duration(days: 30);

  late Directory _queueDir;
  String? _lastKnownOwnerCache;

  File get _lastOwnerFile => File('${_queueDir.path}/$_lastOwnerFilename');

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _queueDir = Directory('${appDir.path}/watch_ingest_queue');
    if (!_queueDir.existsSync()) {
      _queueDir.createSync(recursive: true);
    }
    _sweepRejected();
    cm.sweepStoreScratchFiles(_queueDir,
        onError: (m) => debugPrint('WatchIngestQueue: $m'));
    // Hydrate the in-memory cache from the sidecar so enqueues that
    // run before the first setLastKnownOwner call still carry the
    // correct stamp (e.g. payload arrives during the brief window
    // between init() and the auth-state listener firing).
    try {
      if (_lastOwnerFile.existsSync()) {
        final txt = (await _lastOwnerFile.readAsString()).trim();
        if (txt.isNotEmpty) _lastKnownOwnerCache = txt;
      }
    } catch (e) {
      debugPrint('WatchIngestQueue.init last-owner read failed: $e');
    }
  }

  /// Record the user_id of the phone's most recently signed-in user.
  /// Called from main.dart's auth-state listener on every [signedIn]
  /// event (and at bootstrap when a cached session is restored), so
  /// subsequent enqueues — which run when api.userId is null and so
  /// can't capture the owner themselves — stamp files with the
  /// last-known signed-in user as the "intended adopter."
  ///
  /// Persisted to a sidecar so a process kill between the last
  /// sign-out and the next sign-in doesn't lose the stamp.
  /// Both call sites in `main.dart` fire this UNAWAITED — the bootstrap
  /// restore and the `signedIn` listener — so a sign-out followed by a sign-in
  /// puts a delete and an atomic write over one file in flight together. The
  /// delete then ran while the write's `.tmp` had not been renamed yet, found
  /// nothing to remove, and the rename put a stamp back that the store had
  /// been told to clear: the in-memory cache said signed-out while the next
  /// cold start hydrated a stale owner, and that owner is what decides which
  /// account a queued watch run adopts to. Serialised on the queue directory
  /// (§ 828); the in-memory half is already last-caller-wins because it is set
  /// before the first await.
  ///
  /// [enqueue] and [drain] stay off the chain deliberately. An enqueue's path
  /// is a fresh uuid nothing else names, and a drain awaits `api.saveRun` per
  /// file — putting a watch payload's write behind a stalled upload is the one
  /// thing this must not do.
  Future<void> setLastKnownOwner(String? userId) async {
    _lastKnownOwnerCache = userId;
    await cm.serialiseStoreWrite(_queueDir.path, () async {
      try {
        if (userId == null || userId.isEmpty) {
          if (_lastOwnerFile.existsSync()) await _lastOwnerFile.delete();
        } else {
          // Atomic like the envelope write: a bare writeAsString truncates
          // first, and init() reads an empty file as "no owner" — which drops
          // the stamp and lets the next account adopt the previous user's run.
          await cm.writeStringAtomic(_lastOwnerFile, userId);
        }
      } catch (e) {
        debugPrint('WatchIngestQueue.setLastKnownOwner write failed: $e');
      }
    });
  }

  /// The user_id stamped on payloads enqueued right now (exposed for
  /// tests). Reads the in-memory cache hydrated by [init] / updated
  /// by [setLastKnownOwner].
  String? get debugLastKnownOwner => _lastKnownOwnerCache;

  /// Write a raw watch-run payload to the queue directory, wrapped
  /// with the current last-known-owner stamp so [drain] can skip it
  /// when a different user signs in later (shared-device guard).
  Future<void> enqueue(Map<String, dynamic> payload) async {
    final filename = '${_uuid.v4()}.json';
    final file = File('${_queueDir.path}/$filename');
    final envelope = <String, dynamic>{
      if (_lastKnownOwnerCache != null)
        'intended_owner_user_id': _lastKnownOwnerCache,
      'payload': payload,
    };
    try {
      // Atomic, like every sibling store: a bare writeAsString truncates the
      // target first, so a process death mid-write leaves a truncated file
      // that drain can never parse.
      await cm.writeStringAtomic(file, jsonEncode(envelope));
    } catch (e) {
      debugPrint('WatchIngestQueue.enqueue failed: $e');
    }
  }

  /// Replay queued runs via [api.saveRun]. Each file is deleted on
  /// success. Files that fail are left on disk and will be retried on
  /// the next sign-in.
  ///
  /// Files whose `intended_owner_user_id` stamp names a DIFFERENT user
  /// from the one currently signed in are skipped (and left on disk
  /// for their rightful owner to drain when they sign back in).
  /// Untagged files (legacy / pre-stamp / queued before init wrote
  /// the sidecar) drain unconditionally, matching the pre-stamp
  /// "adopt to whoever signs in next" behaviour.
  Future<void> drain(ApiClient api) async {
    final currentUserId = api.userId;
    if (currentUserId == null) return;

    final files = _queueDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    for (final file in files) {
      // Two failure classes, and they need opposite handling. A read/decode
      // failure is PERMANENT — the bytes will not improve, so retrying it on
      // every sign-in is a forever-loop that also reports a phantom queued run
      // — while an upload failure is TRANSIENT and must keep retrying.
      final cm.Run run;
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        // Envelope-or-bare format detection. New format has a `payload`
        // key whose value is a Map; bare format is the payload itself
        // (which carries `id`/`started_at`/...). Legacy files from
        // before the envelope shipped land in the bare branch and
        // drain unconditionally (untagged → adoption rule).
        final Map<String, dynamic> payload;
        final String? intendedOwner;
        if (raw['payload'] is Map) {
          intendedOwner = raw['intended_owner_user_id'] as String?;
          payload = Map<String, dynamic>.from(raw['payload'] as Map);
        } else {
          intendedOwner = null;
          payload = raw;
        }
        if (intendedOwner != null && intendedOwner != currentUserId) {
          debugPrint(
            'WatchIngestQueue.drain: skipping ${file.path} — intended '
            'owner $intendedOwner does not match current user $currentUserId',
          );
          continue;
        }
        run = runFromWatchPayload(payload);
      } catch (e) {
        _reject(file, e);
        continue;
      }
      try {
        await api.saveRun(run);
      } catch (e) {
        debugPrint('WatchIngestQueue.drain upload failed for ${file.path}: $e');
        continue; // transient — left on disk for the next sign-in
      }
      try {
        await file.delete();
      } catch (e) {
        debugPrint('WatchIngestQueue: could not delete drained file: $e');
      }
    }
  }

  /// Move an unreadable entry out of the queue glob so it stops being retried.
  void _reject(File file, Object error) {
    debugPrint('WatchIngestQueue.drain rejecting ${file.path}: $error');
    try {
      file.renameSync('${file.path}$_rejectedSuffix');
    } catch (e) {
      debugPrint('WatchIngestQueue: could not quarantine ${file.path}: $e');
    }
  }

  /// Drop rejected entries past [_rejectedRetention]. Best-effort, at init.
  void _sweepRejected() {
    final cutoff = DateTime.now().subtract(_rejectedRetention);
    try {
      for (final entity in _queueDir.listSync()) {
        if (entity is! File || !entity.path.endsWith(_rejectedSuffix)) continue;
        try {
          if (entity.statSync().modified.isAfter(cutoff)) continue;
          entity.deleteSync();
        } catch (e) {
          debugPrint('WatchIngestQueue: rejected sweep failed for '
              '${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('WatchIngestQueue: rejected sweep failed: $e');
    }
  }

  int get pendingCount {
    try {
      return _queueDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// Entries [drain] could not parse and has quarantined. Test-visible so the
  /// retry-forever regression stays pinned.
  @visibleForTesting
  int get rejectedCount {
    try {
      return _queueDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(_rejectedSuffix))
          .length;
    } catch (_) {
      return 0;
    }
  }
}

/// Decode a raw watch-run payload (the JSON shape that lives in the
/// queue directory) into a [cm.Run]. Pure — exposed for tests so the
/// payload schema can be exercised without disk IO.
cm.Run runFromWatchPayload(Map<String, dynamic> raw) {
  final id = raw['id'] as String?;
  if (id == null || id.isEmpty) {
    // A blank id can never be uploaded — Postgres rejects it as a uuid — so it
    // has to fail on the PARSE side, where drain quarantines it. Left to the
    // upload branch it is classified transient and retried on every sign-in
    // for the life of the install, inflating pendingCount with a phantom run.
    throw const FormatException('watch payload has no id');
  }
  final startedAt = DateTime.parse(raw['started_at'] as String);
  final durationS = (raw['duration_s'] as num).toInt();
  final distanceM = (raw['distance_m'] as num).toDouble();
  final source = raw['source'] as String? ?? 'watch';
  final trackRaw = raw['track'];
  // Two senders, two shapes. The custom watch's BLE sync reshapes the blob
  // into a List of point maps (`sim_watch_sync.payloadFromBlob`); the Apple
  // Watch bridge forwards the raw JSON TEXT of the file the watch wrote
  // (`apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` sets
  // `payload["track"] = str`). Both reach this one decoder, and understanding
  // only the List shape is why an Apple Watch run that arrived while the
  // runner was signed out used to be replayed with no track at all — the
  // signed-IN copy of this decode knew about the string and this one did not.
  // A malformed string throws rather than degrading to an empty track: drain
  // quarantines the entry, the same treatment a blank id gets above, because
  // silently landing a trackless run is the defect, not the fallback.
  final points = trackRaw is String ? jsonDecode(trackRaw) : trackRaw;
  final track = <cm.Waypoint>[];
  if (points is List) {
    for (final p in points) {
      if (p is Map) {
        track.add(cm.Waypoint(
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
          elevationMetres: (p['ele'] as num?)?.toDouble(),
          timestamp: (p['ts'] as String?) != null
              ? DateTime.tryParse(p['ts'] as String)
              : null,
          // Per-point heart rate: both Apple Watch (HKLiveWorkoutBuilder)
          // and Wear OS (Health Services) ship a `bpm` field per
          // sample. `Waypoint.bpm` is `int?` so floor any decimal that
          // sneaks through and skip non-numeric values.
          bpm: (p['bpm'] as num?)?.toInt(),
        ));
      }
    }
  }

  final metadata = <String, dynamic>{};
  final avgBpm = raw['avg_bpm'];
  if (avgBpm is num) metadata[cm.MetadataKeys.avgBpm] = avgBpm.toDouble();
  // The share of the run the average above was taken over. Forwarded
  // verbatim like `avg_bpm` — every reader grades the range itself
  // (`hrCoveragePercent`, `_hrCoveragePercent`, the export's
  // `hrCoverageCell`), and the export deliberately keeps the raw value in
  // its `metadata` column, so a figure this build cannot interpret is
  // better stored and refused at render than dropped into the ambiguous
  // "no key" population `docs/backend/metadata.md` enumerates. Only
  // finiteness is required, and that is not fastidiousness: `metadata`
  // is JSON-encoded on the way to Postgres, so a non-finite double throws
  // and takes the whole run upload with it.
  final hrCoverage = raw['hr_coverage'];
  if (hrCoverage is num && hrCoverage.toDouble().isFinite) {
    metadata[cm.MetadataKeys.hrCoverage] = hrCoverage.toDouble();
  }
  final activity = raw['activity_type'];
  if (activity is String) metadata[cm.MetadataKeys.activityType] = activity;
  final lastModified = raw['last_modified_at'];
  if (lastModified is String) {
    metadata[cm.MetadataKeys.lastModifiedAt] = lastModified;
  }
  // A watch run recovered from its last mid-run checkpoint after a reset
  // carries `finished: false` (the run_store header's FLAG_FINISHED is clear).
  // Its footer totals are its totals-so-far, so without this stamp it lands in
  // the runner's history looking like a complete run — a reboot at mile 60
  // silently presents 60 miles as the whole day. Only the explicit false is
  // recorded: a sender that says nothing (every WCSession / Wear OS bridge)
  // only ever produces finished runs, and stamping every one of them `false`
  // would put a meaningless key on every watch row.
  if (raw['finished'] == false) {
    metadata[cm.MetadataKeys.recoveredUnfinished] = true;
  }
  // Lap splits: registered shape per `docs/backend/metadata.md` § laps —
  // `[{ index, start_offset_s, distance_m, duration_s }]`. Forward
  // verbatim so a watch sender that follows the registry survives a
  // round-trip through the queue without losing the user's mid-run
  // lap markers.
  final laps = raw['laps'];
  if (laps is List) {
    metadata[cm.MetadataKeys.laps] = List<Map<String, dynamic>>.from(
      laps.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
  }
  // The custom watch's planned-vs-actual workout trail (run-store v4,
  // decisions §356): registered shape per `docs/backend/metadata.md`
  // § watch_workout. Forwarded whole — the section only exists when the
  // decoder found it attributable (a summary with the pushed WKT1 frame's
  // CRC), and the join to a plan_workout_id stays a phone-side concern for
  // when the workout-push surface lands.
  final workout = raw['workout'];
  if (workout is Map) {
    metadata[cm.MetadataKeys.watchWorkout] = Map<String, dynamic>.from(workout);
  }

  return cm.Run(
    id: id,
    startedAt: startedAt,
    duration: Duration(seconds: durationS),
    distanceMetres: distanceM,
    track: track,
    source: parseRunSource(source),
    metadata: metadata.isEmpty ? null : metadata,
  );
}

/// Parse a run-source enum by name with [cm.RunSource.watch] as the
/// default. Used for the watch-payload `source` field.
cm.RunSource parseRunSource(String raw) {
  for (final s in cm.RunSource.values) {
    if (s.name == raw) return s;
  }
  return cm.RunSource.watch;
}
