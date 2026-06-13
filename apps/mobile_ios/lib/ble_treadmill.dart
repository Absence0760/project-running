import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE treadmill reader over the Bluetooth SIG Fitness Machine Service.
///
/// Uses the standard FTMS service (0x1826) and the Treadmill Data
/// characteristic (0x2ACD). Every conforming treadmill (NordicTrack, Sole,
/// Peloton Tread, Technogym, most commercial-gym belts) exposes these exact
/// UUIDs — `service discovery → subscribe → notify` is identical across
/// vendors, the same way the chest-strap reader in `ble_heart_rate.dart`
/// works off the Heart Rate Service.
///
/// Backed by `flutter_reactive_ble` (BSD-3-Clause), the same backend the HR
/// reader uses.
///
/// This is an **additive, opt-in** distance/speed source for indoor running.
/// It never participates in a normal GPS run — the run recorder only consumes
/// [stream] when treadmill mode is explicitly turned on (`run_recorder`'s
/// `setTreadmillSample` seam), and a treadmill failure can never degrade the
/// GPS L0/L1 distance path.
///
/// The belt's id is persisted in SharedPreferences after the user pairs once,
/// so subsequent sessions auto-reconnect silently.
///
/// `stream` emits a [TreadmillSample] on every notification (usually 1–4Hz)
/// while connected. [statusStream] surfaces the reconnecting / lost state so
/// the pairing UI can disclose a drop. The reconnect contract mirrors the HR
/// reader: a drop after a working connection auto-reconnects with backoff;
/// an initial connect that never succeeds reports [BleTreadmillStatus.connectFailed]
/// and does NOT retry.
enum BleTreadmillStatus { disconnected, connecting, connected, reconnecting, connectFailed }

class BleTreadmill {
  static const String _prefsDeviceId = 'treadmill_device_id';
  static const String _prefsDeviceName = 'treadmill_device_name';

  static const int _maxReconnectAttempts = 20;

  static final Uuid _fitnessMachineService =
      Uuid.parse('00001826-0000-1000-8000-00805f9b34fb');
  static final Uuid _treadmillData =
      Uuid.parse('00002acd-0000-1000-8000-00805f9b34fb');

  // Lazy for the same reason as BleHeartRate: `FlutterReactiveBle()` opens a
  // MethodChannel in its constructor and throws under flutter_test.
  late final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  final StreamController<TreadmillSample> _controller =
      StreamController<TreadmillSample>.broadcast();
  final StreamController<BleTreadmillStatus> _statusController =
      StreamController<BleTreadmillStatus>.broadcast();

  bool _everConnected = false;
  bool _intentional = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  BleTreadmillStatus _status = BleTreadmillStatus.disconnected;

  /// Live stream of treadmill samples. Open-ended — stays subscribed until
  /// [disconnect] is called or the process dies.
  Stream<TreadmillSample> get stream => _controller.stream;

  /// Connection-state stream so the pairing UI can disclose a drop / reconnect
  /// attempt. Emits on every transition.
  Stream<BleTreadmillStatus> get statusStream => _statusController.stream;
  BleTreadmillStatus get status => _status;

  void _setStatus(BleTreadmillStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Scan for FTMS treadmill candidates advertising the Fitness Machine
  /// Service. Emits a de-duplicated list as more devices are discovered.
  /// Stops scanning after [timeout].
  Stream<List<BleTreadmillCandidate>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final controller =
        StreamController<List<BleTreadmillCandidate>>.broadcast();
    final found = <String, BleTreadmillCandidate>{};
    StreamSubscription<DiscoveredDevice>? sub;
    Timer? timer;

    sub = _ble.scanForDevices(
      withServices: [_fitnessMachineService],
      scanMode: ScanMode.lowLatency,
    ).listen((d) {
      found[d.id] = BleTreadmillCandidate(
        id: d.id,
        name: d.name.isNotEmpty ? d.name : d.id,
        rssi: d.rssi,
      );
      if (!controller.isClosed) {
        controller.add(found.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi)));
      }
    }, onError: (Object e) {
      debugPrint('BLE treadmill scanForDevices error: $e');
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
  /// immediately.
  Future<void> pair(BleTreadmillCandidate device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceId, device.id);
    await prefs.setString(_prefsDeviceName, device.name);
    await _connect(device.id);
  }

  /// Last-paired treadmill's display name, or null if never paired.
  Future<String?> pairedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsDeviceName);
  }

  /// Reconnect to the previously paired treadmill (if any). No-op when none
  /// has been paired.
  Future<bool> connectCached() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsDeviceId);
    if (id == null) return false;
    try {
      await _connect(id);
      return true;
    } catch (e) {
      debugPrint('BLE treadmill cached reconnect failed: $e');
      return false;
    }
  }

  Future<bool> reconnect() => connectCached();

  Future<void> _connect(String deviceId) async {
    await disconnect();
    _intentional = false;
    _everConnected = false;
    _reconnectAttempt = 0;
    final completer = Completer<void>();
    _openConnection(deviceId, completer);
    await completer.future;
  }

  void _openConnection(String deviceId, Completer<void>? completer) {
    _setStatus(completer != null
        ? BleTreadmillStatus.connecting
        : BleTreadmillStatus.reconnecting);
    _connectionSub = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _everConnected = true;
        _reconnectAttempt = 0;
        _setStatus(BleTreadmillStatus.connected);
        final char = QualifiedCharacteristic(
          serviceId: _fitnessMachineService,
          characteristicId: _treadmillData,
          deviceId: deviceId,
        );
        _notifySub?.cancel();
        _notifySub = _ble.subscribeToCharacteristic(char).listen((bytes) {
          final sample = parseTreadmillData(bytes);
          if (sample != null) _controller.add(sample);
        }, onError: (Object e) {
          debugPrint('BLE treadmill notify error: $e');
        });
        if (completer != null && !completer.isCompleted) completer.complete();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _notifySub?.cancel();
        _notifySub = null;
        if (_intentional) return;
        if (!_everConnected) {
          _setStatus(BleTreadmillStatus.connectFailed);
          if (completer != null && !completer.isCompleted) {
            completer.completeError(
              StateError('Connection failed: ${update.failure}'),
            );
          }
          return;
        }
        _scheduleReconnect(deviceId);
      }
    }, onError: (Object e) {
      debugPrint('BLE treadmill connectToDevice error: $e');
      if (completer != null && !completer.isCompleted) {
        if (!_everConnected) _setStatus(BleTreadmillStatus.connectFailed);
        completer.completeError(e);
      } else if (!_intentional && _everConnected) {
        _scheduleReconnect(deviceId);
      }
    });
  }

  void _scheduleReconnect(String deviceId) {
    if (_intentional) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _setStatus(BleTreadmillStatus.disconnected);
      return;
    }
    _setStatus(BleTreadmillStatus.reconnecting);
    final delay = bleTreadmillReconnectDelay(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_intentional) return;
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
    await _connectionSub?.cancel();
    _connectionSub = null;
    _setStatus(BleTreadmillStatus.disconnected);
  }

  /// Forget the paired treadmill entirely. Disconnects + clears the stored id.
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

/// Backoff before the Nth (0-based) auto-reconnect attempt: 2, 4, 8, 16, then
/// capped at 30s. Top-level pure function so the schedule is unit-testable
/// without a BLE stack — mirrors `bleReconnectDelay` in `ble_heart_rate.dart`.
Duration bleTreadmillReconnectDelay(int attempt) {
  final clamped = attempt < 0 ? 0 : (attempt > 4 ? 4 : attempt);
  final secs = 2 << clamped;
  return Duration(seconds: secs > 30 ? 30 : secs);
}

/// Discovered candidate during a [BleTreadmill.scan]. Plain value type so the
/// UI sheet doesn't depend on flutter_reactive_ble's `DiscoveredDevice`.
@immutable
class BleTreadmillCandidate {
  final String id;
  final String name;
  final int rssi;
  const BleTreadmillCandidate({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

/// One decoded FTMS Treadmill Data notification.
///
/// [instantaneousSpeedKmh] is always present (the FTMS spec mandates it on
/// every Treadmill Data packet). [totalDistanceMetres] and
/// [inclinationPercent] are present only when the treadmill sets the matching
/// flag bit — null otherwise.
@immutable
class TreadmillSample {
  /// Instantaneous belt speed in km/h.
  final double instantaneousSpeedKmh;

  /// Cumulative distance covered this session, in metres. Null when the belt
  /// doesn't report it (the recorder then integrates speed over time).
  final double? totalDistanceMetres;

  /// Belt inclination as a percentage grade (e.g. `2.5` for 2.5%). Null when
  /// not reported.
  final double? inclinationPercent;

  const TreadmillSample({
    required this.instantaneousSpeedKmh,
    this.totalDistanceMetres,
    this.inclinationPercent,
  });

  /// Speed in metres/second, the unit the run recorder integrates.
  double get speedMps => instantaneousSpeedKmh * 1000 / 3600;
}

/// Parse the FTMS Treadmill Data characteristic per the Bluetooth SIG Fitness
/// Machine Service spec (0x2ACD).
///
/// Layout: bytes 0-1 are a little-endian uint16 Flags field. The remaining
/// fields appear, in spec order, only when their flag bit is set:
///   bit 0  More Data — when CLEAR, Instantaneous Speed (uint16, km/h, 0.01
///          resolution) is present first. (The spec inverts the usual sense:
///          the flag means "more data follows in a second packet", so a
///          single self-contained packet has it clear and carries speed.)
///   bit 1  Average Speed (uint16, 0.01 km/h)
///   bit 2  Total Distance (uint24 LE, metres)
///   bit 3  Inclination (sint16, 0.1%) + Ramp Angle (sint16, 0.1°)
///   bit 4  Elevation Gain (uint16 positive + uint16 negative, 0.1 m)
///   ...    further fields (pace, energy, HR, METs, time) we don't need.
///
/// We decode the three fields the recorder + UI care about — instantaneous
/// speed, total distance, inclination — walking the buffer in flag order and
/// skipping the widths of fields we don't keep so later offsets stay correct.
/// Returns null on a malformed / truncated packet.
///
/// Extracted as a top-level function so unit tests can exercise it against
/// known-good byte sequences without a BLE stack, exactly like
/// `parseBleHeartRateMeasurement`.
TreadmillSample? parseTreadmillData(List<int> raw) {
  if (raw.length < 2) return null;
  final bytes = Uint8List.fromList(raw);
  final flags = bytes[0] | (bytes[1] << 8);
  var offset = 2;

  int? readU16() {
    if (offset + 2 > bytes.length) return null;
    final v = bytes[offset] | (bytes[offset + 1] << 8);
    offset += 2;
    return v;
  }

  int? readS16() {
    final v = readU16();
    if (v == null) return null;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int? readU24() {
    if (offset + 3 > bytes.length) return null;
    final v = bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
    offset += 3;
    return v;
  }

  // bit 0 CLEAR → Instantaneous Speed present. Mandatory for a usable sample.
  final moreData = (flags & 0x0001) != 0;
  if (moreData) return null;
  final rawSpeed = readU16();
  if (rawSpeed == null) return null;
  final speedKmh = rawSpeed / 100.0;

  // bit 1 Average Speed — skip the field width if present.
  if ((flags & 0x0002) != 0) {
    if (readU16() == null) return null;
  }

  double? totalDistance;
  if ((flags & 0x0004) != 0) {
    final d = readU24();
    if (d == null) return null;
    totalDistance = d.toDouble();
  }

  double? inclination;
  if ((flags & 0x0008) != 0) {
    final inc = readS16();
    if (inc == null) return null;
    // Ramp angle follows in the same field group — consume it so any later
    // field we care about keeps its offset, but we don't expose it.
    if (readS16() == null) return null;
    inclination = inc / 10.0;
  }

  return TreadmillSample(
    instantaneousSpeedKmh: speedKmh,
    totalDistanceMetres: totalDistance,
    inclinationPercent: inclination,
  );
}
