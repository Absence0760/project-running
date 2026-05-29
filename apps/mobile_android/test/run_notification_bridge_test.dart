import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/run_notification_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('run_app/run_notification');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendNative(String method, [dynamic args]) {
    return messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('routes lock-screen actions to the matching callback (#14)', () async {
    final bridge = RunNotificationBridge();
    final fired = <String>[];
    bridge.onPause = () => fired.add('pause');
    bridge.onResume = () => fired.add('resume');
    bridge.onStop = () => fired.add('stop');

    await sendNative('action', 'pause');
    await sendNative('action', 'resume');
    await sendNative('action', 'stop');
    await sendNative('action', 'bogus'); // unknown → ignored
    await sendNative('action', null); // null → ignored, no throw

    expect(fired, ['pause', 'resume', 'stop']);
  });

  test('a null callback is a safe no-op', () async {
    final bridge = RunNotificationBridge();
    bridge.onPause = null;
    // Must not throw when no handler is wired.
    await sendNative('action', 'pause');
  });

  test('update forwards the paused flag to the channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = RunNotificationBridge();
    await bridge.update(title: 'Run', text: 'stats', paused: true);
    final update = calls.firstWhere((c) => c.method == 'update');
    expect((update.arguments as Map)['paused'], true);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
