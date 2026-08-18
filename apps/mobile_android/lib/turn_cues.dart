import 'dart:math';

/// Pure geometric turn-cue generator for a planned polyline. Dart twin of
/// `apps/web/src/lib/routes/turn_cues.ts` — keep the two in lockstep
/// (algorithm, edge cases, test counts).
///
/// The offline-first turn-by-turn baseline (decisions §169): turns are
/// derived purely from the saved line's geometry — the bearing change at
/// each vertex — with no routing service, no network, and no key. It
/// announces *geometric* bends ("turn left"), not road-name-aware
/// instructions ("turn onto Oak St"); that is the deliberate trade for an
/// always-works offline cue list the recorder can play back with zero
/// connectivity.
///
/// A turn is the NET direction change accumulated within [mergeWithinM]
/// metres of where the turning starts, reported at the vertex where that
/// turning passes its halfway point. The two knobs then read as one
/// sentence: at least [minTurnAngleDeg] of direction change within
/// [mergeWithinM] metres is a turn; anything slacker is a curve and is not
/// announced. Every bearing is measured on a segment that TOUCHES the
/// vertex it is measured at, never one that spans it: a segment drawn
/// across a corner carries half that corner's angle and none of its
/// position.

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

  /// Bearing (degrees, 0–360, 0 = north) approaching the turn.
  final double bearingInDeg;

  /// Bearing leaving the turn.
  final double bearingOutDeg;

  final TurnDirection direction;

  /// Alias of [positionM] kept explicit for the cue-firing consumer.
  double get distanceFromStartM => positionM;
}

const double _defaultMinTurnAngleDeg = 30;
const double _defaultMergeWithinM = 15;
const double _slightMaxDeg = 45;
const double _uturnMinDeg = 150;

/// A leg shorter than this carries no usable bearing, so its far vertex is
/// dropped. Far below any route's vertex resolution, so dropping it cannot
/// move a corner.
const double _minLegM = 0.05;

/// A vertex bending less than this does not open a turn window. A corner
/// built from bends this small would need more vertices inside one window
/// than any drawn or imported route carries.
const double _turnEpsilonDeg = 0.5;

class _Bend {
  const _Bend(
    this.positionM,
    this.bearingInDeg,
    this.bearingOutDeg,
    this.deltaDeg,
  );
  final double positionM;
  final double bearingInDeg;
  final double bearingOutDeg;
  final double deltaDeg;
}

/// Generate an ordered list of turn cues from [waypoints]. Returns `[]` for a
/// straight line or fewer than 3 waypoints (no interior vertex to turn at).
List<TurnCue> generateTurnCues(
  List<TurnCueWaypoint> waypoints, {
  double minTurnAngleDeg = _defaultMinTurnAngleDeg,
  double mergeWithinM = _defaultMergeWithinM,
}) {
  if (waypoints.length < 3) return const [];

  final ptsWp = <TurnCueWaypoint>[waypoints[0]];
  final ptsCum = <double>[0];
  var cum = 0.0;
  for (var i = 1; i < waypoints.length; i++) {
    cum += _haversineM(waypoints[i - 1], waypoints[i]);
    if (cum - ptsCum.last < _minLegM) continue;
    ptsWp.add(waypoints[i]);
    ptsCum.add(cum);
  }
  if (ptsWp.length < 3) return const [];

  final bends = <_Bend>[];
  for (var i = 1; i < ptsWp.length - 1; i++) {
    final bearingIn = _bearingDeg(ptsWp[i - 1], ptsWp[i]);
    final bearingOut = _bearingDeg(ptsWp[i], ptsWp[i + 1]);
    bends.add(_Bend(
      ptsCum[i],
      bearingIn,
      bearingOut,
      _signedTurn(bearingIn, bearingOut),
    ));
  }

  final cues = <TurnCue>[];
  var i = 0;
  while (i < bends.length) {
    if (bends[i].deltaDeg.abs() < _turnEpsilonDeg) {
      i++;
      continue;
    }
    var net = 0.0;
    var swept = 0.0;
    var end = i;
    while (end < bends.length &&
        bends[end].positionM - bends[i].positionM <= mergeWithinM) {
      net += bends[end].deltaDeg;
      swept += bends[end].deltaDeg.abs();
      end++;
    }
    if (net.abs() < minTurnAngleDeg) {
      // Not a turn over this window. Slide by one rather than consuming the
      // window, so a corner that starts just inside it still opens its own.
      i++;
      continue;
    }
    var run = 0.0;
    var positionM = bends[i].positionM;
    for (var k = i; k < end; k++) {
      run += bends[k].deltaDeg.abs();
      if (run * 2 >= swept) {
        positionM = bends[k].positionM;
        break;
      }
    }
    cues.add(TurnCue(
      positionM: positionM,
      bearingInDeg: bends[i].bearingInDeg,
      bearingOutDeg: bends[end - 1].bearingOutDeg,
      direction: _classify(net),
    ));
    i = end;
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
