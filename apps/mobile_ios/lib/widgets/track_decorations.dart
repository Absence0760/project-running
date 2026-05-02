import 'dart:math';

import 'package:latlong2/latlong.dart';

/// A km / mile boundary along a recorded track. The map renders a small
/// circular pin with [label] inside (1, 2, 3 …).
class DistanceMarker {
  final LatLng position;
  final int label;
  const DistanceMarker(this.position, this.label);
}

/// A direction arrow placed along the track. [angleRadians] is the
/// bearing of the local track segment (atan2 of `dy / dx` in lat/lng
/// units). The map rotates a chevron icon by this angle.
class TrackChevron {
  final LatLng position;
  final double angleRadians;
  const TrackChevron(this.position, this.angleRadians);
}

const double _metresPerMile = 1609.344;

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

/// Walk the polyline and emit a [DistanceMarker] at every kilometre (or
/// mile when [useMiles] is true) boundary. Mirrors `computeDistanceMarkers`
/// in `apps/web/src/lib/components/RunMap.svelte`.
///
/// When the authoritative [totalDistanceM] is meaningfully greater than
/// the polyline length (sparse user clicks / seed data), every marker's
/// *along-the-polyline* position is scaled by `polyline / real` so the
/// marker count reflects the real distance even though the rendered
/// geometry is a coarse approximation. Markers at index 0 (covered by
/// the green start cap) are skipped.
List<DistanceMarker> computeDistanceMarkers(
  List<LatLng> coords, {
  required bool useMiles,
  double? totalDistanceM,
}) {
  final out = <DistanceMarker>[];
  if (coords.length < 2) return out;
  final stepM = useMiles ? _metresPerMile : 1000.0;

  double polylineTotal = 0;
  for (int i = 1; i < coords.length; i++) {
    polylineTotal += _haversineMetres(coords[i - 1], coords[i]);
  }

  final realTotal =
      (totalDistanceM != null && totalDistanceM > polylineTotal * 1.1)
          ? totalDistanceM
          : polylineTotal;
  final scale = polylineTotal > 0 ? polylineTotal / realTotal : 1.0;

  double cumulative = 0;
  double nextMarker = stepM * scale;
  final maxAlongPolyline = polylineTotal;
  for (int i = 1; i < coords.length; i++) {
    final segmentM = _haversineMetres(coords[i - 1], coords[i]);
    while (cumulative + segmentM >= nextMarker &&
        segmentM > 0 &&
        nextMarker <= maxAlongPolyline + 0.5) {
      final t = (nextMarker - cumulative) / segmentM;
      final lat = coords[i - 1].latitude +
          (coords[i].latitude - coords[i - 1].latitude) * t;
      final lng = coords[i - 1].longitude +
          (coords[i].longitude - coords[i - 1].longitude) * t;
      final realPos = nextMarker / scale;
      final label = (realPos / stepM).round();
      out.add(DistanceMarker(LatLng(lat, lng), label));
      nextMarker += stepM * scale;
    }
    cumulative += segmentM;
  }
  return out;
}

/// Walk the polyline and emit a [TrackChevron] every [stepMetres]. Each
/// chevron points along the local segment so the runner's direction is
/// obvious at a glance — the equivalent of MapLibre's
/// `symbol-placement: line` arrows on the web map. Skips chevrons within
/// `stepMetres / 2` of the start and end so they don't crowd the green /
/// red caps.
List<TrackChevron> computeChevrons(
  List<LatLng> coords, {
  required double stepMetres,
}) {
  final out = <TrackChevron>[];
  if (coords.length < 2 || stepMetres <= 0) return out;

  double polylineTotal = 0;
  for (int i = 1; i < coords.length; i++) {
    polylineTotal += _haversineMetres(coords[i - 1], coords[i]);
  }
  if (polylineTotal < stepMetres) return out;

  double cumulative = 0;
  // Start one step in so the first chevron isn't on top of the start
  // cap, and stop a step before the end so we don't crowd the end cap.
  double nextChevron = stepMetres;
  final maxAlong = polylineTotal - stepMetres / 2;
  for (int i = 1; i < coords.length; i++) {
    final segmentM = _haversineMetres(coords[i - 1], coords[i]);
    while (cumulative + segmentM >= nextChevron &&
        segmentM > 0 &&
        nextChevron <= maxAlong) {
      final t = (nextChevron - cumulative) / segmentM;
      final lat = coords[i - 1].latitude +
          (coords[i].latitude - coords[i - 1].latitude) * t;
      final lng = coords[i - 1].longitude +
          (coords[i].longitude - coords[i - 1].longitude) * t;
      // Bearing in screen-space (lat increasing = up). The chevron
      // glyph points right at angle 0 so we rotate by the screen-space
      // angle of the local segment.
      final dLat = coords[i].latitude - coords[i - 1].latitude;
      final dLng = coords[i].longitude - coords[i - 1].longitude;
      // Screen-y grows downward; latitude grows upward — invert dLat so
      // a north-bound segment shows the chevron pointing up.
      final angle = atan2(-dLat, dLng);
      out.add(TrackChevron(LatLng(lat, lng), angle));
      nextChevron += stepMetres;
    }
    cumulative += segmentM;
  }
  return out;
}
