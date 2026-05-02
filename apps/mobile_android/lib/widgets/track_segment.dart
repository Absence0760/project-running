import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:latlong2/latlong.dart';

/// The result of tapping the run-detail map. Mirrors `SelectedSegment`
/// in `apps/web/src/lib/components/RunMap.svelte`. Carries the index
/// range and a few aggregate stats for the slice of track within
/// ±150 m of the tapped point.
class SelectedSegment {
  final int startIdx;
  final int endIdx;
  final int clickIdx;
  final double distanceMetres;
  final Duration? duration;
  final double? paceSecondsPerKm;
  final int? avgBpm;
  final double eleGainMetres;
  final double eleLossMetres;
  final Waypoint mid;

  const SelectedSegment({
    required this.startIdx,
    required this.endIdx,
    required this.clickIdx,
    required this.distanceMetres,
    required this.duration,
    required this.paceSecondsPerKm,
    required this.avgBpm,
    required this.eleGainMetres,
    required this.eleLossMetres,
    required this.mid,
  });
}

/// ±150 m window around the tapped track point. Matches `SEGMENT_RADIUS_M`
/// on web — keep in lockstep so a click on web and a tap on mobile
/// produce visually identical highlights and stats.
const double segmentRadiusMetres = 150;

double _haversineMetres(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dLat = (b.latitude - a.latitude) * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(sqrt(h));
}

/// Cumulative haversine distance from index 0 to each point. O(n) — the
/// runs we render top out around 2k points, well below the cost of
/// building a spatial index. Mirrors `buildCumulative` on web.
List<double> buildCumulativeDistances(List<Waypoint> track) {
  final out = List<double>.filled(track.length, 0);
  for (int i = 1; i < track.length; i++) {
    out[i] = out[i - 1] +
        _haversineMetres(
          LatLng(track[i - 1].lat, track[i - 1].lng),
          LatLng(track[i].lat, track[i].lng),
        );
  }
  return out;
}

/// Index of the track point nearest to [tap]. Linear scan — same trade
/// the web side makes (fine up to ~2k points).
int nearestTrackIdx(LatLng tap, List<Waypoint> track) {
  int best = 0;
  double bestDist = double.infinity;
  for (int i = 0; i < track.length; i++) {
    final d = _haversineMetres(tap, LatLng(track[i].lat, track[i].lng));
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// Build a [SelectedSegment] centred on [clickIdx], expanding outwards
/// until the cumulative distance window of ±[segmentRadiusMetres] is
/// reached. Returns null for tracks shorter than two points.
///
/// Computes per-segment duration, pace, average HR, and elevation gain
/// / loss the same way the web `buildSegment` does — keep both paths
/// in sync so the same tap on the same run produces identical stats
/// on both platforms.
SelectedSegment? buildSegmentAt(List<Waypoint> track, int clickIdx,
    {List<double>? cumulative}) {
  if (track.length < 2) return null;
  final cum = cumulative ?? buildCumulativeDistances(track);
  if (cum.length != track.length) return null;
  final target = cum[clickIdx];
  int startIdx = clickIdx;
  while (startIdx > 0 && cum[startIdx - 1] >= target - segmentRadiusMetres) {
    startIdx--;
  }
  int endIdx = clickIdx;
  while (
      endIdx < cum.length - 1 && cum[endIdx + 1] <= target + segmentRadiusMetres) {
    endIdx++;
  }
  if (startIdx == endIdx) {
    // Edge of the track — widen by one neighbour so we have a real
    // segment rather than a single-point degenerate.
    if (endIdx < cum.length - 1) {
      endIdx++;
    } else if (startIdx > 0) {
      startIdx--;
    }
  }

  final distanceM = cum[endIdx] - cum[startIdx];

  // Duration + pace come from per-point timestamps when present.
  final startTs = track[startIdx].timestamp;
  final endTs = track[endIdx].timestamp;
  Duration? duration;
  double? paceSecondsPerKm;
  if (startTs != null && endTs != null) {
    final dt = endTs.difference(startTs);
    if (dt.inMilliseconds > 0) {
      duration = dt;
      if (distanceM > 10) {
        paceSecondsPerKm =
            (dt.inMilliseconds / 1000) / (distanceM / 1000);
      }
    }
  }

  int bpmSum = 0;
  int bpmCount = 0;
  double eleGain = 0;
  double eleLoss = 0;
  for (int i = startIdx; i <= endIdx; i++) {
    final b = track[i].bpm;
    if (b != null && b >= 30 && b <= 230) {
      bpmSum += b;
      bpmCount++;
    }
    if (i > startIdx) {
      final prev = track[i - 1].elevationMetres;
      final cur = track[i].elevationMetres;
      if (prev != null && cur != null) {
        final delta = cur - prev;
        if (delta > 0) {
          eleGain += delta;
        } else {
          eleLoss += -delta;
        }
      }
    }
  }

  return SelectedSegment(
    startIdx: startIdx,
    endIdx: endIdx,
    clickIdx: clickIdx,
    distanceMetres: distanceM,
    duration: duration,
    paceSecondsPerKm: paceSecondsPerKm,
    avgBpm: bpmCount > 0 ? (bpmSum / bpmCount).round() : null,
    eleGainMetres: eleGain.roundToDouble(),
    eleLossMetres: eleLoss.roundToDouble(),
    mid: track[clickIdx],
  );
}
