import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '5345543105ff7fbe00d3a40000403800000024f448005043490380e6c54784030000dc0500'
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
    '3000'
    '976f44f0';

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
        restingHr: 48,
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(100));
    });

    test('empty frame is header + crc with zero flags in both bytes', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '05' '00' '00' 'af830b53'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(settings.encode(), _hex('53455431' '05' '01' '00' 'be00' '1bd70dde'));
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '05' '02' '00' 'd3a40000' '40380000' '54252a34'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '05' '04' '00' '0024f448' '00504349' 'cea1b4d6'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '05' '04' '00' '0024f448' '00000000' '8c6a5c6e'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(settings.encode(), _hex('53455431' '05' '08' '00' '00' 'cf0b2b9a'));
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(settings.encode(), _hex('53455431' '05' '08' '00' '04' 'd6cf469d'));
    });

    test('seaLevelPa-only frame sets bit4 and carries the f32', () {
      const settings = WatchSettings(seaLevelPa: 101325.0);
      expect(settings.encode(), _hex('53455431' '05' '10' '00' '80e6c547' '99457cdb'));
    });

    test('fuel-only frame sets bit5 and carries drink then eat', () {
      const settings = WatchSettings(fuel: (drinkIntervalS: 900, eatIntervalS: 1500));
      expect(
        settings.encode(),
        _hex('53455431' '05' '20' '00' '84030000' 'dc050000' '59c94879'),
      );
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(settings.encode(), _hex('53455431' '05' '09' '00' 'be00' '03' 'cd31c0f1'));
    });

    test('sea-level and fuel keep bit order after the earlier fields', () {
      const settings = WatchSettings(maxHr: 190, seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '05' '11' '00' 'be00' '80e6c547' '9371e798'),
      );
    });

    test('pages-only frame sets bit6 and carries the u64 mask', () {
      // 64-bit since v4: the firmware's mask is 64-bit end to end, so a page the
      // phone cannot name is never curated out by silence.
      const settings = WatchSettings(pages: 0x0000c0ff);
      expect(
        settings.encode(),
        _hex('53455431' '05' '40' '00' 'ffc0000000000000' '330129ce'),
      );
    });

    test('hideEmptyPages sets bit7 and encodes as one byte', () {
      const on = WatchSettings(hideEmptyPages: true);
      expect(on.encode(), _hex('53455431' '05' '80' '00' '01' '61710a02'));
      const off = WatchSettings(hideEmptyPages: false);
      expect(off.encode(), _hex('53455431' '05' '80' '00' '00' 'f7410d75'));
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
            '05'
            'c1'
            '00'
            'be00'
            'ffffffffffffffff'
            '00'
            '97fc6bb0'),
      );
    });

    test('tz-only frame matches the firmware golden byte-for-byte', () {
      // -570 (Marquesas, -9:30) pins the two's-complement i16 encoding; the
      // same vector is frozen in the Rust `golden_vector_tz_only` test.
      const settings = WatchSettings(tzOffsetMin: -570);
      expect(settings.encode(), _hex('53455431' '05' '00' '01' 'c6fd' '16a79943'));
    });

    test('a positive tz offset encodes as i16 LE after every flags field', () {
      const settings = WatchSettings(maxHr: 190, tzOffsetMin: 345);
      expect(
        settings.encode(),
        _hex('53455431' '05' '01' '01' 'be00' '5901' '24bf46d1'),
      );
    });

    test('a zero tz offset (UTC zone) is still a present field', () {
      const settings = WatchSettings(tzOffsetMin: 0);
      expect(settings.encode(), _hex('53455431' '05' '00' '01' '0000' '7f59351d'));
    });

    test('distanceIntervalM sets flags2 bit1 and 0 disarms the alert', () {
      const armed = WatchSettings(distanceIntervalM: 1000);
      expect(
        armed.encode(),
        _hex('53455431' '05' '00' '02' 'e8030000' 'fd2ee4ad'),
      );
      // A present field carrying the zero sentinel, not an omitted one: the
      // phone has to be able to turn the alert off, not only on.
      const off = WatchSettings(distanceIntervalM: 0);
      expect(
        off.encode(),
        _hex('53455431' '05' '00' '02' '00000000' '73f969bc'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
    });

    test('timeIntervalS sets flags2 bit2 and 0 disarms the alert', () {
      const armed = WatchSettings(timeIntervalS: 1800);
      expect(
        armed.encode(),
        _hex('53455431' '05' '00' '04' '08070000' 'b932d2f3'),
      );
      const off = WatchSettings(timeIntervalS: 0);
      expect(
        off.encode(),
        _hex('53455431' '05' '00' '04' '00000000' 'd30c2933'),
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
        _hex('53455431' '05' '00' '08' '2c01' 'a401' '18d293a0'),
      );
      expect(armed.encode(), hasLength(7 + 4 + 4));
      const off = WatchSettings(paceBand: (fastSPerKm: 0, slowSPerKm: 0));
      expect(
        off.encode(),
        _hex('53455431' '05' '00' '08' '0000' '0000' 'd2e1d9f6'),
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
        _hex('53455431' '05' '00' '10' 'd3a40000' '38310000' '00' 'e88c5875'),
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
        _hex('53455431' '05' '00' '10' '00000000' '00000000' '02' 'cd151d41'),
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
            '05'
            '00'
            '20'
            '656173792d3330'
            '00000000000000000000000000000000' '00'
            '1c06d2df'),
      );
      expect(armed.encode(), hasLength(7 + guidedRunIdLen + 4));
      // An empty id deselects — still a present field, all-zero payload.
      const off = WatchSettings(guidedRunId: '');
      expect(
        off.encode(),
        _hex('53455431'
            '05'
            '00'
            '20'
            '00000000000000000000000000000000'
            '0000000000000000'
            'c6d9c47a'),
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
            '05'
            '00'
            '3e'
            'e8030000'
            '08070000'
            '2c01a401'
            'd3a4000038310000' '00'
            '656173792d333000000000000000000000000000000000' '00'
            '07623cdb'),
      );
    });

    test('restingHr sets flags2 bit6 and matches the firmware golden', () {
      // Frozen on both sides as the `golden_vector_resting_hr_only` pair — the
      // only vector that exercises the v5 field alone.
      const settings = WatchSettings(restingHr: 48);
      expect(
        settings.encode(),
        _hex('53455431' '05' '00' '40' '3000' '7b882bb3'),
      );
    });

    test('restingHr lays out after the flags fields and after guidedRunId', () {
      // The TRIMP pair travels as two independent fields: max HR under flags
      // bit0, resting HR under flags2 bit6, laid out in bit order.
      const pair = WatchSettings(maxHr: 190, restingHr: 48);
      expect(
        pair.encode(),
        _hex('53455431' '05' '01' '40' 'be00' '3000' 'a52eed77'),
      );
      const afterGuided = WatchSettings(guidedRunId: 'easy-30', restingHr: 48);
      expect(
        afterGuided.encode(),
        _hex('53455431'
            '05'
            '00'
            '60'
            '656173792d3330'
            '00000000000000000000000000000000' '00'
            '3000'
            'a3a82833'),
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
        restingHr: 48,
      );
      final frame = settings.encode();
      final body = frame.sublist(0, frame.length - 4);
      final trailer =
          ByteData.sublistView(frame, frame.length - 4).getUint32(0, Endian.little);
      expect(trailer, crc32(body));
    });
  });
}
