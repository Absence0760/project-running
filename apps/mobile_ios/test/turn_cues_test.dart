import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../lib/turn_cues.dart';

/// Mirror of `apps/web/src/lib/routes/turn_cues.test.ts`. Keep these 14
/// cases in lockstep (same inputs, same expected directions). The math is
/// pure geometry over the polyline (bearing deltas at each interior vertex).
///
/// Coordinates are built at a low latitude (~0) where 0.01° lng ≈ 0.01° lat
/// in metres, so an axis-aligned right-angle reads as a clean 90° turn.
const double _mPerDeg = 111320;

/// A course that runs [cornerAtM] metres due north, turns [turnDeg] to the
/// left over [cornerLengthM] metres, then runs [tailM] metres on the new
/// heading — every leg sampled at [spacingM]. The densely-sampled corner is
/// what a saved route or an imported GPX actually looks like.
List<TurnCueWaypoint> _corneringCourse({
  required double spacingM,
  required double cornerAtM,
  required double tailM,
  required double turnDeg,
  double cornerLengthM = 0,
}) {
  final pts = <TurnCueWaypoint>[];
  var north = -cornerAtM;
  var east = 0.0;
  var headingDeg = 0.0;
  pts.add(TurnCueWaypoint(north / _mPerDeg, east / _mPerDeg));
  final steps = (cornerLengthM / spacingM).round();
  final legs = <double>[];
  for (var d = spacingM; d <= cornerAtM; d += spacingM) {
    legs.add(0);
  }
  for (var s = 0; s < steps; s++) {
    legs.add(turnDeg / steps);
  }
  if (steps == 0) legs.add(turnDeg);
  for (var d = spacingM; d <= tailM; d += spacingM) {
    legs.add(0);
  }
  for (final bend in legs) {
    headingDeg -= bend;
    final rad = headingDeg * pi / 180;
    north += spacingM * cos(rad);
    east += spacingM * sin(rad);
    pts.add(TurnCueWaypoint(north / _mPerDeg, east / _mPerDeg));
  }
  return pts;
}

void main() {
  // A square corner: east then north → a 90° LEFT turn at the vertex.
  final leftCorner = [
    const TurnCueWaypoint(0, 0),
    const TurnCueWaypoint(0, 0.02),
    const TurnCueWaypoint(0.02, 0.02),
  ];

  // East then south → a 90° RIGHT turn.
  final rightCorner = [
    const TurnCueWaypoint(0, 0),
    const TurnCueWaypoint(0, 0.02),
    const TurnCueWaypoint(-0.02, 0.02),
  ];

  test('a straight line produces no cues', () {
    final wp = [
      const TurnCueWaypoint(0, 0),
      const TurnCueWaypoint(0, 0.01),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0, 0.03),
    ];
    expect(generateTurnCues(wp), isEmpty);
  });

  test('empty input produces no cues', () {
    expect(generateTurnCues(const []), isEmpty);
  });

  test('a single-point input produces no cues', () {
    expect(generateTurnCues([const TurnCueWaypoint(0, 0)]), isEmpty);
  });

  test('a two-point line has no interior vertex, so no cues', () {
    expect(
      generateTurnCues([
        const TurnCueWaypoint(0, 0),
        const TurnCueWaypoint(0, 0.02),
      ]),
      isEmpty,
    );
  });

  test('a 90 degree left turn yields one left cue at the vertex', () {
    final cues = generateTurnCues(leftCorner);
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.left);
    expect(cues[0].positionM, greaterThan(0));
    expect(cues[0].positionM, cues[0].distanceFromStartM);
  });

  test('a 90 degree right turn yields one right cue', () {
    final cues = generateTurnCues(rightCorner);
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.right);
  });

  test('a sub-threshold wiggle is suppressed', () {
    // ~10° kink, below the default 30° threshold.
    final wp = [
      const TurnCueWaypoint(0, 0),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0.0035, 0.04),
    ];
    expect(generateTurnCues(wp), isEmpty);
  });

  test('a slight bend just over threshold classifies as slight', () {
    // ~40° left bend → slightLeft (<= 45°).
    final wp = [
      const TurnCueWaypoint(0, 0),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0.017, 0.04),
    ];
    final cues = generateTurnCues(wp);
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.slightLeft);
  });

  test('a near-reversal is detected as a u-turn', () {
    // Out east, back west → ~180° → uturn.
    final wp = [
      const TurnCueWaypoint(0, 0),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0.0005, 0),
    ];
    final cues = generateTurnCues(wp);
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.uturn);
  });

  test('coincident vertices at one corner merge into a single cue', () {
    // A duplicated vertex right at the corner must not double-fire.
    final wp = [
      const TurnCueWaypoint(0, 0),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0, 0.02),
      const TurnCueWaypoint(0.02, 0.02),
    ];
    final cues = generateTurnCues(wp);
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.left);
  });

  /// The round-1/round-2 bug: a single 90° corner at 100 m sampled every 10 m
  /// used to collapse onto a segment drawn ACROSS the corner, so the one turn
  /// was announced twice (slightLeft at 80 m AND slightLeft at 100 m) — both
  /// under-classified, the first 20 m early, and "turns remaining" reading 2.
  test('a densely sampled 90 degree corner fires exactly one left cue at the corner',
      () {
    final cues = generateTurnCues(_corneringCourse(
      spacingM: 10,
      cornerAtM: 100,
      tailM: 100,
      turnDeg: 90,
    ));
    // "Turns remaining" on a one-corner course is 1, not 2.
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.left);
    expect(cues[0].positionM, closeTo(100, 1));
    expect(cues[0].positionM, cues[0].distanceFromStartM);
  });

  test('a densely sampled 40 degree bend still fires its slight cue', () {
    // Split across the collapsed segment this was two sub-threshold 20° halves
    // and vanished entirely.
    final cues = generateTurnCues(_corneringCourse(
      spacingM: 10,
      cornerAtM: 100,
      tailM: 100,
      turnDeg: 40,
    ));
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.slightLeft);
    expect(cues[0].positionM, closeTo(100, 1));
  });

  test('a corner rounded over several vertices fires one cue at its full angle',
      () {
    // 90° spread over three 30° vertices 5 m apart: one corner, not three
    // sub-threshold fragments and not a 30° slight.
    final cues = generateTurnCues(_corneringCourse(
      spacingM: 5,
      cornerAtM: 100,
      tailM: 100,
      turnDeg: 90,
      cornerLengthM: 15,
    ));
    expect(cues.length, 1);
    expect(cues[0].direction, TurnDirection.left);
    expect(cues[0].positionM, greaterThan(100));
    expect(cues[0].positionM, lessThan(115));
  });

  test('a densely sampled straight line with a 90 degree corner reports the corner once at any sampling',
      () {
    // The old collapse's answer depended on where the corner fell relative to
    // the 15 m merge window, so a different spacing produced a different (and
    // differently wrong) cue list for the same course.
    // 120 m is a whole number of every spacing, so the corner sits at the same
    // distance in all five courses.
    for (final spacingM in [4.0, 6.0, 8.0, 10.0, 12.0]) {
      final cues = generateTurnCues(_corneringCourse(
        spacingM: spacingM,
        cornerAtM: 120,
        tailM: 120,
        turnDeg: 90,
      ));
      expect(cues.length, 1, reason: 'spacing $spacingM');
      expect(cues[0].direction, TurnDirection.left, reason: 'spacing $spacingM');
      expect(cues[0].positionM, closeTo(120, 1), reason: 'spacing $spacingM');
    }
  });
}
