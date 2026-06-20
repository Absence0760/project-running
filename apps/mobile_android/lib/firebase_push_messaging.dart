import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_messaging_bridge.dart';

/// Best-effort Firebase init for native push, called once at startup. Succeeds
/// only when the operator's native Firebase config (`google-services.json` /
/// `GoogleService-Info.plist`) is present — without it `Firebase.initializeApp`
/// throws and push runs disabled (the [FirebasePushMessaging] no-ops). Never
/// rethrows: a missing/invalid config must not break app startup.
Future<void> initFirebaseForPush() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('initFirebaseForPush: Firebase not configured; push disabled: $e');
  }
}

/// Production [PushMessaging] over `firebase_messaging`. Every call is gated on
/// Firebase having been initialised (`Firebase.apps.isNotEmpty`) so a build
/// without the operator's `google-services.json` / `GoogleService-Info.plist`
/// runs as a complete no-op — [isAvailable] is false and [PushMessagingBridge]
/// never wires anything. This is the fail-closed credential gate: the code
/// ships now; delivery turns on when the operator adds the Firebase artifacts.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging();

  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isAvailable => _firebaseReady;

  @override
  Future<bool> requestPermission() async {
    if (!_firebaseReady) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('FirebasePushMessaging: requestPermission failed: $e');
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    if (!_firebaseReady) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FirebasePushMessaging: getToken failed: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh {
    if (!_firebaseReady) return const Stream.empty();
    try {
      return FirebaseMessaging.instance.onTokenRefresh;
    } catch (e) {
      debugPrint('FirebasePushMessaging: onTokenRefresh failed: $e');
      return const Stream.empty();
    }
  }

  @override
  Stream<PushOpenedMessage> get onMessageOpenedApp {
    if (!_firebaseReady) return const Stream.empty();
    try {
      return FirebaseMessaging.onMessageOpenedApp.map(
        (m) => PushOpenedMessage(url: m.data['url'] as String?),
      );
    } catch (e) {
      debugPrint('FirebasePushMessaging: onMessageOpenedApp failed: $e');
      return const Stream.empty();
    }
  }

  @override
  Future<void> deleteToken() async {
    if (!_firebaseReady) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('FirebasePushMessaging: deleteToken failed: $e');
    }
  }
}
