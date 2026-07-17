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

  test('updateSplit posts over the dedicated update_split method (#303)',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = RunNotificationBridge();
    await bridge.updateSplit(title: 'Run', text: '1.0 km — 5:30 /km');
    await bridge.updateSplit(title: 'Run', text: '2.0 km — 5:25 /km');

    final splits = calls.where((c) => c.method == 'update_split').toList();
    expect(splits, hasLength(2),
        reason: 'every split routes through update_split — the native '
            'side reposts on ONE fixed id so the row replaces in place');
    expect((splits.first.arguments as Map)['text'], '1.0 km — 5:30 /km');
    expect((splits.last.arguments as Map)['title'], 'Run');
    expect(calls.where((c) => c.method == 'update'), isEmpty,
        reason: 'the split row must not touch the ongoing-run id');
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('clearSplit sends clear_split (#303)', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = RunNotificationBridge();
    await bridge.clearSplit();
    expect(calls.map((c) => c.method), contains('clear_split'));
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('updateSplit and clearSplit swallow platform errors (L4)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'no_permission');
    });
    final bridge = RunNotificationBridge();
    await bridge.updateSplit(title: 'Run', text: 'x');
    await bridge.clearSplit();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
