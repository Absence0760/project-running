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
/// we stop forwarding bytes and **auto-reconnect** with backoff until
/// it's restored or [disconnect] is called — distance/pace keep going.
/// [statusStream] surfaces the reconnecting / lost state so the run UI
/// can disclose the drop instead of silently flat-lining HR. Persona
/// android #13.
/// `connectFailed` is distinct from `disconnected`: it means the initial
/// connect never reached `connected` (strap off / out of range at launch),
/// which auto-reconnect deliberately does NOT retry. The run UI uses it to
/// offer a one-tap "reconnect" affordance, where a plain `disconnected`
/// (no strap paired, or a clean teardown) shows nothing.
enum BleHrStatus { disconnected, connecting, connected, reconnecting, connectFailed }

class BleHeartRate {
  static const String _prefsDeviceId = 'ble_hr_device_id';
  static const String _prefsDeviceName = 'ble_hr_device_name';

  /// Give up auto-reconnecting after this many consecutive failed
  /// attempts (~9 min at the capped backoff) so a strap that's been
  /// taken off doesn't drain the battery retrying forever.
  static const int _maxReconnectAttempts = 20;

  static final Uuid _heartRateService =
      Uuid.parse('0000180d-0000-1000-8000-00805f9b34fb');
  static final Uuid _heartRateMeasurement =
      Uuid.parse('00002a37-0000-1000-8000-00805f9b34fb');

  // Lazy: `FlutterReactiveBle()` opens a MethodChannel in its
  // constructor and throws under flutter_test (no platform impl).
  // Keeping the field `late` defers that to the first scan / connect
  // call, which production hits and the widget-test surface (which
  // only builds BleHeartRate, never calls into it) does not.
  late final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  final StreamController<int> _controller = StreamController<int>.broadcast();
  final StreamController<BleHrStatus> _statusController =
      StreamController<BleHrStatus>.broadcast();

  /// True once the active session has reached `connected` at least once.
  /// Gates auto-reconnect — an initial connect that never succeeds (strap
  /// off at app start) reports failure to the caller and does NOT retry;
  /// only a drop after a working connection triggers the reconnect loop.
  bool _everConnected = false;
  /// Set by the public [disconnect] / [forget] / [dispose] so the drop
  /// handler can tell a deliberate teardown from a strap going out of range.
  bool _intentional = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  BleHrStatus _status = BleHrStatus.disconnected;

  /// Live stream of BPM readings. Open-ended — stays subscribed until
  /// [stop] is called or the process dies.
  Stream<int> get stream => _controller.stream;

  /// Connection-state stream so the run UI can disclose a mid-run drop /
  /// reconnect attempt. Emits on every transition. Persona android #13.
  Stream<BleHrStatus> get statusStream => _statusController.stream;
  BleHrStatus get status => _status;

  void _setStatus(BleHrStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

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

  /// Manual reconnect for the strap-off-at-launch case. The run UI calls
  /// this from the "reconnect" affordance it shows on [BleHrStatus.connectFailed].
  /// Thin wrapper over [connectCached] so the run screen doesn't need the
  /// stored device id. Returns false when no strap is paired or the connect
  /// still fails.
  Future<bool> reconnect() => connectCached();

  Future<void> _connect(String deviceId) async {
    await disconnect();
    // disconnect() latched _intentional; clear it now that we're opening
    // a fresh session that SHOULD auto-reconnect on a drop.
    _intentional = false;
    _everConnected = false;
    _reconnectAttempt = 0;
    final completer = Completer<void>();
    _openConnection(deviceId, completer);
    await completer.future;
  }

  /// Open (or re-open) the long-lived connection stream. `completer` is
  /// non-null only for the initial [_connect] so callers can `await` a
  /// working stream; reconnect attempts pass null. flutter_reactive_ble
  /// models the connection as a stream: cancelling the subscription
  /// disconnects, and `connectToDevice` is single-attempt — a drop ends
  /// the stream, so we re-open it ourselves to reconnect.
  void _openConnection(String deviceId, Completer<void>? completer) {
    _setStatus(completer != null ? BleHrStatus.connecting : BleHrStatus.reconnecting);
    _connectionSub = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _everConnected = true;
        _reconnectAttempt = 0;
        _setStatus(BleHrStatus.connected);
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
        if (completer != null && !completer.isCompleted) completer.complete();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _notifySub?.cancel();
        _notifySub = null;
        if (_intentional) return;
        if (!_everConnected) {
          // Initial connect never succeeded (strap off at app start).
          // Report failure to the caller and don't burn battery retrying
          // a strap the user may not even have on. `connectFailed` (not
          // `disconnected`) lets the run UI offer a manual reconnect.
          _setStatus(BleHrStatus.connectFailed);
          if (completer != null && !completer.isCompleted) {
            completer.completeError(
              StateError('Connection failed: ${update.failure}'),
            );
          }
          return;
        }
        // A working connection dropped mid-session — reconnect.
        _scheduleReconnect(deviceId);
      }
    }, onError: (Object e) {
      debugPrint('BLE connectToDevice error: $e');
      if (completer != null && !completer.isCompleted) {
        // Initial connect errored out — surface a reconnectable state so the
        // run UI can offer a retry rather than silently flat-lining HR.
        if (!_everConnected) _setStatus(BleHrStatus.connectFailed);
        completer.completeError(e);
      } else if (!_intentional && _everConnected) {
        _scheduleReconnect(deviceId);
      }
    });
  }

  void _scheduleReconnect(String deviceId) {
    if (_intentional) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      // Give up — strap has been gone too long. The run keeps recording
      // without HR; the user can re-pair from Settings.
      _setStatus(BleHrStatus.disconnected);
      return;
    }
    _setStatus(BleHrStatus.reconnecting);
    final delay = bleReconnectDelay(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_intentional) return;
      // Tear down the stale connection stream before re-opening.
      _connectionSub?.cancel();
      _connectionSub = null;
      _openConnection(deviceId, null);
    });
  }

  /// Drop the current connection and stop any in-flight reconnect loop.
  /// Safe to call when not connected.
  Future<void> disconnect() async {
    _intentional = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    // Cancelling the connection-state subscription is what tells
    // flutter_reactive_ble to actually disconnect — there is no
    // explicit `disconnect()` API.
    await _connectionSub?.cancel();
    _connectionSub = null;
    _setStatus(BleHrStatus.disconnected);
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
    await _statusController.close();
  }
}

/// Backoff before the Nth (0-based) auto-reconnect attempt: 2, 4, 8, 16,
/// then capped at 30 s. Extracted as a top-level pure function so the
/// schedule can be unit-tested without a BLE stack. Persona android #13.
Duration bleReconnectDelay(int attempt) {
  final clamped = attempt < 0 ? 0 : (attempt > 4 ? 4 : attempt);
  final secs = 2 << clamped; // 2,4,8,16,32
  return Duration(seconds: secs > 30 ? 30 : secs);
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
