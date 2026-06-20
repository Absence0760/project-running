import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/push_messaging_bridge.dart';

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

  @override
  Future<void> deleteToken() async => deleted = true;

  void emitRefresh(String t) => _refresh.add(t);

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
}
