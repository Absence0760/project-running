import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pushes the current Supabase session to the paired Wear OS watch whenever
/// it changes. The native side (`WearAuthBridge.kt`) forwards to the
/// Wearable Data Layer — watch_wear's `SessionBridge` picks it up on the
/// other end and caches it into its own DataStore.
///
/// Call [attach] once after `Supabase.initialize` in `main.dart`. Pass the
/// same `url` + `anonKey` so the watch ends up talking to the same backend
/// the phone is talking to.
class WearAuthBridge {
  static const _channel = MethodChannel('run_app/wear_auth');

  StreamSubscription<AuthState>? _sub;

  void attach({required String url, required String anonKey}) {
    final auth = Supabase.instance.client.auth;

    // Push whatever's current right now — handles the common "phone already
    // signed in, wear app launched later" case.
    final current = auth.currentSession;
    if (current != null) {
      _push(current, url: url, anonKey: anonKey);
    }

    _sub = auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (session == null) {
        _clear();
      } else {
        _push(session, url: url, anonKey: anonKey);
      }
    });
  }

  void detach() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _push(
    Session session, {
    required String url,
    required String anonKey,
  }) async {
    try {
      await _channel.invokeMethod<void>('push', {
        'access_token': session.accessToken,
        'refresh_token': session.refreshToken ?? '',
        'user_id': session.user.id,
        'base_url': url,
        'anon_key': anonKey,
        'expires_at_ms': (session.expiresAt ?? 0) * 1000,
      });
    } on PlatformException {
      // Wearable Data Layer unavailable (no Google Play services on the
      // device). Silently ignore — phone functionality is unaffected.
    } on MissingPluginException {
      // Not running on Android, or the native plugin hasn't registered yet.
    }
  }

  Future<void> _clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // no-op
    } on MissingPluginException {
      // no-op
    }
  }
}
