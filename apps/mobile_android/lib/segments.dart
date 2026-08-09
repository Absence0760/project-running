import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'geo.dart' show unwrapLonDeg;

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

/// A free-standing catalogue-segment geometry (the global/famous-segment
/// layer — decisions §232). Carries its own polyline, so matching keys off
/// the run passing the segment's start then its end rather than a
/// distance-along-a-route window. Mirrors `GlobalSegmentGeometry` in
/// `apps/web/src/lib/segments/segments.ts`.
class GlobalSegmentGeometry {
  final List<Waypoint> points;
  final double distanceM;
  const GlobalSegmentGeometry({required this.points, required this.distanceM});
}

/// Scores a run track against a free-standing catalogue-segment geometry
/// and returns the effort time, or null if the run didn't run it.
///
/// v1 is a CURATED end-to-end match, NOT arbitrary-geometry HMM matching
/// (deferred): the run must approach the segment's START within
/// [toleranceM], then reach its END within [toleranceM] LATER in the track
/// (a segment is directional), having covered a distance within 25% of the
/// segment's own length between the two crossings — otherwise null. The
/// timing reuses [computeEffortFromTrack] over that window so the sparsity
/// + timestamp-interpolation guards are shared. Mirrors
/// `computeGlobalSegmentEffort` in `apps/web/src/lib/segments/segments.ts`.
EffortResult? computeGlobalSegmentEffort(
  List<Waypoint> track,
  GlobalSegmentGeometry segment, {
  double toleranceM = 35,
}) =>
    computeGlobalSegmentEfforts(track, [segment], toleranceM: toleranceM).first;

/// Scores a run track against a whole catalogue of segment geometries in one
/// sweep, returning one result per input segment (null where the run didn't
/// run it). Identical per-segment semantics to [computeGlobalSegmentEffort],
/// which delegates here.
///
/// The batch shape is what makes catalogue scoring affordable. Scored
/// one-at-a-time, every segment paid two full-track haversine passes before
/// the check that rejected it, so a sweep over the 500-segment catalogue was
/// O(segments x trackPoints) — essentially all of it spent measuring
/// distances to segments on other continents. Here the track's extent is
/// measured once and each segment is rejected against it in constant time, so
/// only the handful of geometries that could plausibly match walk the track.
///
/// Mirrors `computeGlobalSegmentEfforts` in
/// `apps/web/src/lib/segments/segments.ts`.
List<EffortResult?> computeGlobalSegmentEfforts(
  List<Waypoint> track,
  List<GlobalSegmentGeometry> segments, {
  double toleranceM = 35,
}) {
  final out = List<EffortResult?>.filled(segments.length, null);
  if (track.length < 2 || segments.isEmpty) return out;

  final bounds = _trackBounds(track);
  // Only built once a segment survives the extent test — a sweep that
  // rejects every segment must not pay a haversine pass at all.
  List<double>? cum;

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final pts = segment.points;
    if (pts.length < 2 || segment.distanceM <= 0) continue;
    if (!_boundsAdmit(bounds, pts.first, toleranceM)) continue;
    if (!_boundsAdmit(bounds, pts.last, toleranceM)) continue;
    cum ??= _cumulativeDistances(track);
    out[i] = _scoreAgainstTrack(track, cum, segment, toleranceM);
  }
  return out;
}

List<double> _cumulativeDistances(List<Waypoint> track) {
  final cum = List<double>.filled(track.length, 0);
  for (var i = 1; i < track.length; i++) {
    cum[i] = cum[i - 1] +
        _haversine(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
  }
  return cum;
}

/// Latitude / longitude extent of a run track. Longitudes are unwrapped
/// around the first point (`geo.dart`), so a track straddling the
/// antimeridian stays one narrow interval instead of appearing to span the
/// globe.
class _TrackBounds {
  final double minLat;
  final double maxLat;
  final double refLon;
  final double minLon;
  final double maxLon;
  const _TrackBounds({
    required this.minLat,
    required this.maxLat,
    required this.refLon,
    required this.minLon,
    required this.maxLon,
  });
}

/// Metres per degree of latitude on the 6371 km sphere [_haversine] uses is
/// 111_195; the smaller figure here is deliberate, so every degree window
/// derived from a tolerance comes out slightly WIDER than the true one. The
/// extent test must never reject a segment the full scan would have matched.
const double _conservativeMetresPerDeg = 110574;

_TrackBounds _trackBounds(List<Waypoint> track) {
  final refLon = track.first.lng;
  var minLat = track.first.lat;
  var maxLat = minLat;
  var minLon = refLon;
  var maxLon = refLon;
  for (var i = 1; i < track.length; i++) {
    final lat = track[i].lat;
    if (lat < minLat) {
      minLat = lat;
    } else if (lat > maxLat) {
      maxLat = lat;
    }
    final lon = unwrapLonDeg(refLon, track[i].lng);
    if (lon < minLon) {
      minLon = lon;
    } else if (lon > maxLon) {
      maxLon = lon;
    }
  }
  return _TrackBounds(
    minLat: minLat,
    maxLat: maxLat,
    refLon: refLon,
    minLon: minLon,
    maxLon: maxLon,
  );
}

/// Whether any point of the track could lie within [toleranceM] of [point].
/// Conservative by construction: false means every track point is provably
/// further away, true means "maybe, go and measure".
///
/// Latitude is exact — spherical distance is never less than the meridian
/// separation. Longitude uses the tangent-meridian bound: everything within
/// an angular distance s of a point at latitude phi lies within
/// asin(sin s / cos phi) of its meridian, which for a 35 m tolerance is the
/// linear s / cos phi to well inside the margin the constant above carries.
/// Approaching the poles that window swells past a half-turn and the test
/// stops discriminating, so it admits rather than pretending to.
bool _boundsAdmit(_TrackBounds bounds, Waypoint point, double toleranceM) {
  final padLat = toleranceM / _conservativeMetresPerDeg;
  if (point.lat < bounds.minLat - padLat || point.lat > bounds.maxLat + padLat) {
    return false;
  }

  final cosLat = math.cos(point.lat * math.pi / 180);
  if (cosLat <= 0) return true;
  final padLon = padLat / cosLat;
  if (padLon >= 180) return true;

  final lon = unwrapLonDeg(bounds.refLon, point.lng);
  return lon >= bounds.minLon - padLon && lon <= bounds.maxLon + padLon;
}

EffortResult? _scoreAgainstTrack(
  List<Waypoint> track,
  List<double> cum,
  GlobalSegmentGeometry segment,
  double toleranceM,
) {
  final pts = segment.points;
  final start = pts.first;
  final end = pts.last;

  var startIdx = -1;
  var startBest = double.infinity;
  for (var i = 0; i < track.length; i++) {
    final d = _haversine(track[i].lat, track[i].lng, start.lat, start.lng);
    if (d < startBest) {
      startBest = d;
      startIdx = i;
    }
  }
  if (startIdx < 0 || startBest > toleranceM) return null;

  var endIdx = -1;
  var endBest = double.infinity;
  for (var i = startIdx + 1; i < track.length; i++) {
    final d = _haversine(track[i].lat, track[i].lng, end.lat, end.lng);
    if (d < endBest) {
      endBest = d;
      endIdx = i;
    }
  }
  if (endIdx < 0 || endBest > toleranceM) return null;

  final dStart = cum[startIdx];
  final dEnd = cum[endIdx];
  if (dEnd <= dStart) return null;

  // End-to-end guard: covered distance must be ~the segment length so a
  // straight-line shortcut between distant endpoints isn't mistaken for
  // running the segment.
  if ((dEnd - dStart - segment.distanceM).abs() / segment.distanceM > 0.25) {
    return null;
  }

  return computeEffortFromTrack(
    track,
    SegmentSlice(startDistanceM: dStart, endDistanceM: dEnd),
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

