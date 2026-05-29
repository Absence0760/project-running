import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart client for the native `RunNotificationBridge` method channel.
///
/// Overrides the geolocator foreground-service notification with live run
/// stats, so the lock screen shows time / distance / pace during a run.
/// See `android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt`
/// for the Android side (the native receiver reposts on geolocator's
/// channel id + notification id to replace rather than duplicate).
class RunNotificationBridge {
  static const _channel = MethodChannel('run_app/run_notification');

  /// Lock-screen action callbacks (Android #14). The native side renders
  /// Pause/Resume + Stop buttons on the foreground-service notification;
  /// tapping one launches MainActivity with a `run_action` extra, which
  /// forwards here over the same channel. The run screen wires these to
  /// the recorder. Null on iOS (the channel has no native handler there,
  /// so the buttons never exist and these never fire).
  void Function()? onPause;
  void Function()? onResume;
  void Function()? onStop;

  RunNotificationBridge() {
    _channel.setMethodCallHandler(_handleNativeCall);
    // Tell the native side the Dart handler is live so any action that
    // arrived during a cold start (process relaunched by tapping the
    // notification) is flushed now instead of dropped.
    _channel.invokeMethod<void>('ready').catchError((Object _) {});
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'action') {
      switch (call.arguments as String?) {
        case 'pause':
          onPause?.call();
          break;
        case 'resume':
          onResume?.call();
          break;
        case 'stop':
          onStop?.call();
          break;
      }
    }
    return null;
  }

  /// Update the notification with the supplied stats. Safe to call from
  /// every snapshot — the native side just calls `NotificationManager.notify`
  /// which dedupes by id, and the phone's notification shade redraws
  /// cheaply. [bigText] is optional multi-line content shown when the
  /// user expands the notification. [paused] flips the Pause action to
  /// Resume so the lock-screen control matches the recorder state.
  Future<void> update({
    required String title,
    required String text,
    String? bigText,
    bool paused = false,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'text': text,
        if (bigText != null) 'big_text': bigText,
        'paused': paused,
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
