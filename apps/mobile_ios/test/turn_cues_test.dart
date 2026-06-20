import 'package:flutter_test/flutter_test.dart';

import '../lib/turn_cues.dart';

/// Mirror of `apps/web/src/lib/routes/turn_cues.test.ts`. Keep these 10
/// cases in lockstep (same inputs, same expected directions). The math is
/// pure geometry over the polyline (bearing deltas at each interior vertex).
///
/// Coordinates are built at a low latitude (~0) where 0.01° lng ≈ 0.01° lat
/// in metres, so an axis-aligned right-angle reads as a clean 90° turn.
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
}
