/// Pure unit tests for the in-progress recovery helper.
/// Persona-hunt finding Casual #3 — pre-fix, sub-threshold partials
/// were silently `clearInProgress()`-d with no breadcrumb. The
/// classifier now emits a banner message in both cases so the user
/// can tell the difference between "the app dropped a partial" and
/// "the app ate my run".

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/in_progress_recovery.dart';

Run _partial({
  required double distanceMetres,
  required Duration duration,
  int waypoints = 0,
  bool indoor = false,
}) {
  final track = List.generate(
    waypoints,
    (i) => Waypoint(
      lat: -37.81 + i * 0.001,
      lng: 144.96 + i * 0.001,
      timestamp: DateTime.utc(2026, 4, 1).add(Duration(seconds: i * 5)),
    ),
  );
  return Run(
    id: 'partial-1',
    startedAt: DateTime.utc(2026, 4, 1),
    duration: duration,
    distanceMetres: distanceMetres,
    track: track,
    source: RunSource.app,
    metadata: indoor ? const {'indoor_estimated': true} : null,
  );
}

void main() {
  group('evaluateInProgressPartial', () {
    test('null partial → outcome=none, no banner', () {
      final r = evaluateInProgressPartial(null);
      expect(r.outcome, InProgressOutcome.none);
      expect(r.recovered, isNull);
      expect(r.bannerMessage, isNull);
    });

    test('GPS partial above thresholds → recovered, banner', () {
      // 3 waypoints + 100 m distance — both thresholds met.
      final partial = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 90),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(r.recovered, isNotNull);
      expect(r.recovered!.metadata?['recovered_from_crash'], isTrue);
      expect(r.bannerMessage, contains('Recovered'));
      expect(r.bannerMessage, contains('100 m'));
    });

    test('GPS partial with only 2 waypoints → discarded (track too short)',
        () {
      final partial = _partial(
        distanceMetres: 100,
        duration: const Duration(seconds: 60),
        waypoints: 2,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(r.recovered, isNull);
      expect(r.bannerMessage, contains('Discarded'));
      expect(r.bannerMessage, contains('100 m'));
    });

    test('GPS partial under 50 m → discarded with distance summary', () {
      final partial = _partial(
        distanceMetres: 38,
        duration: const Duration(seconds: 30),
        waypoints: 5,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(r.bannerMessage,
          'Discarded a 38 m partial recording from a previous session.');
    });

    test('Indoor partial ≥ 60 s → recovered with duration summary', () {
      final partial = _partial(
        distanceMetres: 0,
        duration: const Duration(seconds: 90),
        indoor: true,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(r.bannerMessage, contains('Recovered'));
      expect(r.bannerMessage, contains('min'));
    });

    test('Indoor partial < 60 s → discarded with duration summary', () {
      final partial = _partial(
        distanceMetres: 0,
        duration: const Duration(seconds: 45),
        indoor: true,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
      expect(r.bannerMessage,
          'Discarded a 45 s partial recording from a previous session.');
    });

    test('Distance formatter: km when ≥ 1000 m', () {
      final partial = _partial(
        distanceMetres: 2300,
        duration: const Duration(minutes: 15),
        waypoints: 10,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
      expect(r.bannerMessage, contains('2.3 km'));
    });

    test('Edge: exactly 50 m / 3 waypoints → recovered (≥ thresholds)', () {
      final partial = _partial(
        distanceMetres: 50,
        duration: const Duration(seconds: 30),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.recovered);
    });

    test('Edge: 49 m → discarded (just below)', () {
      final partial = _partial(
        distanceMetres: 49,
        duration: const Duration(seconds: 30),
        waypoints: 3,
      );
      final r = evaluateInProgressPartial(partial);
      expect(r.outcome, InProgressOutcome.discarded);
    });
  });
}
