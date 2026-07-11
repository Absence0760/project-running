import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '53455431010fbe00d3a40000403800000024f4480050434903';

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
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(25));
    });

    test('empty frame is header-only with zero flags', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '01' '00'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(settings.encode(), _hex('53455431' '01' '01' 'be00'));
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '01' '02' 'd3a40000' '40380000'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '01' '04' '0024f448' '00504349'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '01' '04' '0024f448' '00000000'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(settings.encode(), _hex('53455431' '01' '08' '00'));
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(settings.encode(), _hex('53455431' '01' '08' '04'));
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(settings.encode(), _hex('53455431' '01' '09' 'be00' '03'));
    });
  });
}
