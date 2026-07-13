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
  DateTime? savedAt,
}) {
  final track = List.generate(
    waypoints,
    (i) => Waypoint(
      lat: -37.81 + i * 0.001,
      lng: 144.96 + i * 0.001,
      timestamp: DateTime.utc(2026, 4, 1).add(Duration(seconds: i * 5)),
    ),
  );
  final metadata = <String, dynamic>{
    if (indoor) 'indoor_estimated': true,
    if (savedAt != null) 'in_progress_saved_at': savedAt.toIso8601String(),
  };
  return Run(
    id: 'partial-1',
    startedAt: DateTime.utc(2026, 4, 1),
    duration: duration,
    distanceMetres: distanceMetres,
    track: track,
    source: RunSource.app,
    metadata: metadata.isEmpty ? null : metadata,
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

    group('resumable (process-kill continuation)', () {
      final now = DateTime.utc(2026, 4, 3, 12);

      test('recent qualifying GPS partial → resumable, no banner', () {
        // Saved 6 h ago — a canyon dead-zone stretch. The runner reopens the
        // app; the partial should be offered for resume, not finalized.
        final partial = _partial(
          distanceMetres: 187000,
          duration: const Duration(hours: 40),
          waypoints: 5,
          savedAt: now.subtract(const Duration(hours: 6)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
        expect(r.resumablePartial, isNotNull);
        expect(r.resumablePartial!.id, partial.id,
            reason: 'the raw partial is handed back so resume keeps the id');
        expect(r.recovered, isNull);
        // Interactive prompt on the run screen, not a passive banner.
        expect(r.bannerMessage, isNull);
      });

      test('recent qualifying indoor partial → resumable', () {
        final partial = _partial(
          distanceMetres: 0,
          duration: const Duration(minutes: 20),
          indoor: true,
          savedAt: now.subtract(const Duration(minutes: 30)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('stale qualifying partial (> 48 h) → recovered, not resumable', () {
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
          savedAt: now.subtract(const Duration(hours: 72)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.recovered,
            reason: 'a days-old abandoned partial still auto-finalizes');
        expect(r.resumablePartial, isNull);
        expect(r.bannerMessage, contains('Recovered'));
      });

      test('boundary: exactly at the window edge → resumable', () {
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
          savedAt: now.subtract(kResumableWindow),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.resumable);
      });

      test('recent but below content threshold → still discarded', () {
        // Recency never rescues a sub-threshold partial — the content gate
        // runs first.
        final partial = _partial(
          distanceMetres: 30,
          duration: const Duration(seconds: 20),
          waypoints: 5,
          savedAt: now.subtract(const Duration(minutes: 1)),
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.discarded);
      });

      test('no in_progress_saved_at stamp → finalizes (recovered), never resumable',
          () {
        // Unknown-age partial: preserve the pre-fix behaviour rather than
        // prompt a resume for a run whose age we can't establish.
        final partial = _partial(
          distanceMetres: 5000,
          duration: const Duration(minutes: 40),
          waypoints: 10,
        );
        final r = evaluateInProgressPartial(partial, now: now);
        expect(r.outcome, InProgressOutcome.recovered);
      });
    });
  });
}
