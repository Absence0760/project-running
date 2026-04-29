import 'dart:math' as math;

/// Pure Dart port of `apps/web/src/lib/privacy.ts` (decisions §33).
/// Geofences clipped from the start and end of a track before it
/// renders on any public surface. Owner-side preview only — non-owner
/// clipping happens server-side via the `clip_track_for_user` RPC.

class PrivacyZone {
  final double lat;
  final double lng;
  final double radiusM;
  const PrivacyZone({
    required this.lat,
    required this.lng,
    required this.radiusM,
  });

  factory PrivacyZone.fromJson(Map<String, dynamic> json) => PrivacyZone(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radiusM: (json['radius_m'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
      };
}

/// Settings-bag key matching web's `PRIVACY_ZONES_KEY`.
const String privacyZonesKey = 'privacy_zones';

/// True when [point] is within the radius of any of [zones].
bool isInAnyZone(double lat, double lng, List<PrivacyZone> zones) {
  for (final z in zones) {
    if (_haversine(lat, lng, z.lat, z.lng) <= z.radiusM) return true;
  }
  return false;
}

/// Walk forward from index 0 and drop points in any zone; walk
/// backward from the end with the same predicate; keep the contiguous
/// middle. Mirrors `clipPointsToZones` in `privacy.ts`.
List<T> clipPointsToZones<T>(
  List<T> points,
  List<PrivacyZone> zones, {
  required double Function(T) latOf,
  required double Function(T) lngOf,
}) {
  if (zones.isEmpty || points.isEmpty) return points;
  var start = 0;
  while (start < points.length &&
      isInAnyZone(latOf(points[start]), lngOf(points[start]), zones)) {
    start++;
  }
  if (start >= points.length) return const [];
  var end = points.length - 1;
  while (end > start &&
      isInAnyZone(latOf(points[end]), lngOf(points[end]), zones)) {
    end--;
  }
  return points.sublist(start, end + 1);
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
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
