import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE chest-strap heart-rate reader.
///
/// Uses the standard BLE Heart Rate Service (0x180D) and the Heart Rate
/// Measurement characteristic (0x2A37). Every conforming strap on the
/// market (Polar H9/H10, Garmin HRM-Pro/Dual, Wahoo Tickr, Coospo, etc.)
/// exposes these exact UUIDs — `service discovery → subscribe → notify`
/// is identical across vendors.
///
/// The strap's MAC address is persisted in SharedPreferences after the
/// user pairs once, so subsequent runs auto-reconnect silently.
///
/// `stream()` emits on every notification (usually 1Hz) while connected.
/// Callers collect into a running list for `avg_bpm` computation and
/// render `current` in the live run UI. If the connection drops mid-run
/// we emit nothing until it's restored — distance/pace keep going.
class BleHeartRate {
  static const String _prefsDeviceId = 'ble_hr_device_id';
  static const String _prefsDeviceName = 'ble_hr_device_name';

  static final Guid _heartRateService = Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final Guid _heartRateMeasurement = Guid('00002a37-0000-1000-8000-00805f9b34fb');

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _sub;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  /// Live stream of BPM readings. Open-ended — stays subscribed until
  /// [stop] is called or the process dies.
  Stream<int> get stream => _controller.stream;

  /// Scan for BLE strap candidates advertising the Heart Rate Service.
  /// Emits a de-duplicated list as more devices are discovered. Stops
  /// scanning after [timeout]. Caller typically shows a bottom sheet
  /// with the list and lets the user tap the one they want.
  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    final controller = StreamController<List<ScanResult>>.broadcast();
    final found = <DeviceIdentifier, ScanResult>{};
    late StreamSubscription<List<ScanResult>> sub;

    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(_heartRateService) ||
            r.device.platformName.isNotEmpty) {
          found[r.device.remoteId] = r;
        }
      }
      controller.add(found.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)));
    });

    FlutterBluePlus.startScan(
      withServices: [_heartRateService],
      timeout: timeout,
    ).then((_) async {
      await sub.cancel();
      await controller.close();
    }).catchError((Object e) async {
      debugPrint('BLE scan failed: $e');
      await sub.cancel();
      await controller.close();
    });
    return controller.stream;
  }

  /// Pair with [device] — stores its id for auto-reconnect + connects
  /// immediately. Subsequent app launches will call [connectCached]
  /// without user interaction.
  Future<void> pair(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceId, device.remoteId.str);
    await prefs.setString(_prefsDeviceName, device.platformName);
    await _connect(device);
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
    final device = BluetoothDevice.fromId(id);
    try {
      await _connect(device);
      return true;
    } catch (e) {
      debugPrint('BLE cached reconnect failed: $e');
      return false;
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
    final services = await device.discoverServices();
    final hrService = services.firstWhere(
      (s) => s.serviceUuid == _heartRateService,
      orElse: () => throw StateError('Heart Rate Service not found on ${device.platformName}'),
    );
    final hrChar = hrService.characteristics.firstWhere(
      (c) => c.characteristicUuid == _heartRateMeasurement,
      orElse: () => throw StateError('HR Measurement characteristic not found'),
    );
    await hrChar.setNotifyValue(true);
    _sub = hrChar.lastValueStream.listen((bytes) {
      final bpm = _parseHeartRate(bytes);
      if (bpm != null && bpm >= 30 && bpm <= 230) {
        _controller.add(bpm);
      }
    });
  }

  /// Parse the BLE Heart Rate Measurement characteristic per the spec:
  /// byte 0 is flags; if bit 0 is clear the HR is uint8 in byte 1,
  /// otherwise uint16 LE in bytes 1–2. Higher bits describe EE, RR, and
  /// sensor-contact status — we ignore them for avg-BPM purposes.
  int? _parseHeartRate(List<int> raw) {
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

  /// Drop the current connection. Safe to call when not connected.
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _device?.disconnect();
    } catch (_) {
      // best-effort
    }
    _device = null;
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
