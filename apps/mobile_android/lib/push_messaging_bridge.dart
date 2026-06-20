import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The device-led leg of the native-push channel (FCM / APNs). Registers this
/// device's push token on sign-in, re-registers on rotation, and forgets it on
/// sign-out so the next account on the device doesn't inherit pushes. The
/// server leg (the Go worker's `native_push` consumer) fans notifications out
/// over the registered tokens.
///
/// L4 auxiliary effect (decisions §… layered resilience): every platform-
/// channel call is wrapped so a push-init failure can NEVER break sign-in or
/// any core flow. When Firebase isn't configured on the device (no
/// `google-services.json` / `GoogleService-Info.plist`), [attach] is a
/// best-effort no-op — the app compiles + runs in dev without the operator's
/// Firebase artifacts (the credential gate; the artifacts are a deploy-time
/// checklist item, not a code dependency).
///
/// The actual `firebase_messaging` calls live behind the [PushMessaging] seam
/// so the bridge logic is unit-testable with a fake and so the production impl
/// can degrade to a no-op when Firebase isn't initialisable on this build.

/// The notification a tap opened, surfaced so the host can route the deep link.
class PushOpenedMessage {
  const PushOpenedMessage({this.url});

  /// The `url` data key the worker stamps (`pathForKind`) — the in-app target
  /// to route to. Null when the message carried no deep link.
  final String? url;
}

/// Transport-agnostic seam over `firebase_messaging`. The production impl wraps
/// the plugin; tests substitute a fake. Every method is best-effort — an impl
/// that can't reach Firebase returns the inert value (false / null / a
/// never-firing stream) rather than throwing.
abstract class PushMessaging {
  /// Whether Firebase is initialised + messaging is usable on this device.
  /// False → the bridge no-ops (dev without `google-services.json`).
  bool get isAvailable;

  /// Request the OS notification permission (Android 13+ runtime
  /// POST_NOTIFICATIONS, iOS APNs prompt). Returns whether it's granted.
  Future<bool> requestPermission();

  /// The current FCM registration token, or null when unavailable.
  Future<String?> getToken();

  /// Fires the new token whenever the platform rotates it.
  Stream<String> get onTokenRefresh;

  /// Fires when the user taps a notification that opened the app (background →
  /// foreground, or cold start). Carries the deep-link target.
  Stream<PushOpenedMessage> get onMessageOpenedApp;

  /// Delete the platform token (sign-out) so the device stops receiving pushes
  /// for the previous account.
  Future<void> deleteToken();
}

/// Wires device-token registration to auth state + a [PushMessaging] seam.
///
/// Call [attach] once after `Supabase.initialize` in `main.dart`, passing the
/// production [PushMessaging] impl (or a fake in tests) and the [ApiClient].
/// [onOpenNotification] receives a tap's deep link so the host can route it
/// through the existing in-app notification-target routing.
class PushMessagingBridge {
  PushMessagingBridge({
    required PushMessaging messaging,
    required ApiClient api,
    void Function(PushOpenedMessage)? onOpenNotification,
    String? appVersion,
  })  : _messaging = messaging,
        _api = api,
        _onOpenNotification = onOpenNotification,
        _appVersion = appVersion;

  /// The attached bridge, so a settings toggle can mirror the
  /// `push_notifications` choice down to this device's opt-in flag without
  /// threading the instance through every screen. Null until [attach] runs (or
  /// when push is unavailable). Best-effort — callers null-check.
  static PushMessagingBridge? instance;

  final PushMessaging _messaging;
  final ApiClient _api;
  final void Function(PushOpenedMessage)? _onOpenNotification;
  final String? _appVersion;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<PushOpenedMessage>? _openedSub;

  /// The token registered for the currently signed-in user, so sign-out can
  /// forget exactly it. Null when nothing is registered.
  String? _currentToken;

  @visibleForTesting
  String? get currentToken => _currentToken;

  void attach() {
    instance = this;
    // Gate the whole bridge on Firebase being usable — a build without the
    // operator's Firebase config files runs as a complete no-op.
    if (!_messaging.isAvailable) {
      debugPrint('PushMessagingBridge: messaging unavailable; no-op');
      return;
    }

    // Idempotent — a re-attach (reconnect) must not leak prior subscriptions.
    _authSub?.cancel();
    _refreshSub?.cancel();
    _openedSub?.cancel();

    // Re-register on platform token rotation.
    _refreshSub = _messaging.onTokenRefresh.listen((token) {
      _registerToken(token);
    });

    // Route a tap's deep link through the host.
    _openedSub = _messaging.onMessageOpenedApp.listen((msg) {
      try {
        _onOpenNotification?.call(msg);
      } catch (e) {
        debugPrint('PushMessagingBridge: open-notification routing failed: $e');
      }
    });

    final auth = Supabase.instance.client.auth;

    // Handle the already-signed-in case (app launched while a session exists).
    if (auth.currentSession != null) {
      _onSignedIn();
    }

    _authSub = auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          _onSignedIn();
        case AuthChangeEvent.signedOut:
          _onSignedOut();
        default:
          break;
      }
    });
  }

  void detach() {
    _authSub?.cancel();
    _authSub = null;
    _refreshSub?.cancel();
    _refreshSub = null;
    _openedSub?.cancel();
    _openedSub = null;
  }

  Future<void> _onSignedIn() async {
    try {
      // Best-effort permission ask — registration proceeds even if declined so
      // a later in-OS grant delivers without re-running this flow; the
      // is_notifications_enabled flag + the worker pref gate are the real
      // controls. A declined prompt simply means the OS won't display.
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('PushMessagingBridge: no FCM token available');
        return;
      }
      await _registerToken(token);
    } catch (e) {
      debugPrint('PushMessagingBridge: sign-in registration failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _api.registerDeviceToken(
        platform: Platform.isIOS ? 'ios' : 'android',
        token: token,
        appVersion: _appVersion,
        locale: _deviceLocaleTag(),
      );
      _currentToken = token;
    } catch (e) {
      debugPrint('PushMessagingBridge: registerDeviceToken failed: $e');
    }
  }

  Future<void> _onSignedOut() async {
    final token = _currentToken;
    _currentToken = null;
    try {
      // Forget the row for the signed-out user, then drop the platform token so
      // the next user on the device gets a fresh registration.
      if (token != null) {
        await _api.removeDeviceToken(token);
      }
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('PushMessagingBridge: sign-out cleanup failed: $e');
    }
  }

  /// Mirror the user's `push_notifications` choice down to this device's
  /// per-device opt-in flag, so the worker's fan-out filter
  /// (`is_notifications_enabled`) matches what the user toggled. Best-effort.
  Future<void> setNotificationsEnabled(bool enabled) async {
    final token = _currentToken;
    if (token == null) return;
    try {
      await _api.setDeviceNotificationsEnabled(token: token, enabled: enabled);
    } catch (e) {
      debugPrint('PushMessagingBridge: setNotificationsEnabled failed: $e');
    }
  }

  String _deviceLocaleTag() {
    try {
      return Platform.localeName;
    } catch (_) {
      return 'en';
    }
  }
}
