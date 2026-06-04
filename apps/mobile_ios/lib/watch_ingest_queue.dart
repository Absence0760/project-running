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

  late Directory _queueDir;
  String? _lastKnownOwnerCache;

  File get _lastOwnerFile => File('${_queueDir.path}/$_lastOwnerFilename');

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _queueDir = Directory('${appDir.path}/watch_ingest_queue');
    if (!_queueDir.existsSync()) {
      _queueDir.createSync(recursive: true);
    }
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
  Future<void> setLastKnownOwner(String? userId) async {
    _lastKnownOwnerCache = userId;
    try {
      if (userId == null || userId.isEmpty) {
        if (_lastOwnerFile.existsSync()) await _lastOwnerFile.delete();
      } else {
        await _lastOwnerFile.writeAsString(userId);
      }
    } catch (e) {
      debugPrint('WatchIngestQueue.setLastKnownOwner write failed: $e');
    }
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
      await file.writeAsString(jsonEncode(envelope));
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
        final run = runFromWatchPayload(payload);
        await api.saveRun(run);
        try {
          await file.delete();
        } catch (e) {
          debugPrint('WatchIngestQueue: could not delete drained file: $e');
        }
      } catch (e) {
        debugPrint('WatchIngestQueue.drain failed for ${file.path}: $e');
      }
    }
  }

  int get pendingCount {
    try {
      return _queueDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .where((f) => !f.path.endsWith(_lastOwnerFilename))
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
  final id = raw['id'] as String? ?? '';
  final startedAt = DateTime.parse(raw['started_at'] as String);
  final durationS = (raw['duration_s'] as num).toInt();
  final distanceM = (raw['distance_m'] as num).toDouble();
  final source = raw['source'] as String? ?? 'watch';
  final trackRaw = raw['track'];
  final track = <cm.Waypoint>[];
  if (trackRaw is List) {
    for (final p in trackRaw) {
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
  final activity = raw['activity_type'];
  if (activity is String) metadata[cm.MetadataKeys.activityType] = activity;
  final lastModified = raw['last_modified_at'];
  if (lastModified is String) {
    metadata[cm.MetadataKeys.lastModifiedAt] = lastModified;
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
