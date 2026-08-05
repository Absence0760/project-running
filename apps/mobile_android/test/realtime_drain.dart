import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [testWidgets] that also drains the realtime disconnect timer.
///
/// `realtime_client` arms a 50 s pending disconnect from *inside*
/// `RealtimeChannel.unsubscribe`, and a screen calls that from `dispose` — so
/// the timer does not exist until the tree is torn down, and no amount of
/// pumping inside the test body can drain it. Every screen holding a channel
/// therefore fails `!timersPending` on teardown unless the test unmounts and
/// pumps past it, which is what this wrapper does after [body] returns.
void realtimeWidgetTest(
  String description,
  WidgetTesterCallback body, {
  bool? skip,
  Timeout? timeout,
}) {
  testWidgets(
    description,
    (tester) async {
      await body(tester);
      await drainRealtimeTimers(tester);
    },
    skip: skip,
    timeout: timeout,
  );
}

/// Unmount whatever is mounted, then pump past the disconnect timer. Exposed
/// for tests that already tear down explicitly rather than through
/// [realtimeWidgetTest].
Future<void> drainRealtimeTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 60));
}
