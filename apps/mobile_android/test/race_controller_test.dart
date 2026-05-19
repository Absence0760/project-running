// Unit tests for `lib/race_controller.dart`'s pure-data + state-
// transition surface.
//
// RaceController wraps Supabase realtime + REST calls so the full
// `start()` / `_refresh()` paths need a live local stack. This file
// scopes to:
//
//   - `ActiveRace` data class + `isArmed` / `isRunning` getters
//   - `_setActive` change-detection (via the @visibleForTesting
//     hook) — covers the 4 fields that make up an ActiveRace's
//     observable identity
//   - `attachRecorder` / `detachRecorder` state mutation
//
// The full network-backed flow (`_refresh`, `pushPing`'s insert,
// `submitResult`'s RPC) is left to the integration tests that hit a
// real local Supabase.
//
// One bug surfaced + fixed while writing this:
//
//   The original `_setActive` compared `eventId`, `status`,
//   `startedAt` — but not `instanceStart`. A back-to-back armed
//   transition between two instances of the same recurring event
//   (Instance 1 finishes → Instance 2 immediately armed, same
//   eventId + 'armed' + null startedAt) silently updated `_active`
//   without firing notifyListeners. Banner UI rendered Instance
//   1's time until another field changed or the screen rebuilt. Fix
//   was a one-line addition of `next?.instanceStart !=
//   _active?.instanceStart` to the changed predicate. Pinned by the
//   "back-to-back instance switch fires notifyListeners" test
//   below.

import 'package:flutter_test/flutter_test.dart';

import '../lib/race_controller.dart';
import '../lib/social_service.dart';

ActiveRace race({
  String eventId = 'event-1',
  DateTime? instanceStart,
  String status = 'armed',
  DateTime? startedAt,
  String? eventTitle = 'Thursday 10K',
}) =>
    ActiveRace(
      eventId: eventId,
      instanceStart: instanceStart ?? DateTime.utc(2026, 5, 22, 18, 0, 0),
      status: status,
      startedAt: startedAt,
      eventTitle: eventTitle,
    );

void main() {
  group('ActiveRace.isArmed / isRunning', () {
    test('isArmed is true only for status == "armed"', () {
      // The banner gates on this getter. A regression to a string-
      // case-insensitive comparison or substring-match would let an
      // intermediate status (e.g. "arming") render the armed banner.
      expect(race(status: 'armed').isArmed, isTrue);
      expect(race(status: 'running').isArmed, isFalse);
      expect(race(status: 'finished').isArmed, isFalse);
      expect(race(status: 'cancelled').isArmed, isFalse);
    });

    test('isRunning is true only for status == "running"', () {
      expect(race(status: 'running').isRunning, isTrue);
      expect(race(status: 'armed').isRunning, isFalse);
      expect(race(status: 'finished').isRunning, isFalse);
      expect(race(status: 'cancelled').isRunning, isFalse);
    });

    test('isArmed and isRunning are mutually exclusive', () {
      // The four documented statuses are pairwise disjoint; a regression
      // that loosened either getter (e.g. accepted 'armed' OR
      // 'running' for isArmed) would let the run screen render two
      // banners for the same race.
      for (final status in ['armed', 'running', 'finished', 'cancelled']) {
        final r = race(status: status);
        expect(
          r.isArmed && r.isRunning,
          isFalse,
          reason: 'status=$status should not satisfy both getters',
        );
      }
    });

    test('unknown status returns false for both getters', () {
      // Defensive: a future status (e.g. 'paused' if the feature
      // extends) must not silently flip an existing getter on. Both
      // must explicitly return false until updated.
      final r = race(status: 'paused');
      expect(r.isArmed, isFalse);
      expect(r.isRunning, isFalse);
    });
  });

  group('RaceController state transitions', () {
    test('initial state has no active race', () {
      final c = RaceController(SocialService());
      expect(c.active, isNull);
    });

    test('attachRecorder + detachRecorder do not touch active', () {
      // The hosting state (event being recorded against) is separate
      // from the active-race state (event observed via realtime).
      // A regression that wired attachRecorder to also set _active
      // would surface a stale banner after detach — the active race
      // is gone but the controller still thinks one's hosted.
      final c = RaceController(SocialService());
      final before = c.active;
      c.attachRecorder(
        eventId: 'event-1',
        instance: DateTime.utc(2026, 5, 22),
      );
      expect(c.active, before, reason: 'attachRecorder must not mutate active');
      c.detachRecorder();
      expect(c.active, before, reason: 'detachRecorder must not mutate active');
    });
  });

  group('_setActive change-detection (via @visibleForTesting hook)', () {
    test('null → non-null fires notifyListeners', () {
      final c = RaceController(SocialService());
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(race());
      expect(notifyCount, 1);
      expect(c.active, isNotNull);
    });

    test('non-null → null fires notifyListeners', () {
      final c = RaceController(SocialService());
      c.setActiveForTest(race());
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(null);
      expect(notifyCount, 1);
      expect(c.active, isNull);
    });

    test('identical ActiveRace does NOT fire notifyListeners', () {
      // The whole point of change-detection: polling refresh-loops
      // emit the same race state multiple times. Without the gate
      // every poll would notify, causing the banner to re-render +
      // every observer to thrash 60×/min.
      final c = RaceController(SocialService());
      final r = race();
      c.setActiveForTest(r);
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(race()); // construct an equivalent value
      expect(notifyCount, 0);
    });

    test('status change (armed → running) fires notifyListeners', () {
      // The headline transition: organiser hits GO and the controller
      // must notify so the banner flips from "Race armed" to "Race
      // running". A regression in the status check would freeze the
      // banner mid-flip.
      final c = RaceController(SocialService());
      c.setActiveForTest(race(status: 'armed'));
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(race(status: 'running'));
      expect(notifyCount, 1);
      expect(c.active!.isRunning, isTrue);
    });

    test('startedAt change fires notifyListeners', () {
      // Mid-race the started_at field is the source-of-truth for the
      // elapsed clock the banner ticks. A regression in this check
      // would freeze the elapsed display.
      final c = RaceController(SocialService());
      c.setActiveForTest(race(status: 'running', startedAt: null));
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(
        race(status: 'running', startedAt: DateTime.utc(2026, 5, 22, 18, 5, 0)),
      );
      expect(notifyCount, 1);
    });

    test('eventId change (different event) fires notifyListeners', () {
      // Two separate races back-to-back (an evening event finishes →
      // a different event's race arms within the same hour).
      final c = RaceController(SocialService());
      c.setActiveForTest(race(eventId: 'event-1'));
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.setActiveForTest(race(eventId: 'event-2'));
      expect(notifyCount, 1);
    });

    // ── The bug-pin test ─────────────────────────────────────────
    test('instanceStart change with same event + status fires notifyListeners', () {
      // Regression pin for the bug fixed in this commit:
      //
      // Recurring event has back-to-back armed instances (Instance 1
      // finishes → Instance 2 armed immediately, same eventId, same
      // 'armed' status, both null startedAt). The original
      // _setActive only compared eventId / status / startedAt and
      // silently swapped instanceStart without notifying. The
      // banner would render Instance 1's time until something else
      // triggered a rebuild.
      //
      // Adding `next?.instanceStart != _active?.instanceStart` to the
      // changed predicate closes the gap.
      final c = RaceController(SocialService());
      c.setActiveForTest(race(
        eventId: 'recurring-1',
        instanceStart: DateTime.utc(2026, 5, 22, 18, 0, 0), // Thursday
        status: 'armed',
        startedAt: null,
      ));
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      // Same event, same status, same null startedAt, DIFFERENT instance.
      c.setActiveForTest(race(
        eventId: 'recurring-1',
        instanceStart: DateTime.utc(2026, 5, 29, 18, 0, 0), // next Thursday
        status: 'armed',
        startedAt: null,
      ));
      expect(notifyCount, 1,
          reason: 'instanceStart switch must notify so banner re-renders');
      expect(
        c.active!.instanceStart,
        DateTime.utc(2026, 5, 29, 18, 0, 0),
      );
    });
  });
}
