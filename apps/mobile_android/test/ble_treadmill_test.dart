import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_treadmill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseTreadmillData (FTMS 0x2ACD)', () {
    test('speed-only packet, flags=0x0000', () {
      // flags 0x0000 (more-data clear → speed present, no other fields).
      // 10.00 km/h = 1000 = 0x03E8 → bytes 0xE8, 0x03.
      final s = parseTreadmillData([0x00, 0x00, 0xE8, 0x03]);
      expect(s, isNotNull);
      expect(s!.instantaneousSpeedKmh, closeTo(10.0, 1e-9));
      expect(s.totalDistanceMetres, isNull);
      expect(s.inclinationPercent, isNull);
    });

    test('0.01 km/h resolution decodes', () {
      // 12.34 km/h = 1234 = 0x04D2 → bytes 0xD2, 0x04.
      final s = parseTreadmillData([0x00, 0x00, 0xD2, 0x04]);
      expect(s!.instantaneousSpeedKmh, closeTo(12.34, 1e-9));
    });

    test('speedMps converts km/h to m/s', () {
      // 18.00 km/h = 1800 = 0x0708 → 5.0 m/s.
      final s = parseTreadmillData([0x00, 0x00, 0x08, 0x07]);
      expect(s!.speedMps, closeTo(5.0, 1e-9));
    });

    test('total distance present (bit 2)', () {
      // flags 0x0004 (total distance). speed 8.00 km/h = 800 = 0x0320.
      // distance 1500 m = 0x0005DC → uint24 LE bytes 0xDC, 0x05, 0x00.
      final s = parseTreadmillData(
          [0x04, 0x00, 0x20, 0x03, 0xDC, 0x05, 0x00]);
      expect(s, isNotNull);
      expect(s!.instantaneousSpeedKmh, closeTo(8.0, 1e-9));
      expect(s.totalDistanceMetres, 1500.0);
      expect(s.inclinationPercent, isNull);
    });

    test('average speed (bit 1) is skipped so distance offset stays correct', () {
      // flags 0x0006 (avg speed + total distance). speed 9.00 km/h = 900 =
      // 0x0384. avg speed 8.50 km/h = 850 = 0x0352 (consumed, not exposed).
      // distance 2000 m = 0x0007D0 → bytes 0xD0, 0x07, 0x00.
      final s = parseTreadmillData(
          [0x06, 0x00, 0x84, 0x03, 0x52, 0x03, 0xD0, 0x07, 0x00]);
      expect(s, isNotNull);
      expect(s!.instantaneousSpeedKmh, closeTo(9.0, 1e-9));
      expect(s.totalDistanceMetres, 2000.0);
    });

    test('inclination present (bit 3), positive grade', () {
      // flags 0x0008 (inclination). speed 6.00 km/h = 600 = 0x0258.
      // inclination 2.5% = 25 = 0x0019 (sint16). ramp angle 12 = 0x000C
      // (consumed, not exposed).
      final s = parseTreadmillData(
          [0x08, 0x00, 0x58, 0x02, 0x19, 0x00, 0x0C, 0x00]);
      expect(s, isNotNull);
      expect(s!.instantaneousSpeedKmh, closeTo(6.0, 1e-9));
      expect(s.inclinationPercent, closeTo(2.5, 1e-9));
    });

    test('inclination present (bit 3), negative grade (sint16)', () {
      // inclination -1.5% = -15 = 0xFFF1 (sint16). ramp angle -5 = 0xFFFB.
      final s = parseTreadmillData(
          [0x08, 0x00, 0x58, 0x02, 0xF1, 0xFF, 0xFB, 0xFF]);
      expect(s!.inclinationPercent, closeTo(-1.5, 1e-9));
    });

    test('distance + inclination together (bits 2 and 3)', () {
      // flags 0x000C. speed 10.00 = 0x03E8. distance 500 = 0x0001F4 →
      // bytes 0xF4, 0x01, 0x00. inclination 5.0% = 50 = 0x0032, ramp 0.
      final s = parseTreadmillData([
        0x0C, 0x00, 0xE8, 0x03,
        0xF4, 0x01, 0x00,
        0x32, 0x00, 0x00, 0x00,
      ]);
      expect(s, isNotNull);
      expect(s!.totalDistanceMetres, 500.0);
      expect(s.inclinationPercent, closeTo(5.0, 1e-9));
    });

    test('zero speed (treadmill paused / belt stopped)', () {
      final s = parseTreadmillData([0x00, 0x00, 0x00, 0x00]);
      expect(s!.instantaneousSpeedKmh, 0.0);
      expect(s.speedMps, 0.0);
    });

    test('more-data flag set (bit 0) returns null — no usable speed', () {
      // bit 0 set means speed is NOT in this packet; nothing to integrate.
      expect(parseTreadmillData([0x01, 0x00, 0xE8, 0x03]), isNull);
    });

    test('empty payload returns null', () {
      expect(parseTreadmillData([]), isNull);
    });

    test('flags-only payload returns null', () {
      expect(parseTreadmillData([0x00, 0x00]), isNull);
    });

    test('truncated distance payload returns null', () {
      // bit 2 set but only one of the three distance bytes present.
      expect(parseTreadmillData([0x04, 0x00, 0x20, 0x03, 0xDC]), isNull);
    });

    test('truncated inclination payload returns null', () {
      // bit 3 set, speed present, but ramp-angle half of the field missing.
      expect(parseTreadmillData([0x08, 0x00, 0x58, 0x02, 0x19, 0x00, 0x0C]),
          isNull);
    });
  });

  group('bleTreadmillReconnectDelay', () {
    test('exponential backoff 2/4/8/16 then caps at 30s', () {
      expect(bleTreadmillReconnectDelay(0), const Duration(seconds: 2));
      expect(bleTreadmillReconnectDelay(1), const Duration(seconds: 4));
      expect(bleTreadmillReconnectDelay(2), const Duration(seconds: 8));
      expect(bleTreadmillReconnectDelay(3), const Duration(seconds: 16));
      expect(bleTreadmillReconnectDelay(4), const Duration(seconds: 30));
    });

    test('stays capped at 30s for high attempt counts', () {
      expect(bleTreadmillReconnectDelay(10), const Duration(seconds: 30));
      expect(bleTreadmillReconnectDelay(99), const Duration(seconds: 30));
    });

    test('negative attempt clamps to the first delay', () {
      expect(bleTreadmillReconnectDelay(-1), const Duration(seconds: 2));
    });
  });

  group('connection status + pairing', () {
    test('connectFailed is a distinct status from disconnected', () {
      expect(BleTreadmillStatus.connectFailed,
          isNot(BleTreadmillStatus.disconnected));
      expect(BleTreadmillStatus.values,
          contains(BleTreadmillStatus.connectFailed));
    });

    test('reconnect() returns false when no treadmill is paired', () async {
      SharedPreferences.setMockInitialValues({});
      final t = BleTreadmill();
      expect(await t.reconnect(), isFalse);
      await t.dispose();
    });

    test('pairedName() is null before any pairing', () async {
      SharedPreferences.setMockInitialValues({});
      final t = BleTreadmill();
      expect(await t.pairedName(), isNull);
      await t.dispose();
    });
  });
}
