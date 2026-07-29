import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '5345543106ffffbe00d3a40000403800000024f448005043490380e6c54784030000dc0500'
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
    // ice: holder / blood / conditions / contact / phone, each NUL-padded
    '414c4558204d4f5247414e00000000000000000000'
    '4f204e4547000000'
    '50454e4943494c4c494e2c20415354484d41000000'
    '4a414d4945204d4f5247414e000000000000000000'
    '2b3120353535203031333400000000000000000000'
    '2dc5385a';

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
        ice: WatchIceCard(
          holder: 'ALEX MORGAN',
          blood: 'O NEG',
          conditions: 'PENICILLIN, ASTHMA',
          contact: 'JAMIE MORGAN',
          phone: '+1 555 0134',
        ),
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(192));
    });

    test('empty frame is header + crc with zero flags in both bytes', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '06' '00' '00' 'f63d4d51'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(settings.encode(), _hex('53455431' '06' '01' '00' 'be00' 'cbadad99'));
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '06' '02' '00' 'd3a40000' '40380000' '5543c8ad'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '06' '04' '00' '0024f448' '00504349' 'cfc7564f'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '06' '04' '00' '0024f448' '00000000' '8d0cbef7'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(settings.encode(), _hex('53455431' '06' '08' '00' '00' '21a49e88'));
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(settings.encode(), _hex('53455431' '06' '08' '00' '04' '3860f38f'));
    });

    test('seaLevelPa-only frame sets bit4 and carries the f32', () {
      const settings = WatchSettings(seaLevelPa: 101325.0);
      expect(settings.encode(), _hex('53455431' '06' '10' '00' '80e6c547' '045f94ea'));
    });

    test('fuel-only frame sets bit5 and carries drink then eat', () {
      const settings = WatchSettings(fuel: (drinkIntervalS: 900, eatIntervalS: 1500));
      expect(
        settings.encode(),
        _hex('53455431' '06' '20' '00' '84030000' 'dc050000' '58afaae0'),
      );
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(settings.encode(), _hex('53455431' '06' '09' '00' 'be00' '03' '63435477'));
    });

    test('sea-level and fuel keep bit order after the earlier fields', () {
      const settings = WatchSettings(maxHr: 190, seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '06' '11' '00' 'be00' '80e6c547' '564d6aa1'),
      );
    });

    test('pages-only frame sets bit6 and carries the u64 mask', () {
      // 64-bit since v4: the firmware's mask is 64-bit end to end, so a page the
      // phone cannot name is never curated out by silence.
      const settings = WatchSettings(pages: 0x0000c0ff);
      expect(
        settings.encode(),
        _hex('53455431' '06' '40' '00' 'ffc0000000000000' '3267cb57'),
      );
    });

    test('hideEmptyPages sets bit7 and encodes as one byte', () {
      const on = WatchSettings(hideEmptyPages: true);
      expect(on.encode(), _hex('53455431' '06' '80' '00' '01' '8fdebf10'));
      const off = WatchSettings(hideEmptyPages: false);
      expect(off.encode(), _hex('53455431' '06' '80' '00' '00' '19eeb867'));
    });

    test('pages and hideEmpty keep bit order after the earlier fields', () {
      const settings = WatchSettings(
        maxHr: 190,
        pages: -1, // every bit set: the full 64-bit mask
        hideEmptyPages: false,
      );
      expect(
        settings.encode(),
        _hex('53455431' '06' 'c1' '00' 'be00' 'ffffffffffffffff' '00' '4cd90acc'),
      );
    });

    test('tz-only frame matches the firmware golden byte-for-byte', () {
      // -570 (Marquesas, -9:30) pins the two's-complement i16 encoding; the
      // same vector is frozen in the Rust `golden_vector_tz_only` test.
      const settings = WatchSettings(tzOffsetMin: -570);
      expect(settings.encode(), _hex('53455431' '06' '00' '01' 'c6fd' 'c6dd3904'));
    });

    test('a positive tz offset encodes as i16 LE after every flags field', () {
      const settings = WatchSettings(maxHr: 190, tzOffsetMin: 345);
      expect(
        settings.encode(),
        _hex('53455431' '06' '01' '01' 'be00' '5901' 'b9a5aee0'),
      );
    });

    test('a zero tz offset (UTC zone) is still a present field', () {
      const settings = WatchSettings(tzOffsetMin: 0);
      expect(settings.encode(), _hex('53455431' '06' '00' '01' '0000' 'af23955a'));
    });

    test('distanceIntervalM sets flags2 bit1 and 0 disarms the alert', () {
      const armed = WatchSettings(distanceIntervalM: 1000);
      expect(
        armed.encode(),
        _hex('53455431' '06' '00' '02' 'e8030000' '60340c9c'),
      );
      // A present field carrying the zero sentinel, not an omitted one: the
      // phone has to be able to turn the alert off, not only on.
      const off = WatchSettings(distanceIntervalM: 0);
      expect(
        off.encode(),
        _hex('53455431' '06' '00' '02' '00000000' 'eee3818d'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
    });

    test('timeIntervalS sets flags2 bit2 and 0 disarms the alert', () {
      const armed = WatchSettings(timeIntervalS: 1800);
      expect(
        armed.encode(),
        _hex('53455431' '06' '00' '04' '08070000' '24283ac2'),
      );
      const off = WatchSettings(timeIntervalS: 0);
      expect(
        off.encode(),
        _hex('53455431' '06' '00' '04' '00000000' '4e16c102'),
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
        _hex('53455431' '06' '00' '08' '2c01' 'a401' '85c87b91'),
      );
      expect(armed.encode(), hasLength(7 + 4 + 4));
      const off = WatchSettings(paceBand: (fastSPerKm: 0, slowSPerKm: 0));
      expect(
        off.encode(),
        _hex('53455431' '06' '00' '08' '0000' '0000' '4ffb31c7'),
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
        _hex('53455431' '06' '00' '10' 'd3a40000' '38310000' '00' '185ec602'),
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
        _hex('53455431' '06' '00' '10' '00000000' '00000000' '02' '3dc78336'),
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
        _hex('53455431' '06' '00' '20' '656173792d3330' '00000000000000000000000000000000' '00' 'df2b466c'),
      );
      expect(armed.encode(), hasLength(7 + guidedRunIdLen + 4));
      // An empty id deselects — still a present field, all-zero payload.
      const off = WatchSettings(guidedRunId: '');
      expect(
        off.encode(),
        _hex('53455431' '06' '00' '20' '00000000000000000000000000000000' '0000000000000000' '05f450c9'),
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
        _hex('53455431' '06' '00' '3e' 'e8030000' '08070000' '2c01a401' 'd3a4000038310000' '00' '656173792d333000000000000000000000000000000000' '00' '6357ee9d'),
      );
    });

    test('restingHr sets flags2 bit6 and matches the firmware golden', () {
      // Frozen on both sides as the `golden_vector_resting_hr_only` pair — the
      // only vector that exercises the v5 field alone.
      const settings = WatchSettings(restingHr: 48);
      expect(
        settings.encode(),
        _hex('53455431' '06' '00' '40' '3000' 'abf28bf4'),
      );
    });

    test('restingHr lays out after the flags fields and after guidedRunId', () {
      // The TRIMP pair travels as two independent fields: max HR under flags
      // bit0, resting HR under flags2 bit6, laid out in bit order.
      const pair = WatchSettings(maxHr: 190, restingHr: 48);
      expect(
        pair.encode(),
        _hex('53455431' '06' '01' '40' 'be00' '3000' '38340546'),
      );
      const afterGuided = WatchSettings(guidedRunId: 'easy-30', restingHr: 48);
      expect(
        afterGuided.encode(),
        _hex('53455431' '06' '00' '60' '656173792d3330' '00000000000000000000000000000000' '00' '3000' 'cfc32096'),
      );
    });

    test('ice sets flags2 bit7 and matches the firmware golden', () {
      // Frozen on both sides as the `golden_vector_ice_only` pair — the only
      // vector that exercises the v6 field alone, and the one that pins the
      // field-by-field NUL padding a shorter name must produce.
      const settings = WatchSettings(
        ice: WatchIceCard(
          holder: 'ALEX',
          blood: 'O NEG',
          conditions: 'ASTHMA',
          contact: 'JAMIE',
          phone: '555 0134',
        ),
      );
      expect(
        settings.encode(),
        _hex(
          '53455431' '06' '00' '80'
          '414c45580000000000000000000000000000000000'
          '4f204e4547000000'
          '415354484d41000000000000000000000000000000'
          '4a414d494500000000000000000000000000000000'
          '353535203031333400000000000000000000000000'
          '729c3de9',
        ),
      );
    });

    test('an all-blank card is a real field that CLEARS the watch card', () {
      // Distinct from `ice: null`, which leaves whatever the watch holds
      // standing — a runner removing their details has to be able to say so.
      const settings = WatchSettings(ice: WatchIceCard());
      final frame = settings.encode();
      expect(frame, hasLength(7 + iceWireLen + 4));
      expect(frame[6] & 0x80, 0x80, reason: 'the presence bit is still set');
      expect(
        frame.sublist(7, 7 + iceWireLen).every((b) => b == 0),
        isTrue,
        reason: 'an all-blank payload is what the watch reads as a clear',
      );
      expect(const WatchIceCard().isBlank, isTrue);
    });

    test('an over-long or unrenderable ice field throws rather than shipping', () {
      // The watch refuses the whole FRAME on either — so a silent truncation
      // here would cost the runner every other setting in the same push, not
      // just the card. Loud on this side, for that reason.
      expect(
        () => const WatchSettings(ice: WatchIceCard(holder: 'A123456789012345678901'))
            .encode(),
        throwsArgumentError,
      );
      expect(
        () => const WatchSettings(ice: WatchIceCard(blood: 'AB NEGATIVE')).encode(),
        throwsArgumentError,
      );
      expect(
        () => const WatchSettings(ice: WatchIceCard(conditions: 'CAFÉ ALLERGY'))
            .encode(),
        throwsArgumentError,
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
