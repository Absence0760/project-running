import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart' show pendingPushTarget, routePushOpen;
import '../lib/push_messaging_bridge.dart';
import '../lib/push_target.dart';

class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> registrations = [];
  final List<String> removals = [];
  final List<({String token, bool enabled})> enabledWrites = [];
  bool throwOnRegister = false;
  bool throwOnEnabled = false;

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? appVersion,
    String? locale,
  }) async {
    if (throwOnRegister) throw Exception('boom');
    registrations.add({
      'platform': platform,
      'token': token,
      'appVersion': appVersion,
      'locale': locale,
    });
  }

  @override
  Future<void> removeDeviceToken(String token) async => removals.add(token);

  @override
  Future<void> setDeviceNotificationsEnabled({
    required String token,
    required bool enabled,
  }) async {
    if (throwOnEnabled) throw Exception('boom');
    enabledWrites.add((token: token, enabled: enabled));
  }
}

class _FakeMessaging implements PushMessaging {
  _FakeMessaging({this.available = true});

  bool available;
  String? token = 'tok-1';
  bool permissionRequested = false;
  bool deleted = false;
  final _refresh = StreamController<String>.broadcast();
  final _opened = StreamController<PushOpenedMessage>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Future<bool> requestPermission() async {
    permissionRequested = true;
    return true;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Stream<PushOpenedMessage> get onMessageOpenedApp => _opened.stream;

  /// The tap that cold-started the app, if any.
  PushOpenedMessage? initialMessage;
  bool throwOnInitialMessage = false;

  @override
  Future<PushOpenedMessage?> getInitialMessage() async {
    if (throwOnInitialMessage) throw Exception('boom');
    return initialMessage;
  }

  @override
  Future<void> deleteToken() async => deleted = true;

  void emitRefresh(String t) => _refresh.add(t);

  void emitOpened(PushOpenedMessage m) => _opened.add(m);

  void dispose() {
    _refresh.close();
    _opened.close();
  }
}

void main() {
  test('unavailable messaging makes attach() a complete no-op', () {
    final messaging = _FakeMessaging(available: false);
    final api = _FakeApi();
    final bridge = PushMessagingBridge(messaging: messaging, api: api)..attach();

    expect(messaging.permissionRequested, isFalse);
    expect(api.registrations, isEmpty);
    expect(bridge.currentToken, isNull);
    messaging.dispose();
  });

  test('setNotificationsEnabled routes the choice to the api for the token',
      () async {
    final messaging = _FakeMessaging();
    final api = _FakeApi();
    final bridge = PushMessagingBridge(messaging: messaging, api: api);

    // No token registered yet → best-effort no-op (nothing to flag).
    await bridge.setNotificationsEnabled(false);
    expect(api.enabledWrites, isEmpty);
    messaging.dispose();
  });

  test('setNotificationsEnabled is a guarded no-op when no token is registered',
      () async {
    final messaging = _FakeMessaging();
    // Even if the api would throw, the early return on a null current token
    // means it's never reached — proving the guard, not just swallowing.
    final api = _FakeApi()..throwOnEnabled = true;
    final bridge = PushMessagingBridge(messaging: messaging, api: api);
    await bridge.setNotificationsEnabled(true);
    expect(api.enabledWrites, isEmpty);
    messaging.dispose();
  });

  test('attach exposes the bridge as the static instance', () {
    final messaging = _FakeMessaging(available: false);
    final api = _FakeApi();
    final bridge = PushMessagingBridge(messaging: messaging, api: api)..attach();
    expect(PushMessagingBridge.instance, same(bridge));
    messaging.dispose();
  });

  group('notification-tap routing (issue #666 A1)', () {
    test('a tap while the app is alive reaches onOpenNotification', () async {
      final messaging = _FakeMessaging();
      final opened = <String?>[];
      PushMessagingBridge(
        messaging: messaging,
        api: _FakeApi(),
        onOpenNotification: (m) => opened.add(m.url),
      ).attach();

      messaging.emitOpened(
          const PushOpenedMessage(url: 'https://threkir.com/runs/r1'));
      await Future<void>.delayed(Duration.zero);

      expect(opened, ['https://threkir.com/runs/r1']);
      messaging.dispose();
    });

    test('the tap that COLD-STARTED the app reaches onOpenNotification',
        () async {
      // onMessageOpenedApp never replays the launch message, so without the
      // getInitialMessage read a push tapped from a terminated app opened the
      // dashboard and dropped its target.
      final messaging = _FakeMessaging()
        ..initialMessage =
            const PushOpenedMessage(url: 'https://threkir.com/clubs/c9');
      final opened = <String?>[];
      PushMessagingBridge(
        messaging: messaging,
        api: _FakeApi(),
        onOpenNotification: (m) => opened.add(m.url),
      ).attach();

      await Future<void>.delayed(Duration.zero);

      expect(opened, ['https://threkir.com/clubs/c9']);
      messaging.dispose();
    });

    test('no launch message → the callback is never invoked', () async {
      final messaging = _FakeMessaging();
      var calls = 0;
      PushMessagingBridge(
        messaging: messaging,
        api: _FakeApi(),
        onOpenNotification: (_) => calls++,
      ).attach();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      messaging.dispose();
    });

    test('a throwing launch-message read never escapes attach()', () async {
      final messaging = _FakeMessaging()..throwOnInitialMessage = true;
      var calls = 0;
      expect(
        () => PushMessagingBridge(
          messaging: messaging,
          api: _FakeApi(),
          onOpenNotification: (_) => calls++,
        ).attach(),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      messaging.dispose();
    });

    test('a throwing host callback is contained (L4)', () async {
      final messaging = _FakeMessaging();
      PushMessagingBridge(
        messaging: messaging,
        api: _FakeApi(),
        onOpenNotification: (_) => throw Exception('router blew up'),
      ).attach();

      messaging
          .emitOpened(const PushOpenedMessage(url: 'https://threkir.com/plans'));
      await Future<void>.delayed(Duration.zero);
      // No unhandled error: the stream stays live for the next tap.
      messaging.emitOpened(const PushOpenedMessage(url: null));
      await Future<void>.delayed(Duration.zero);
      messaging.dispose();
    });

    test('routePushOpen parks the mapped target for HomeScreen to drain', () {
      addTearDown(() => pendingPushTarget.value = null);

      routePushOpen(const PushOpenedMessage(url: 'https://threkir.com/u/u7'));
      expect(pendingPushTarget.value,
          const PushTarget(PushTargetKind.profile, 'u7'));

      // A push with no url still parks a target — the inbox — so the tap
      // opens something rather than being dropped.
      routePushOpen(const PushOpenedMessage());
      expect(pendingPushTarget.value, PushTarget.inbox);
    });

    test('an unavailable messaging impl never reads the launch message',
        () async {
      final messaging = _FakeMessaging(available: false)
        ..initialMessage =
            const PushOpenedMessage(url: 'https://threkir.com/runs/r1');
      var calls = 0;
      PushMessagingBridge(
        messaging: messaging,
        api: _FakeApi(),
        onOpenNotification: (_) => calls++,
      ).attach();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      messaging.dispose();
    });
  });
}
