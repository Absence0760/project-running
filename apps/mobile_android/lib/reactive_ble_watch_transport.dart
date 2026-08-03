import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'sim_watch_sync.dart';
import 'watch_status_link.dart';

/// Production [WatchBleTransport] over flutter_reactive_ble.
///
/// Backed by flutter_reactive_ble (BSD-3-Clause) — the same BLE stack the
/// chest-strap HR reader uses (`ble_heart_rate.dart`). We deliberately do
/// NOT pull in flutter_blue_plus: its 2.x license gate is a project-level
/// licensing decision the estate already rejected, and a second BLE
/// central stack in one app would fight over the platform's BLE manager.
///
/// The service + characteristic UUIDs mirror the firmware's GATT table in
/// `apps/custom_watch/app/src/tasks/ble.rs`, which is the source of truth:
/// `..e1` frame (read+notify), `..e2` run_manifest (read+notify), `..e3`
/// run_chunk (write+notify), `..e4` settings, `..e5` course, `..e6`
/// workout, `..e7` screens, `..e8` roadbook. A chunk request and its reply share ONE
/// characteristic (`..e3`): the phone writes the request there and the
/// watch notifies the slice back on the same handle (decisions §211d), so
/// [chunkCharUuid] serves both directions. `..e1` is claimed by
/// [ReactiveBleWatchFrameSource] below, which holds its own connection.
///
/// This class is untested by design — it only reaches the radio, which no
/// unit test can drive. All decode/verify/reshape/orchestration logic
/// lives behind [WatchBleTransport] in [WatchSyncClient] and IS tested via
/// a fake transport. Keep it that way: no parsing or business logic here.
/// The UUID constants are the one exception, pinned by
/// `test/reactive_ble_watch_transport_test.dart` — a mismatch against the
/// firmware table is invisible without hardware.
class ReactiveBleWatchTransport implements WatchBleTransport {
  static final Uuid serviceUuid =
      Uuid.parse('d1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid manifestCharUuid =
      Uuid.parse('d1f6a7e2-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid chunkCharUuid =
      Uuid.parse('d1f6a7e3-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid settingsCharUuid =
      Uuid.parse('d1f6a7e4-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid courseCharUuid =
      Uuid.parse('d1f6a7e5-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid workoutCharUuid =
      Uuid.parse('d1f6a7e6-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid screensCharUuid =
      Uuid.parse('d1f6a7e7-5b2c-4e9a-9c3d-1a2b3c4d5e6f');
  static final Uuid roadbookCharUuid =
      Uuid.parse('d1f6a7e8-5b2c-4e9a-9c3d-1a2b3c4d5e6f');

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
              _ble.subscribeToCharacteristic(_char(chunkCharUuid)).listen(
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
      .writeCharacteristicWithResponse(_char(chunkCharUuid), value: request);

  @override
  Future<void> writeSettings(List<int> frame) => _ble
      .writeCharacteristicWithResponse(_char(settingsCharUuid), value: frame);

  @override
  Future<void> writeWorkout(List<int> chunk) => _ble
      .writeCharacteristicWithResponse(_char(workoutCharUuid), value: chunk);

  @override
  Future<void> writeCourse(List<int> chunk) => _ble
      .writeCharacteristicWithResponse(_char(courseCharUuid), value: chunk);

  @override
  Future<void> writeScreens(List<int> frame) => _ble
      .writeCharacteristicWithResponse(_char(screensCharUuid), value: frame);

  @override
  Future<void> writeRoadbook(List<int> chunk) => _ble
      .writeCharacteristicWithResponse(_char(roadbookCharUuid), value: chunk);

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

/// Production [WatchFrameSource]: a persistent subscription to the watch's
/// live-status characteristic (`..e1`, read+notify), which the firmware
/// notifies one `link::status_frame` per second on once a phone subscribes.
///
/// A SEPARATE connection from [ReactiveBleWatchTransport], which is the whole
/// reason this is its own class. Run sync is a per-operation dance — scan,
/// connect, pull, disconnect — while the status feed has to stay up for a
/// whole run, so a `frameStream` hung off the transport would die every time a
/// sync finished.
///
/// UNVERIFIED on hardware, and this is the part to check first: two
/// simultaneous `connectToDevice` streams against the SAME watch is not
/// something flutter_reactive_ble promises anywhere, and the BLE path cannot
/// run in the Renode sim (no SoftDevice). Until a bench says otherwise, a
/// caller driving both surfaces stops the status link ([WatchStatusLink.stop])
/// before a run sync and arms a fresh one afterwards.
///
/// Untested by design, like [ReactiveBleWatchTransport] — it only reaches the
/// radio. Decode, backoff, give-up and teardown live in [WatchStatusLink]
/// behind [WatchFrameSource] and are tested there. [frameCharUuid] is the
/// exception, pinned against the firmware table by
/// `scripts/check_watch_ble_uuids.mjs`.
class ReactiveBleWatchFrameSource implements WatchFrameSource {
  static final Uuid frameCharUuid =
      Uuid.parse('d1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f');

  ReactiveBleWatchFrameSource({
    this.scanTimeout = const Duration(seconds: 20),
    this.connectTimeout = const Duration(seconds: 15),
  });

  late final FlutterReactiveBle _ble = FlutterReactiveBle();

  final Duration scanTimeout;
  final Duration connectTimeout;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamController<List<int>>? _frames;

  @override
  Future<Stream<List<int>>> open() async {
    try {
      return await _open();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<Stream<List<int>>> _open() async {
    final found = Completer<String>();
    _scanSub = _ble.scanForDevices(
      withServices: [ReactiveBleWatchTransport.serviceUuid],
    ).listen(
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

    final char = QualifiedCharacteristic(
      serviceId: ReactiveBleWatchTransport.serviceUuid,
      characteristicId: frameCharUuid,
      deviceId: deviceId,
    );
    // Frames are republished through a controller rather than handing the
    // characteristic stream straight out, so a disconnect CLOSES the stream.
    // A notify subscription that merely stops emitting reads the same as a
    // stationary runner, which is the one thing the link must not conclude.
    final frames = StreamController<List<int>>();
    _frames = frames;

    final connected = Completer<void>();
    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: connectTimeout)
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          _notifySub ??= _ble.subscribeToCharacteristic(char).listen(
            (bytes) {
              // A notification can land between the disconnect event closing
              // the controller and the platform cancelling the subscription.
              if (!frames.isClosed) frames.add(bytes);
            },
            onError: (Object e) {
              debugPrint('watch frame notify error: $e');
              if (!frames.isClosed) frames.close();
            },
          );
          if (!connected.isCompleted) connected.complete();
        } else if (update.connectionState ==
            DeviceConnectionState.disconnected) {
          if (!connected.isCompleted) {
            connected.completeError(
              StateError('watch frame connect failed: ${update.failure}'),
            );
          } else if (!frames.isClosed) {
            frames.close();
          }
        }
      },
      onError: (Object e) {
        if (!connected.isCompleted) {
          connected.completeError(e);
        } else if (!frames.isClosed) {
          frames.close();
        }
      },
    );
    await connected.future.timeout(connectTimeout);
    return frames.stream;
  }

  @override
  Future<void> close() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    final frames = _frames;
    _frames = null;
    if (frames != null && !frames.isClosed) await frames.close();
  }
}
