import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '5345543102ff01be00d3a40000403800000024f448005043490380e6c54784030000dc0500'
    '00ffc00000'
    '01'
    '5901';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('WatchSettings.encode', () {
    test('fully-populated frame matches the golden vector byte-for-byte', () {
      const settings = WatchSettings(
        maxHr: 190,
        pacer: (distanceM: 42195, timeS: 14400),
        gear: (baselineM: 500000.0, targetM: 800000.0),
        zoneCeiling: 3,
        seaLevelPa: 101325.0,
        fuel: (drinkIntervalS: 900, eatIntervalS: 1500),
        pages: 0x0000c0ff,
        hideEmptyPages: true,
        tzOffsetMin: 345,
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(45));
    });

    test('empty frame is header-only with zero flags in both bytes', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '02' '00' '00'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(settings.encode(), _hex('53455431' '02' '01' '00' 'be00'));
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '02' '02' '00' 'd3a40000' '40380000'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '02' '04' '00' '0024f448' '00504349'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '02' '04' '00' '0024f448' '00000000'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(settings.encode(), _hex('53455431' '02' '08' '00' '00'));
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(settings.encode(), _hex('53455431' '02' '08' '00' '04'));
    });

    test('seaLevelPa-only frame sets bit4 and carries the f32', () {
      const settings = WatchSettings(seaLevelPa: 101325.0);
      expect(settings.encode(), _hex('53455431' '02' '10' '00' '80e6c547'));
    });

    test('fuel-only frame sets bit5 and carries drink then eat', () {
      const settings = WatchSettings(fuel: (drinkIntervalS: 900, eatIntervalS: 1500));
      expect(
        settings.encode(),
        _hex('53455431' '02' '20' '00' '84030000' 'dc050000'),
      );
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(settings.encode(), _hex('53455431' '02' '09' '00' 'be00' '03'));
    });

    test('sea-level and fuel keep bit order after the earlier fields', () {
      const settings = WatchSettings(maxHr: 190, seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '02' '11' '00' 'be00' '80e6c547'),
      );
    });

    test('pages-only frame sets bit6 and carries the u32 mask', () {
      const settings = WatchSettings(pages: 0x0000c0ff);
      expect(settings.encode(), _hex('53455431' '02' '40' '00' 'ffc00000'));
    });

    test('hideEmptyPages sets bit7 and encodes as one byte', () {
      const on = WatchSettings(hideEmptyPages: true);
      expect(on.encode(), _hex('53455431' '02' '80' '00' '01'));
      const off = WatchSettings(hideEmptyPages: false);
      expect(off.encode(), _hex('53455431' '02' '80' '00' '00'));
    });

    test('pages and hideEmpty keep bit order after the earlier fields', () {
      const settings = WatchSettings(
        maxHr: 190,
        pages: 0xffffffff,
        hideEmptyPages: false,
      );
      expect(
        settings.encode(),
        _hex('53455431' '02' 'c1' '00' 'be00' 'ffffffff' '00'),
      );
    });

    test('tz-only frame matches the firmware golden byte-for-byte', () {
      // -570 (Marquesas, -9:30) pins the two's-complement i16 encoding; the
      // same vector is frozen in the Rust `golden_vector_tz_only` test.
      const settings = WatchSettings(tzOffsetMin: -570);
      expect(settings.encode(), _hex('53455431' '02' '00' '01' 'c6fd'));
    });

    test('a positive tz offset encodes as i16 LE after every flags field', () {
      const settings = WatchSettings(maxHr: 190, tzOffsetMin: 345);
      expect(
        settings.encode(),
        _hex('53455431' '02' '01' '01' 'be00' '5901'),
      );
    });

    test('a zero tz offset (UTC zone) is still a present field', () {
      const settings = WatchSettings(tzOffsetMin: 0);
      expect(settings.encode(), _hex('53455431' '02' '00' '01' '0000'));
    });
  });
}
