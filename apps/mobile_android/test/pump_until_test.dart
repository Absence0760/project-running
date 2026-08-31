// The wait helper every § 715 / § 723 conversion is built on, tested itself.
//
// `pumpUntil` and `holdFinish` are the synchronisation for dozens of widget
// tests across this suite. Nothing pinned them, so a regression in either
// would have made those tests pass for the wrong reason rather than fail —
// a condition evaluated once, a deadline that never fires, a `holdFinish`
// that returns before the stop path it exists to wait for. Each case below
// is one property the callers rely on and would not notice losing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart' show HoldToStopButton;
import 'pump_until.dart';

/// A host whose text only changes when a REAL-event-loop future completes,
/// so a wait that never turns that loop can never see it.
class _RealAsyncFlag extends StatefulWidget {
  const _RealAsyncFlag({required this.trigger});

  final Future<void> trigger;

  @override
  State<_RealAsyncFlag> createState() => _RealAsyncFlagState();
}

class _RealAsyncFlagState extends State<_RealAsyncFlag> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.trigger.then((_) {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(_done ? 'settled' : 'pending'),
      );
}

Widget _holdHost(VoidCallback onHoldComplete, {bool reachable = true}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: IgnorePointer(
            ignoring: !reachable,
            child: HoldToStopButton(
              onHoldComplete: onHoldComplete,
              showHint: false,
            ),
          ),
        ),
      ),
    );

void main() {
  group('pumpUntil — the condition is the wait', () {
    testWidgets('a condition that already holds costs no loop turn',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      var evaluated = 0;
      await pumpUntil(tester, () {
        evaluated++;
        return true;
      }, describe: 'nothing');

      expect(evaluated, 1,
          reason: 'the predicate is checked before the first slice, so an '
              'already-true condition returns without turning the loop');
    });

    testWidgets('it spins on the real event loop until the condition flips',
        (tester) async {
      var flipped = false;
      var evaluated = 0;
      await tester.runAsync(() async {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 80))
            .then((_) => flipped = true));
      });

      await pumpUntil(tester, () {
        evaluated++;
        return flipped;
      }, describe: 'the real-loop future to complete');

      expect(flipped, isTrue);
      expect(evaluated, greaterThan(1),
          reason: 'the condition was false at least once — a wait whose '
              'predicate is true on the first evaluation has converted '
              'nothing (decisions § 723)');
    });

    testWidgets('a frame is pumped between slices, so real-async setState '
        'reaches the screen', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(_RealAsyncFlag(trigger: gate.future));
      expect(find.text('pending'), findsOneWidget);

      await tester.runAsync(() async {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 40))
            .then((_) => gate.complete()));
      });
      await pumpUntil(tester, () => find.text('settled').evaluate().isNotEmpty,
          describe: 'the flag widget to rebuild');

      expect(find.text('settled'), findsOneWidget,
          reason: 'without the pump() inside the loop the widget tree never '
              'rebuilds and a UI-state predicate can never hold');
    });

    testWidgets('the deadline fails naming the condition, rather than hanging',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      Object? thrown;
      final started = DateTime.now();
      try {
        await pumpUntil(tester, () => false,
            describe: 'a condition that never holds',
            timeout: const Duration(milliseconds: 300));
      } catch (e) {
        thrown = e;
      }
      final elapsed = DateTime.now().difference(started);

      expect(thrown, isA<TestFailure>(),
          reason: 'an expired deadline must FAIL — a helper that returns '
              'quietly hands the next assertion a screen that never got '
              'there and reports the wrong thing');
      expect('$thrown', contains('a condition that never holds'),
          reason: 'the message has to say which condition never held; that '
              'is the whole reason describe is required');
      expect('$thrown', contains('300'),
          reason: 'the bound it gave up at belongs in the message');
      expect(elapsed.inSeconds, lessThan(5),
          reason: 'it gives up at its own deadline rather than running on');
    });

    testWidgets('the fake clock is never advanced by the wait', (tester) async {
      // Documented limit (§ 723): no route transition, animation or dialog
      // dismissal can be a pumpUntil predicate, because the helper turns the
      // REAL loop and leaves fake timers exactly where it found them. A
      // future edit that "helpfully" pumped a duration here would also fire
      // whatever unrelated timer the screen under test has armed.
      await tester.pumpWidget(const SizedBox.shrink());
      var fakeTimerFired = false;
      final timer = Timer(const Duration(seconds: 5), () {
        fakeTimerFired = true;
      });

      var spins = 0;
      await pumpUntil(tester, () => spins++ > 8,
          describe: 'a few real-loop slices');
      timer.cancel();

      expect(fakeTimerFired, isFalse,
          reason: 'pumpUntil must not advance the fake clock');
    });
  });

  group('holdFinish — the stop path is what is waited for', () {
    testWidgets('it fails when there is no Finish button to hold',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      Object? thrown;
      try {
        await holdFinish(tester);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<TestFailure>(),
          reason: 'a screen with no Finish button is a regression, not a '
              'test that should quietly do nothing');
    });

    testWidgets('a Finish button no real user could press is not a Finish '
        'button', (tester) async {
      await tester.pumpWidget(_holdHost(() {}, reachable: false));
      Object? thrown;
      try {
        await holdFinish(tester);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<TestFailure>(),
          reason: 'hit-testability is the property asserted — an unreachable '
              'stop control fails the run for the runner too');
    });

    testWidgets('it waits for the future the callback hands back',
        (tester) async {
      var landed = false;
      await tester.pumpWidget(_holdHost(() async {
        // The shape of `_stop`: real-loop work the fake clock cannot drain,
        // with everything the callers assert on ordered behind it.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        landed = true;
      }));

      final stopped = await holdFinish(tester);

      expect(landed, isTrue,
          reason: 'holdFinish returning before the stop path finished is '
              'exactly the race § 715 replaced a fixed 200 ms sleep to fix');
      expect(stopped(), isTrue);
    });

    testWidgets('a stop path that throws is reported, not swallowed',
        (tester) async {
      await tester.pumpWidget(_holdHost(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        throw StateError('save failed');
      }));

      Object? thrown;
      try {
        await holdFinish(tester);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<TestFailure>());
      expect('$thrown', contains('save failed'),
          reason: 'a stop path that blew up must not read as a stop path '
              'that completed');
    });

    testWidgets('until lets a caller wait for a nearer signal, and the '
        'returned predicate still reports the stop path', (tester) async {
      final released = Completer<void>();
      var reachedDialog = false;
      await tester.pumpWidget(_holdHost(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        reachedDialog = true;
        // The visibility dialog case: `_stop` parks until the runner answers.
        await released.future;
      }));

      final stopped = await holdFinish(
        tester,
        until: () => reachedDialog,
        describe: 'the keep-public dialog to appear',
      );
      expect(stopped(), isFalse,
          reason: 'the stop path is deliberately still parked — a caller '
              'that treated `until` as completion would assert against a '
              'half-finished screen');

      await tester.runAsync(() async => released.complete());
      await pumpUntil(tester, stopped,
          describe: 'the stop path to finish once the dialog is answered');
      expect(stopped(), isTrue);
    });

    testWidgets('the deadline names the caller-supplied description',
        (tester) async {
      await tester.pumpWidget(_holdHost(() async {
        await Completer<void>().future;
      }));

      Object? thrown;
      try {
        await holdFinish(tester,
            until: () => false,
            describe: 'a stop signal that never arrives');
      } catch (e) {
        thrown = e;
      }
      expect('$thrown', contains('a stop signal that never arrives'));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
