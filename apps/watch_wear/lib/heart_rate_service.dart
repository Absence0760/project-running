import 'dart:async';

import 'package:flutter/services.dart';

/// Wraps the native Wear OS Health Services measure client.
///
/// Call [start] when a run begins; `bpm` fires once per sample the sensor
/// produces (typically every 1–3 seconds during activity). Call [stop]
/// when the run ends. On non–Wear-OS targets or on devices without Health
/// Services, `start` silently fails and the stream stays empty.
class HeartRateService {
  static const _methodChannel = MethodChannel('watch_wear/hr');
  static const _eventChannel = EventChannel('watch_wear/hr/stream');

  Stream<int>? _bpm;

  Stream<int> get bpm =>
      _bpm ??= _eventChannel.receiveBroadcastStream().map<int?>((event) {
        if (event is Map && event['bpm'] is num) {
          return (event['bpm'] as num).round();
        }
        return null;
      }).where((v) => v != null).cast<int>();

  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod<void>('start');
    } on PlatformException {
      // Health Services unavailable; keep running without HR.
    } on MissingPluginException {
      // Not running on Wear OS (e.g. desktop / test host).
    }
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on PlatformException {
      // no-op
    } on MissingPluginException {
      // no-op
    }
  }
}
