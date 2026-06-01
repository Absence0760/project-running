import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('parseBleHeartRateMeasurement', () {
    test('8-bit BPM with flags=0x00', () {
      // flags 0x00 (all off) + BPM 72 in byte 1
      expect(parseBleHeartRateMeasurement([0x00, 72]), 72);
    });

    test('8-bit BPM with sensor-contact + EE flags set (non-0x01 bit 0 clear)', () {
      // flags 0b00001110 (contact bits + EE present, but HR format bit clear)
      expect(parseBleHeartRateMeasurement([0x0E, 135]), 135);
    });

    test('16-bit BPM little-endian', () {
      // flags 0x01 (bit 0 set → uint16), value 300 = 0x012C → bytes 0x2C, 0x01
      expect(parseBleHeartRateMeasurement([0x01, 0x2C, 0x01]), 300);
    });

    test('16-bit BPM at low value still decodes correctly', () {
      // 60 bpm in 16-bit mode (some straps always report 16-bit)
      expect(parseBleHeartRateMeasurement([0x01, 60, 0x00]), 60);
    });

    test('empty payload returns null', () {
      expect(parseBleHeartRateMeasurement([]), null);
    });

    test('truncated 8-bit payload returns null', () {
      // flags byte only, no BPM byte
      expect(parseBleHeartRateMeasurement([0x00]), null);
    });

    test('truncated 16-bit payload returns null', () {
      // flags say 16-bit but only one data byte present
      expect(parseBleHeartRateMeasurement([0x01, 0x50]), null);
    });

    test('max 8-bit BPM value', () {
      expect(parseBleHeartRateMeasurement([0x00, 0xFF]), 255);
    });

    test('realistic Polar H10 packet', () {
      // Observed: flags 0x10 (RR intervals present), HR 145, followed by
      // RR data we ignore. HR format bit is clear → 8-bit parse.
      expect(
        parseBleHeartRateMeasurement([0x10, 145, 0xA0, 0x01, 0xB0, 0x01]),
        145,
      );
    });
  });

  group('bleReconnectDelay (persona #13)', () {
    test('exponential backoff 2/4/8/16 then caps at 30s', () {
      expect(bleReconnectDelay(0), const Duration(seconds: 2));
      expect(bleReconnectDelay(1), const Duration(seconds: 4));
      expect(bleReconnectDelay(2), const Duration(seconds: 8));
      expect(bleReconnectDelay(3), const Duration(seconds: 16));
      // 2<<4 = 32 → capped at 30.
      expect(bleReconnectDelay(4), const Duration(seconds: 30));
    });

    test('stays capped at 30s for high attempt counts', () {
      expect(bleReconnectDelay(10), const Duration(seconds: 30));
      expect(bleReconnectDelay(99), const Duration(seconds: 30));
    });

    test('negative attempt clamps to the first delay', () {
      expect(bleReconnectDelay(-1), const Duration(seconds: 2));
    });
  });

  group('initial-connect affordance (persona round-5)', () {
    test('connectFailed is a distinct status from disconnected', () {
      // The run UI keys its manual-reconnect affordance off connectFailed,
      // so it must not collapse into the idle/clean-teardown disconnected
      // value.
      expect(BleHrStatus.connectFailed, isNot(BleHrStatus.disconnected));
      expect(BleHrStatus.values, contains(BleHrStatus.connectFailed));
    });

    test('reconnect() returns false when no strap is paired', () async {
      SharedPreferences.setMockInitialValues({});
      final ble = BleHeartRate();
      // No stored device id → connectCached short-circuits before touching
      // the (unavailable-under-test) BLE channel.
      expect(await ble.reconnect(), isFalse);
      await ble.dispose();
    });
  });
}
