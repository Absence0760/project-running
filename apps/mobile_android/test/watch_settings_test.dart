import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '5345543104ff3fbe00d3a40000403800000024f448005043490380e6c54784030000dc0500'
    '00'
    'ffc0000000000000'
    '01'
    '5901'
    'e8030000'
    '08070000'
    '2c01a401'
    'd3a4000038310000' '00'
    '656173792d333000000000000000000000000000000000'
    '00'
    '18cd9c55';

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
        distanceIntervalM: 1000,
        timeIntervalS: 1800,
        paceBand: (fastSPerKm: 300, slowSPerKm: 420),
        racePhases: (
          distanceM: 42195,
          goalTimeS: 12600,
          preset: WatchRacePhasePreset.tenTenTen,
        ),
        guidedRunId: 'easy-30',
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(98));
    });

    test('empty frame is header + crc with zero flags in both bytes', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '04' '00' '00' '98e9c952'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(settings.encode(), _hex('53455431' '04' '01' '00' 'be00' 'abfe6de3'));
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '04' '02' '00' 'd3a40000' '40380000' '94faa4f5'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '04' '04' '00' '0024f448' '00504349' '0e7e3a17'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '04' '04' '00' '0024f448' '00000000' '4cb5d2af'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(settings.encode(), _hex('53455431' '04' '08' '00' '00' 'aa6c9722'));
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(settings.encode(), _hex('53455431' '04' '08' '00' '04' 'b3a8fa25'));
    });

    test('seaLevelPa-only frame sets bit4 and carries the f32', () {
      const settings = WatchSettings(seaLevelPa: 101325.0);
      expect(settings.encode(), _hex('53455431' '04' '10' '00' '80e6c547' '2d4e0b7d'));
    });

    test('fuel-only frame sets bit5 and carries drink then eat', () {
      const settings = WatchSettings(fuel: (drinkIntervalS: 900, eatIntervalS: 1500));
      expect(
        settings.encode(),
        _hex('53455431' '04' '20' '00' '84030000' 'dc050000' '9916c6b8'),
      );
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(settings.encode(), _hex('53455431' '04' '09' '00' 'be00' '03' '68e29c3a'));
    });

    test('sea-level and fuel keep bit order after the earlier fields', () {
      const settings = WatchSettings(maxHr: 190, seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '04' '11' '00' 'be00' '80e6c547' 'd0659c8f'),
      );
    });

    test('pages-only frame sets bit6 and carries the u64 mask', () {
      // 64-bit since v4: the firmware's mask is 64-bit end to end, so a page the
      // phone cannot name is never curated out by silence.
      const settings = WatchSettings(pages: 0x0000c0ff);
      expect(
        settings.encode(),
        _hex('53455431' '04' '40' '00' 'ffc0000000000000' 'f3dea70f'),
      );
    });

    test('hideEmptyPages sets bit7 and encodes as one byte', () {
      const on = WatchSettings(hideEmptyPages: true);
      expect(on.encode(), _hex('53455431' '04' '80' '00' '01' '0416b6ba'));
      const off = WatchSettings(hideEmptyPages: false);
      expect(off.encode(), _hex('53455431' '04' '80' '00' '00' '9226b1cd'));
    });

    test('pages and hideEmpty keep bit order after the earlier fields', () {
      const settings = WatchSettings(
        maxHr: 190,
        pages: -1, // every bit set: the full 64-bit mask
        hideEmptyPages: false,
      );
      expect(
        settings.encode(),
        _hex('53455431'
            '04'
            'c1'
            '00'
            'be00'
            'ffffffffffffffff'
            '00'
            'e11d642d'),
      );
    });

    test('tz-only frame matches the firmware golden byte-for-byte', () {
      // -570 (Marquesas, -9:30) pins the two's-complement i16 encoding; the
      // same vector is frozen in the Rust `golden_vector_tz_only` test.
      const settings = WatchSettings(tzOffsetMin: -570);
      expect(settings.encode(), _hex('53455431' '04' '00' '01' 'c6fd' 'a68ef97e'));
    });

    test('a positive tz offset encodes as i16 LE after every flags field', () {
      const settings = WatchSettings(maxHr: 190, tzOffsetMin: 345);
      expect(
        settings.encode(),
        _hex('53455431' '04' '01' '01' 'be00' '5901' '90b43177'),
      );
    });

    test('a zero tz offset (UTC zone) is still a present field', () {
      const settings = WatchSettings(tzOffsetMin: 0);
      expect(settings.encode(), _hex('53455431' '04' '00' '01' '0000' 'cf705520'));
    });

    test('distanceIntervalM sets flags2 bit1 and 0 disarms the alert', () {
      const armed = WatchSettings(distanceIntervalM: 1000);
      expect(
        armed.encode(),
        _hex('53455431' '04' '00' '02' 'e8030000' '4925930b'),
      );
      // A present field carrying the zero sentinel, not an omitted one: the
      // phone has to be able to turn the alert off, not only on.
      const off = WatchSettings(distanceIntervalM: 0);
      expect(
        off.encode(),
        _hex('53455431' '04' '00' '02' '00000000' 'c7f21e1a'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
    });

    test('timeIntervalS sets flags2 bit2 and 0 disarms the alert', () {
      const armed = WatchSettings(timeIntervalS: 1800);
      expect(
        armed.encode(),
        _hex('53455431' '04' '00' '04' '08070000' '0d39a555'),
      );
      const off = WatchSettings(timeIntervalS: 0);
      expect(
        off.encode(),
        _hex('53455431' '04' '00' '04' '00000000' '67075e95'),
      );
    });

    test('paceBand travels whole under flags2 bit3 and an all-zero band disarms',
        () {
      // ONE presence bit for both edges. Two bits would let a partial push arm a
      // new fast edge against whatever stale slow edge the watch still held — an
      // inverted band its setter refuses, so the runner would lose the whole
      // update rather than half of it.
      const armed = WatchSettings(paceBand: (fastSPerKm: 300, slowSPerKm: 420));
      expect(
        armed.encode(),
        _hex('53455431' '04' '00' '08' '2c01' 'a401' 'acd9e406'),
      );
      expect(armed.encode(), hasLength(7 + 4 + 4));
      const off = WatchSettings(paceBand: (fastSPerKm: 0, slowSPerKm: 0));
      expect(
        off.encode(),
        _hex('53455431' '04' '00' '08' '0000' '0000' '66eaae50'),
      );
    });

    test('racePhases sets flags2 bit4 and carries distance, goal, preset index',
        () {
      const armed = WatchSettings(
        racePhases: (
          distanceM: 42195,
          goalTimeS: 12600,
          preset: WatchRacePhasePreset.tenTenTen,
        ),
      );
      expect(
        armed.encode(),
        _hex('53455431' '04' '00' '10' 'd3a40000' '38310000' '00' '87c0fdee'),
      );
      // A null distance IS the clear the watch setter takes; a null goal time
      // builds the phases with no target pace.
      const clear = WatchSettings(
        racePhases: (
          distanceM: null,
          goalTimeS: null,
          preset: WatchRacePhasePreset.even,
        ),
      );
      expect(
        clear.encode(),
        _hex('53455431' '04' '00' '10' '00000000' '00000000' '02' 'a259b8da'),
      );
    });

    test('the preset index is the wire contract, in firmware enum order', () {
      // The watch reads this byte as its `RacePhasePreset` declaration index and
      // pins it to the cross-platform wire name, so reordering this enum
      // re-points every plan already pushed.
      expect(WatchRacePhasePreset.tenTenTen.index, 0);
      expect(WatchRacePhasePreset.negativeSplit.index, 1);
      expect(WatchRacePhasePreset.even.index, 2);
      expect(WatchRacePhasePreset.values, hasLength(3));
    });

    test('guidedRunId sets flags2 bit5 and pads the ascii id with NULs', () {
      const armed = WatchSettings(guidedRunId: 'easy-30');
      expect(
        armed.encode(),
        _hex('53455431'
            '04'
            '00'
            '20'
            '656173792d3330'
            '00000000000000000000000000000000' '00'
            '5d1d5eb1'),
      );
      expect(armed.encode(), hasLength(7 + guidedRunIdLen + 4));
      // An empty id deselects — still a present field, all-zero payload.
      const off = WatchSettings(guidedRunId: '');
      expect(
        off.encode(),
        _hex('53455431'
            '04'
            '00'
            '20'
            '00000000000000000000000000000000'
            '0000000000000000'
            '87c24814'),
      );
    });

    test('an id longer than the wire field throws rather than truncating', () {
      // A truncated id either resolves to nothing on the watch or, worse, to a
      // different run whose id is a prefix of the one the runner picked.
      final tooLong = WatchSettings(guidedRunId: 'x' * (guidedRunIdLen + 1));
      expect(tooLong.encode, throwsArgumentError);
      final exact = WatchSettings(guidedRunId: 'x' * guidedRunIdLen);
      expect(exact.encode(), hasLength(7 + guidedRunIdLen + 4));
    });

    test('the five v4 fields keep flags2 bit order', () {
      // Frozen on both sides as the `golden_vector_v4_arms_only` pair: the only
      // vector that exercises the v4 fields without the rest of the frame.
      const armed = WatchSettings(
        distanceIntervalM: 1000,
        timeIntervalS: 1800,
        paceBand: (fastSPerKm: 300, slowSPerKm: 420),
        racePhases: (
          distanceM: 42195,
          goalTimeS: 12600,
          preset: WatchRacePhasePreset.tenTenTen,
        ),
        guidedRunId: 'easy-30',
      );
      expect(
        armed.encode(),
        _hex('53455431'
            '04'
            '00'
            '3e'
            'e8030000'
            '08070000'
            '2c01a401'
            'd3a4000038310000' '00'
            '656173792d333000000000000000000000000000000000' '00'
            'db8e8de6'),
      );
    });

    test('the trailer is the crc32 of every byte before it', () {
      // The goldens above pin the trailer as literal bytes; this pins that it
      // is actually derived, so a frame the goldens do not cover still carries
      // the checksum the firmware will verify.
      const settings = WatchSettings(
        maxHr: 190,
        seaLevelPa: 101325.0,
        tzOffsetMin: 345,
        distanceIntervalM: 1000,
        paceBand: (fastSPerKm: 300, slowSPerKm: 420),
        guidedRunId: 'first-timer-15',
      );
      final frame = settings.encode();
      final body = frame.sublist(0, frame.length - 4);
      final trailer =
          ByteData.sublistView(frame, frame.length - 4).getUint32(0, Endian.little);
      expect(trailer, crc32(body));
    });
  });
}
