import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart client for the native `RunNotificationBridge` method channel.
///
/// Overrides the geolocator foreground-service notification with live run
/// stats, so the lock screen shows time / distance / pace during a run.
/// See `android/app/src/main/kotlin/com/betterrunner/app/RunNotificationBridge.kt`
/// for the Android side (the native receiver reposts on geolocator's
/// channel id + notification id to replace rather than duplicate).
class RunNotificationBridge {
  static const _channel = MethodChannel('run_app/run_notification');

  /// Update the notification with the supplied stats. Safe to call from
  /// every snapshot — the native side just calls `NotificationManager.notify`
  /// which dedupes by id, and the phone's notification shade redraws
  /// cheaply. [bigText] is optional multi-line content shown when the
  /// user expands the notification.
  Future<void> update({
    required String title,
    required String text,
    String? bigText,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'text': text,
        if (bigText != null) 'big_text': bigText,
      });
    } catch (e) {
      debugPrint('RunNotificationBridge.update failed: $e');
    }
  }

  /// Cancel the replacement notification. Called from `_stop` and
  /// `_discard` in `run_screen` so the lock-screen row disappears the
  /// moment the run ends, even if the geolocator foreground-service
  /// teardown races the UI transition.
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (e) {
      debugPrint('RunNotificationBridge.clear failed: $e');
    }
  }
}
