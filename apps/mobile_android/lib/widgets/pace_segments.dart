import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../preferences.dart' show ActivityType;

/// Pace colour ramp — slow → fast, 6 buckets. Designed to read clearly
/// on top of the dark map style and to map "hotter colour = faster" in
/// a way that matches what runners already expect from NRC / Strava
/// heatmaps. Bucket count matches [_ageAlphas] / [_speedBreakpoints]:
/// 5 breakpoints partition the speed range into 6 buckets.
const _paceRamp = <Color>[
  Color(0xFFEF4444), // red — slowest
  Color(0xFFF97316), // orange
  Color(0xFFFBBF24), // amber
  Color(0xFFA3E635), // lime
  Color(0xFF10B981), // emerald
  Color(0xFF22D3EE), // cyan — fastest
];

/// Three age bands (oldest → newest) applied as alpha on top of the
/// pace colour. The tail of the run fades out like a comet; the
/// segment nearest the runner is fully opaque.
const _ageAlphas = <double>[0.55, 0.80, 1.0];

/// Speed break-points (m/s), slow → fast. Four of the activities use
/// pace (min/km); cycling is displayed as speed but the buckets are
/// expressed in m/s so a single helper handles both. Values chosen so
/// a "typical" pace falls in the middle two buckets.
///
/// Conversion: m/s = 1000 / (seconds-per-km). A 5:00/km pace is 3.33 m/s.
const _speedBreakpoints = <ActivityType, List<double>>{
  // Running: 7:30, 6:10, 5:15, 4:30, 3:45 per km
  ActivityType.run: [2.2, 2.7, 3.2, 3.7, 4.4],
  // Walking: 16:40, 12:50, 10:25, 9:15, 7:35 per km
  ActivityType.walk: [1.0, 1.3, 1.6, 1.8, 2.2],
  // Cycling: 12, 18, 24, 30, 36 km/h
  ActivityType.cycle: [3.3, 5.0, 6.7, 8.3, 10.0],
  // Hiking: slower than walking, wider spread
  ActivityType.hike: [0.8, 1.1, 1.4, 1.7, 2.2],
};

/// Which pace bucket the given speed falls into. Bucket 0 is slowest,
/// `breakpoints.length` is fastest. Clamped at both ends.
@visibleForTesting
int paceBucketForSpeed(double mps, ActivityType activity) {
  final breaks = _speedBreakpoints[activity]!;
  for (int i = 0; i < breaks.length; i++) {
    if (mps < breaks[i]) return i;
  }
  return breaks.length;
}

/// Which age band the segment at [segmentIndex] falls into, given a
/// total of [segmentCount] segments. Index 0 = oldest, index 2 = newest.
/// Short tracks (≤1 segment) are treated as fully newest.
@visibleForTesting
int ageBandFor(int segmentIndex, int segmentCount) {
  if (segmentCount <= 1) return 2;
  final f = segmentIndex / (segmentCount - 1);
  if (f < 1 / 3) return 0;
  if (f < 2 / 3) return 1;
  return 2;
}

double? _segmentSpeedMps(Waypoint a, Waypoint b) {
  final ta = a.timestamp;
  final tb = b.timestamp;
  if (ta == null || tb == null) return null;
  final dtSec = tb.difference(ta).inMilliseconds / 1000.0;
  if (dtSec <= 0) return null;
  final d = _haversineMetres(a, b);
  if (d <= 0) return null;
  return d / dtSec;
}

double _haversineMetres(Waypoint a, Waypoint b) {
  const r = 6371000.0;
  final lat1 = a.lat * pi / 180;
  final lat2 = b.lat * pi / 180;
  final dLat = (b.lat - a.lat) * pi / 180;
  final dLng = (b.lng - a.lng) * pi / 180;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(sqrt(h));
}

/// Build the list of [Polyline]s that make up the pace-coloured, age-faded
/// live track. Each segment is assigned a `(paceBucket, ageBand)` and
/// consecutive segments sharing both are coalesced into a single polyline
/// so the map doesn't have to draw one primitive per GPS fix.
///
/// [track] and [rendered] must be the same length; [rendered] is the
/// drawing-space coordinates (e.g. smoothed) while [track] provides the
/// raw timestamps for pace computation. Returns an empty list for tracks
/// with fewer than two points.
List<Polyline> buildPaceSegments({
  required List<Waypoint> track,
  required List<LatLng> rendered,
  required ActivityType activity,
  double strokeWidth = 6,
}) {
  assert(track.length == rendered.length,
      'track and rendered must have matching lengths');
  final n = track.length;
  if (n < 2) return const [];

  final segCount = n - 1;
  final paceBucket = List<int>.filled(segCount, 0);
  for (int i = 0; i < segCount; i++) {
    final mps = _segmentSpeedMps(track[i], track[i + 1]);
    paceBucket[i] = mps == null ? 0 : paceBucketForSpeed(mps, activity);
  }

  final ageBand = List<int>.filled(segCount, 0);
  for (int i = 0; i < segCount; i++) {
    ageBand[i] = ageBandFor(i, segCount);
  }

  final out = <Polyline>[];
  int runStart = 0;
  void emit(int firstSeg, int lastSegExclusive) {
    final pts = rendered.sublist(firstSeg, lastSegExclusive + 1);
    final color = _paceRamp[paceBucket[firstSeg]]
        .withValues(alpha: _ageAlphas[ageBand[firstSeg]]);
    out.add(Polyline(points: pts, strokeWidth: strokeWidth, color: color));
  }

  for (int i = 1; i < segCount; i++) {
    if (paceBucket[i] != paceBucket[i - 1] ||
        ageBand[i] != ageBand[i - 1]) {
      emit(runStart, i);
      runStart = i;
    }
  }
  emit(runStart, segCount);

  return out;
}
