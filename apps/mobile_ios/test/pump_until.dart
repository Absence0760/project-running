import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Pump frames until [condition] holds, giving the REAL event loop a slice
/// between them.
///
/// Widget tests run on a fake clock, so an async chain that only resolves on
/// the real event loop — a stream cancel, a file write, a platform-channel
/// reply — makes no progress under `pump` alone; `tester.runAsync` is what
/// turns that loop. [timeout] is a FAILURE bound, not the wait itself: when it
/// expires the test fails naming what never happened, so a regression is loud
/// instead of being slept through. A fixed delay in this position is the flake
/// this replaces — see docs/architecture/decisions.md § 715.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String describe,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after ${timeout.inMilliseconds} ms waiting for '
          '$describe');
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

/// Complete a Finish hold on a mounted `RunScreen`, then wait for the stop
/// path it starts.
///
/// `HoldToStopButton` only fires `onHoldComplete` after an 800 ms
/// `Ticker`-driven hold, and driving that Ticker to the threshold under the
/// fake test clock is unreliable — so this asserts the button is present and
/// hit-testable (a real user can reach it) and invokes its wired callback,
/// the exact action a completed hold performs. That routes through the real
/// `_stop()`.
///
/// `onHoldComplete` is declared `VoidCallback` but wired straight to the async
/// `_stop`, so invoking it dynamically hands back that future — the one exact
/// completion signal, rather than a proxy for it. Everything `_stop` does is
/// ordered behind it: the local save lands before the screen leaves its
/// recording state, and the cloud push and live wind-down after. Pass [until]
/// for the cases where `_stop` deliberately does NOT finish — it parks on the
/// post-live visibility dialog until that dialog is answered.
Future<void> holdFinish(
  WidgetTester tester, {
  bool Function()? until,
  String describe = "the Finish hold's stop path to finish",
}) async {
  final btnFinder = find
      .byWidgetPredicate((w) => w.runtimeType.toString() == 'HoldToStopButton');
  expect(btnFinder.hitTestable(), findsOneWidget,
      reason: 'a hit-testable Finish button must be present while recording');
  final hitButton = btnFinder.hitTestable().evaluate().single.widget;

  var stopped = false;
  Object? stopFailure;
  await tester.runAsync(() async {
    // ignore: avoid_dynamic_calls
    final stopping = (hitButton as dynamic).onHoldComplete() as Future<void>;
    unawaited(stopping.then<void>(
      (_) => stopped = true,
      onError: (Object e) {
        stopFailure = e;
        stopped = true;
      },
    ));
  });
  await pumpUntil(tester, until ?? () => stopped, describe: describe);
  if (stopFailure != null) fail('the Finish hold threw: $stopFailure');
}
