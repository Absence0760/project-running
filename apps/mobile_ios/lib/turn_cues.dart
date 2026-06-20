import 'dart:math';

/// Pure geometric turn-cue generator for a planned polyline. Dart twin of
/// `apps/web/src/lib/routes/turn_cues.ts` — keep the two in lockstep
/// (algorithm, edge cases, test counts).
///
/// The offline-first turn-by-turn baseline (decisions §166): turns are
/// derived purely from the saved line's geometry — the bearing change at
/// each vertex — with no routing service, no network, and no key. It
/// announces *geometric* bends ("turn left"), not road-name-aware
/// instructions ("turn onto Oak St"); that is the deliberate trade for an
/// always-works offline cue list the recorder can play back with zero
/// connectivity.

class TurnCueWaypoint {
  const TurnCueWaypoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum TurnDirection { left, right, slightLeft, slightRight, straight, uturn }

class TurnCue {
  const TurnCue({
    required this.positionM,
    required this.bearingInDeg,
    required this.bearingOutDeg,
    required this.direction,
  });

  /// Distance along the route, in metres from the start, at the turn vertex.
  final double positionM;

  /// Bearing (degrees, 0–360, 0 = north) approaching the vertex.
  final double bearingInDeg;

  /// Bearing leaving the vertex.
  final double bearingOutDeg;

  final TurnDirection direction;

  /// Alias of [positionM] kept explicit for the cue-firing consumer.
  double get distanceFromStartM => positionM;
}

const double _defaultMinTurnAngleDeg = 30;
const double _defaultMergeWithinM = 15;
const double _slightMaxDeg = 45;
const double _uturnMinDeg = 150;

/// Generate an ordered list of turn cues from [waypoints]. A cue is emitted
/// at each interior vertex whose bearing change exceeds [minTurnAngleDeg],
/// classified by signed turn angle into left/right/slight/uturn. Coincident
/// vertices and vertices within [mergeWithinM] of the previous kept vertex
/// are merged so a densely-sampled corner produces one cue, not a burst.
/// Returns `[]` for a straight line or fewer than 3 waypoints.
List<TurnCue> generateTurnCues(
  List<TurnCueWaypoint> waypoints, {
  double minTurnAngleDeg = _defaultMinTurnAngleDeg,
  double mergeWithinM = _defaultMergeWithinM,
}) {
  if (waypoints.length < 3) return const [];

  // Collapse coincident / sub-merge-distance vertices first, carrying the
  // cumulative distance of each surviving vertex along the ORIGINAL line.
  final collapsedWp = <TurnCueWaypoint>[];
  final collapsedCum = <double>[];
  var cum = 0.0;
  collapsedWp.add(waypoints[0]);
  collapsedCum.add(0);
  for (var i = 1; i < waypoints.length; i++) {
    cum += _haversineM(waypoints[i - 1], waypoints[i]);
    if (cum - collapsedCum.last <= mergeWithinM) {
      collapsedWp[collapsedWp.length - 1] = waypoints[i];
      continue;
    }
    collapsedWp.add(waypoints[i]);
    collapsedCum.add(cum);
  }
  if (collapsedWp.length < 3) return const [];

  final cues = <TurnCue>[];
  for (var i = 1; i < collapsedWp.length - 1; i++) {
    final bearingIn = _bearingDeg(collapsedWp[i - 1], collapsedWp[i]);
    final bearingOut = _bearingDeg(collapsedWp[i], collapsedWp[i + 1]);
    final delta = _signedTurn(bearingIn, bearingOut);
    if (delta.abs() < minTurnAngleDeg) continue;

    cues.add(TurnCue(
      positionM: collapsedCum[i],
      bearingInDeg: bearingIn,
      bearingOutDeg: bearingOut,
      direction: _classify(delta),
    ));
  }
  return cues;
}

/// Signed turn angle in degrees, (-180, 180]. Positive = right turn
/// (clockwise), negative = left turn — matching compass convention.
double _signedTurn(double bearingIn, double bearingOut) {
  var d = bearingOut - bearingIn;
  while (d > 180) {
    d -= 360;
  }
  while (d <= -180) {
    d += 360;
  }
  return d;
}

TurnDirection _classify(double delta) {
  final a = delta.abs();
  if (a >= _uturnMinDeg) return TurnDirection.uturn;
  if (delta > 0) {
    return a <= _slightMaxDeg ? TurnDirection.slightRight : TurnDirection.right;
  }
  return a <= _slightMaxDeg ? TurnDirection.slightLeft : TurnDirection.left;
}

double _bearingDeg(TurnCueWaypoint a, TurnCueWaypoint b) {
  const deg = pi / 180;
  final lat1 = a.lat * deg;
  final lat2 = b.lat * deg;
  final dLng = (b.lng - a.lng) * deg;
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  final brng = atan2(y, x) / deg;
  return (brng + 360) % 360;
}

double _haversineM(TurnCueWaypoint a, TurnCueWaypoint b) {
  const r = 6371000.0;
  const deg = pi / 180;
  final dLat = (b.lat - a.lat) * deg;
  final dLng = (b.lng - a.lng) * deg;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(a.lat * deg) * cos(b.lat * deg) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * asin(min(1, sqrt(h)));
}
