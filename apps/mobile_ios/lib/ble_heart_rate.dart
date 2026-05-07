import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE chest-strap heart-rate reader.
///
/// Uses the standard BLE Heart Rate Service (0x180D) and the Heart Rate
/// Measurement characteristic (0x2A37). Every conforming strap on the
/// market (Polar H9/H10, Garmin HRM-Pro/Dual, Wahoo Tickr, Coospo, etc.)
/// exposes these exact UUIDs — `service discovery → subscribe → notify`
/// is identical across vendors.
///
/// Backed by `flutter_reactive_ble` (BSD-3-Clause). The previous
/// `flutter_blue_plus` 1.x backend was MIT but its 2.x release switched
/// to a custom license requiring per-call License.free / License.commercial,
/// which is a project-licensing decision rather than a dep bump. Switching
/// packages here removes the licensing surface entirely. /audit/all
/// 2026-05-07.
///
/// The strap's id is persisted in SharedPreferences after the user pairs
/// once, so subsequent runs auto-reconnect silently.
///
/// `stream` emits on every notification (usually 1Hz) while connected.
/// Callers collect into a running list for `avg_bpm` computation and
/// render `current` in the live run UI. If the connection drops mid-run
/// we stop forwarding bytes until it's restored — distance/pace keep
/// going.
class BleHeartRate {
  static const String _prefsDeviceId = 'ble_hr_device_id';
  static const String _prefsDeviceName = 'ble_hr_device_name';

  static final Uuid _heartRateService =
      Uuid.parse('0000180d-0000-1000-8000-00805f9b34fb');
  static final Uuid _heartRateMeasurement =
      Uuid.parse('00002a37-0000-1000-8000-00805f9b34fb');

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  String? _deviceId;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  /// Live stream of BPM readings. Open-ended — stays subscribed until
  /// [stop] is called or the process dies.
  Stream<int> get stream => _controller.stream;

  /// Scan for BLE strap candidates advertising the Heart Rate Service.
  /// Emits a de-duplicated list as more devices are discovered. Stops
  /// scanning after [timeout]. Caller typically shows a bottom sheet
  /// with the list and lets the user tap the one they want.
  Stream<List<BleDeviceCandidate>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final controller = StreamController<List<BleDeviceCandidate>>.broadcast();
    final found = <String, BleDeviceCandidate>{};
    StreamSubscription<DiscoveredDevice>? sub;
    Timer? timer;

    sub = _ble.scanForDevices(
      withServices: [_heartRateService],
      scanMode: ScanMode.lowLatency,
    ).listen((d) {
      // The platform layer already filters by service UUID. Some
      // straps advertise a missing-name beacon between bonded packets;
      // include them keyed by id so the user can still see the rssi
      // and pick (we'll use the id as the display name fallback).
      found[d.id] = BleDeviceCandidate(
        id: d.id,
        name: d.name.isNotEmpty ? d.name : d.id,
        rssi: d.rssi,
      );
      if (!controller.isClosed) {
        controller.add(found.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi)));
      }
    }, onError: (Object e) {
      // The scan stream emits errors when the user toggles BT off
      // mid-scan or revokes the runtime BT permission. Without an
      // onError handler, the rejection becomes an unhandled async
      // error. Forward to the broadcast controller so the caller's
      // bottom-sheet can dismiss cleanly.
      debugPrint('BLE scanForDevices error: $e');
      if (!controller.isClosed) controller.addError(e);
    });

    timer = Timer(timeout, () async {
      await sub?.cancel();
      if (!controller.isClosed) await controller.close();
    });
    controller.onCancel = () async {
      timer?.cancel();
      await sub?.cancel();
    };
    return controller.stream;
  }

  /// Pair with [device] — stores its id for auto-reconnect + connects
  /// immediately. Subsequent app launches will call [connectCached]
  /// without user interaction.
  Future<void> pair(BleDeviceCandidate device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceId, device.id);
    await prefs.setString(_prefsDeviceName, device.name);
    await _connect(device.id);
  }

  /// Last-paired strap's display name, or null if never paired. The
  /// Settings screen uses this to show the current strap.
  Future<String?> pairedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsDeviceName);
  }

  /// Reconnect to the previously paired strap (if any). Called at the
  /// start of a run so live HR is ready when recording begins. No-op
  /// when no strap has been paired — the run just records without HR.
  Future<bool> connectCached() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsDeviceId);
    if (id == null) return false;
    try {
      await _connect(id);
      return true;
    } catch (e) {
      debugPrint('BLE cached reconnect failed: $e');
      return false;
    }
  }

  Future<void> _connect(String deviceId) async {
    await disconnect();
    _deviceId = deviceId;
    final completer = Completer<void>();

    // flutter_reactive_ble models the connection as a long-lived
    // stream: cancelling the subscription disconnects, the stream
    // emits ConnectionStateUpdate on every transition. We resolve
    // [_connect]'s future on the first `connected` event (so callers
    // can `await pair()` and have a working stream by the time it
    // returns), and rely on the subscription staying open for the
    // recording session.
    _connectionSub = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        final char = QualifiedCharacteristic(
          serviceId: _heartRateService,
          characteristicId: _heartRateMeasurement,
          deviceId: deviceId,
        );
        _notifySub?.cancel();
        _notifySub = _ble.subscribeToCharacteristic(char).listen((bytes) {
          final bpm = parseBleHeartRateMeasurement(bytes);
          if (bpm != null && bpm >= 30 && bpm <= 230) {
            _controller.add(bpm);
          }
        }, onError: (Object e) {
          debugPrint('BLE notify error: $e');
        });
        if (!completer.isCompleted) completer.complete();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        // Connection lost mid-recording. flutter_reactive_ble does
        // NOT auto-reconnect on its own — `connectToDevice` is a
        // single-attempt stream, so a drop ends the session. Cancel
        // the notify subscription; the caller can call connectCached
        // again to start a fresh attempt.
        _notifySub?.cancel();
        _notifySub = null;
        if (update.failure != null && !completer.isCompleted) {
          completer.completeError(
            StateError('Connection failed: ${update.failure}'),
          );
        }
      }
    }, onError: (Object e) {
      debugPrint('BLE connectToDevice error: $e');
      if (!completer.isCompleted) completer.completeError(e);
    });

    await completer.future;
  }

  /// Drop the current connection. Safe to call when not connected.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    // Cancelling the connection-state subscription is what tells
    // flutter_reactive_ble to actually disconnect — there is no
    // explicit `disconnect()` API.
    await _connectionSub?.cancel();
    _connectionSub = null;
    _deviceId = null;
  }

  /// Forget the paired strap entirely. Disconnects + clears the stored id.
  Future<void> forget() async {
    await disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsDeviceId);
    await prefs.remove(_prefsDeviceName);
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}

/// Discovered candidate during a [BleHeartRate.scan]. Plain value type
/// so the UI sheet doesn't need to depend on flutter_reactive_ble's
/// internal `DiscoveredDevice` shape.
@immutable
class BleDeviceCandidate {
  final String id;
  final String name;
  final int rssi;
  const BleDeviceCandidate({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

/// Parse the BLE Heart Rate Measurement characteristic per the Bluetooth
/// SIG spec (0x2A37): byte 0 is the flags field. Bit 0 of flags is the
/// Heart Rate Value Format:
///   `0` → HR is a `uint8` in byte 1.
///   `1` → HR is a `uint16` little-endian in bytes 1-2.
/// Higher bits describe Sensor Contact, Energy Expended, and RR
/// Intervals — all ignored here (we only care about the current BPM).
///
/// Extracted from [BleHeartRate] as a top-level function so unit tests
/// can exercise it against known-good byte sequences from real straps
/// without a BLE stack.
int? parseBleHeartRateMeasurement(List<int> raw) {
  if (raw.isEmpty) return null;
  final bytes = Uint8List.fromList(raw);
  final flags = bytes[0];
  final is16bit = (flags & 0x01) == 0x01;
  if (is16bit) {
    if (bytes.length < 3) return null;
    return bytes[1] | (bytes[2] << 8);
  }
  if (bytes.length < 2) return null;
  return bytes[1];
}
