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
/// on app restart. See docs/decisions.md for the full rationale.
class WatchIngestQueue {
  static const _uuid = Uuid();

  late Directory _queueDir;

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _queueDir = Directory('${appDir.path}/watch_ingest_queue');
    if (!_queueDir.existsSync()) {
      _queueDir.createSync(recursive: true);
    }
  }

  /// Write a raw watch-run payload to the queue directory.
  Future<void> enqueue(Map<String, dynamic> payload) async {
    final filename = '${_uuid.v4()}.json';
    final file = File('${_queueDir.path}/$filename');
    try {
      await file.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('WatchIngestQueue.enqueue failed: $e');
    }
  }

  /// Replay all queued runs via [api.saveRun]. Each file is deleted on
  /// success. Files that fail are left on disk and will be retried on the
  /// next sign-in.
  Future<void> drain(ApiClient api) async {
    final files = _queueDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    for (final file in files) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final run = _runFromPayload(raw);
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
          .length;
    } catch (_) {
      return 0;
    }
  }

  static cm.Run _runFromPayload(Map<String, dynamic> raw) {
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
          ));
        }
      }
    }

    final metadata = <String, dynamic>{};
    final avgBpm = raw['avg_bpm'];
    if (avgBpm is num) metadata['avg_bpm'] = avgBpm.toDouble();
    final activity = raw['activity_type'];
    if (activity is String) metadata['activity_type'] = activity;

    return cm.Run(
      id: id,
      startedAt: startedAt,
      duration: Duration(seconds: durationS),
      distanceMetres: distanceM,
      track: track,
      source: _parseSource(source),
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  static cm.RunSource _parseSource(String raw) {
    for (final s in cm.RunSource.values) {
      if (s.name == raw) return s;
    }
    return cm.RunSource.watch;
  }
}
