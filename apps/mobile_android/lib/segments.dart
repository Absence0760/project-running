import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

/// Pure Dart port of `apps/web/src/lib/segments.ts` (decisions §37).
/// Walks a run track to extract elapsed time over a (start, end)
/// distance window of a saved route. Stays in sync with the web copy.

class SegmentSlice {
  final double startDistanceM;
  final double endDistanceM;
  const SegmentSlice({required this.startDistanceM, required this.endDistanceM});
}

class EffortResult {
  final double timeSeconds;
  final DateTime startedAt;
  const EffortResult({required this.timeSeconds, required this.startedAt});
}

/// Walks the run track once to compute elapsed time across a segment
/// slice. Returns null when the track is too short, has no timestamps,
/// or is too sparsely sampled (median step > segLen / 5).
EffortResult? computeEffortFromTrack(
  List<Waypoint> track,
  SegmentSlice segment,
) {
  if (track.length < 2) return null;
  final segLen = segment.endDistanceM - segment.startDistanceM;
  if (segLen <= 0) return null;

  final cum = List<double>.filled(track.length, 0);
  final steps = <double>[];
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    final d = _haversine(a.lat, a.lng, b.lat, b.lng);
    cum[i] = cum[i - 1] + d;
    if (d > 0) steps.add(d);
  }
  if (cum.last < segment.endDistanceM) return null;
  if (steps.isEmpty) return null;

  // Sparsity guard mirroring segments.ts.
  steps.sort();
  final median = steps[steps.length ~/ 2];
  if (median > segLen / 5) return null;

  final startMs = _msAtDistance(track, cum, segment.startDistanceM);
  final endMs = _msAtDistance(track, cum, segment.endDistanceM);
  if (startMs == null || endMs == null) return null;

  final elapsed = (endMs - startMs) / 1000.0;
  if (!(elapsed > 0)) return null;
  return EffortResult(
    timeSeconds: elapsed,
    startedAt: DateTime.fromMillisecondsSinceEpoch(startMs.round(), isUtc: true),
  );
}

/// Auto-effort generation for a run on its parent route. Mirrors
/// `computeSegmentEffortsForRun` in web `data.ts`. Idempotent against
/// the unique(segment_id, run_id) constraint via upsert with
/// ignoreDuplicates inside `recordSegmentEffort`.
Future<int> autoComputeEffortsForRun({
  required ApiClient api,
  required String runId,
  required String userId,
  required String routeId,
  required List<Waypoint> track,
}) async {
  if (track.length < 2) return 0;
  final viewerId = api.userId;
  if (viewerId == null || viewerId != userId) return 0;

  final segments = await api.fetchSegmentsForRoute(routeId);
  if (segments.isEmpty) return 0;

  var written = 0;
  for (final seg in segments) {
    final eff = computeEffortFromTrack(
      track,
      SegmentSlice(
        startDistanceM: seg.startDistanceM,
        endDistanceM: seg.endDistanceM,
      ),
    );
    if (eff == null) continue;
    try {
      await api.recordSegmentEffort(
        segmentId: seg.id,
        runId: runId,
        timeSeconds: eff.timeSeconds.round(),
        startedAt: eff.startedAt,
      );
      written++;
    } catch (_) {
      // Ignore individual insert failures; RLS or duplicate keys
      // simply skip the row rather than abort the whole walk.
    }
  }
  return written;
}

double? _msAtDistance(
  List<Waypoint> track,
  List<double> cum,
  double target,
) {
  for (var i = 1; i < track.length; i++) {
    if (cum[i] < target) continue;
    final prev = cum[i - 1];
    final here = cum[i];
    final a = track[i - 1];
    final b = track[i];
    if (a.timestamp == null || b.timestamp == null) return null;
    final tA = a.timestamp!.millisecondsSinceEpoch.toDouble();
    final tB = b.timestamp!.millisecondsSinceEpoch.toDouble();
    final span = here - prev;
    final frac = span > 0 ? (target - prev) / span : 0;
    return tA + (tB - tA) * frac;
  }
  return null;
}

double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final a = sinLat * sinLat +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          sinLng *
          sinLng;
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

