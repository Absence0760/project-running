import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'sim_watch_sync.dart';

/// Production [WatchBleTransport] over flutter_reactive_ble.
///
/// Backed by flutter_reactive_ble (BSD-3-Clause) — the same BLE stack the
/// chest-strap HR reader uses (`ble_heart_rate.dart`). We deliberately do
/// NOT pull in flutter_blue_plus: its 2.x license gate is a project-level
/// licensing decision the estate already rejected, and a second BLE
/// central stack in one app would fight over the platform's BLE manager.
///
/// The service + characteristic UUIDs are constants here so they can be
/// re-pinned to whatever the firmware GATT server settles on. Only the
/// service UUID is frozen in the wire spec today; the char UUIDs follow
/// the `d1f6a7e0..` sibling convention.
///
/// This class is untested by design — it only reaches the radio, which no
/// unit test can drive. All decode/verify/reshape/orchestration logic
/// lives behind [WatchBleTransport] in [WatchSyncClient] and IS tested via
/// a fake transport. Keep it that way: no parsing or business logic here.
class ReactiveBleWatchTransport implements WatchBleTransport {
  static final Uuid serviceUuid =
      Uuid.parse('d1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid manifestCharUuid =
      Uuid.parse('d1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid chunkRequestCharUuid =
      Uuid.parse('d1f6a7e2-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid chunkDataCharUuid =
      Uuid.parse('d1f6a7e3-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid settingsCharUuid =
      Uuid.parse('d1f6a7e4-5b2c-4e9a-9c3d-1a2b3c4d5e6f');

  // Lazy: FlutterReactiveBle() opens a MethodChannel in its constructor,
  // which throws under flutter_test. Deferring construction keeps the
  // class importable in a test build even though it's never driven there.
  late final FlutterReactiveBle _ble = FlutterReactiveBle();

  final Duration scanTimeout;
  final Duration connectTimeout;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  String? _deviceId;

  final StreamController<List<int>> _chunks = StreamController.broadcast();
  StreamSubscription<List<int>>? _notifySub;

  ReactiveBleWatchTransport({
    this.scanTimeout = const Duration(seconds: 20),
    this.connectTimeout = const Duration(seconds: 15),
  });

  @override
  Stream<List<int>> get chunkStream => _chunks.stream;

  QualifiedCharacteristic _char(Uuid characteristicId) => QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicId,
        deviceId: _deviceId!,
      );

  @override
  Future<void> scan() async {
    final found = Completer<String>();
    _scanSub = _ble.scanForDevices(withServices: [serviceUuid]).listen(
      (device) {
        if (!found.isCompleted) found.complete(device.id);
      },
      onError: (Object e) {
        if (!found.isCompleted) found.completeError(e);
      },
    );
    final deviceId = await found.future.timeout(scanTimeout);
    await _scanSub?.cancel();
    _scanSub = null;
    _deviceId = deviceId;

    final connected = Completer<void>();
    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: connectTimeout)
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected &&
            !connected.isCompleted) {
          _notifySub =
              _ble.subscribeToCharacteristic(_char(chunkDataCharUuid)).listen(
            _chunks.add,
            onError: (Object e) => debugPrint('watch chunk notify error: $e'),
          );
          connected.complete();
        } else if (update.connectionState ==
                DeviceConnectionState.disconnected &&
            !connected.isCompleted) {
          connected.completeError(
            StateError('watch connect failed: ${update.failure}'),
          );
        }
      },
      onError: (Object e) {
        if (!connected.isCompleted) connected.completeError(e);
      },
    );
    await connected.future.timeout(connectTimeout);
  }

  @override
  Future<List<int>> readManifest() =>
      _ble.readCharacteristic(_char(manifestCharUuid));

  @override
  Future<void> writeChunkRequest(List<int> request) => _ble
      .writeCharacteristicWithResponse(_char(chunkRequestCharUuid), value: request);

  @override
  Future<void> writeSettings(List<int> frame) => _ble
      .writeCharacteristicWithResponse(_char(settingsCharUuid), value: frame);

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    _deviceId = null;
  }
}
