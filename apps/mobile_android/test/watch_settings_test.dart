import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_settings.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::settings` test vector so a wire-format drift on either side
/// is caught here.
const _goldenHex =
    '5345543108ffff03be00d3a40000403800000024f448005043490380e6c54784030000dc0500'
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
    '02'
    '2800'
    '1c26d5df';

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
        autoLap: WatchAutoLap.mi1,
        stormAlertHpa: 4.0,
      );
      final frame = settings.encode();
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(196));
    });

    test('empty frame is header + crc with zero flags in all three bytes', () {
      const settings = WatchSettings();
      expect(settings.encode(), _hex('53455431' '08' '00' '00' '00' 'aa825266'));
    });

    test('maxHr-only frame sets bit0 and carries the u16', () {
      const settings = WatchSettings(maxHr: 190);
      expect(
        settings.encode(),
        _hex('53455431' '08' '01' '00' '00' 'be00' '4468a151'),
      );
    });

    test('pacer-only frame sets bit1 and carries distance then time', () {
      const settings = WatchSettings(pacer: (distanceM: 42195, timeS: 14400));
      expect(
        settings.encode(),
        _hex('53455431' '08' '02' '00' '00' 'd3a40000' '40380000' 'b12764c4'),
      );
    });

    test('gear-only frame sets bit2 and carries baseline then target', () {
      const settings = WatchSettings(
        gear: (baselineM: 500000.0, targetM: 800000.0),
      );
      expect(
        settings.encode(),
        _hex('53455431' '08' '04' '00' '00' '0024f448' '00504349' '2f1951c3'),
      );
    });

    test('a null gear target encodes as 0.0 (no target / untracked)', () {
      const settings = WatchSettings(gear: (baselineM: 500000.0, targetM: null));
      expect(
        settings.encode(),
        _hex('53455431' '08' '04' '00' '00' '0024f448' '00000000' '6dd2b97b'),
      );
    });

    test('zoneCeiling 0 clears the ceiling and still sets bit3', () {
      const settings = WatchSettings(zoneCeiling: 0);
      expect(
        settings.encode(),
        _hex('53455431' '08' '08' '00' '00' '00' '16dfd321'),
      );
    });

    test('zoneCeiling 4 encodes the top ceiling zone', () {
      const settings = WatchSettings(zoneCeiling: 4);
      expect(
        settings.encode(),
        _hex('53455431' '08' '08' '00' '00' '04' '0f1bbe26'),
      );
    });

    test('seaLevelPa-only frame sets bit4 and carries the f32', () {
      const settings = WatchSettings(seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '08' '10' '00' '00' '80e6c547' 'f763a2b4'),
      );
    });

    test('fuel-only frame sets bit5 and carries drink then eat', () {
      const settings = WatchSettings(fuel: (drinkIntervalS: 900, eatIntervalS: 1500));
      expect(
        settings.encode(),
        _hex('53455431' '08' '20' '00' '00' '84030000' 'dc050000' '472e5e1c'),
      );
    });

    test('present fields are laid out in bit order regardless of set subset',
        () {
      const settings = WatchSettings(maxHr: 190, zoneCeiling: 3);
      expect(
        settings.encode(),
        _hex('53455431' '08' '09' '00' '00' 'be00' '03' 'bb18b8d6'),
      );
    });

    test('sea-level and fuel keep bit order after the earlier fields', () {
      const settings = WatchSettings(maxHr: 190, seaLevelPa: 101325.0);
      expect(
        settings.encode(),
        _hex('53455431' '08' '11' '00' '00' 'be00' '80e6c547' '44c9456a'),
      );
    });

    test('pages-only frame sets bit6 and carries the u64 mask', () {
      // 64-bit since v4: the firmware's mask is 64-bit end to end, so a page the
      // phone cannot name is never curated out by silence.
      const settings = WatchSettings(pages: 0x0000c0ff);
      expect(
        settings.encode(),
        _hex('53455431' '08' '40' '00' '00' 'ffc0000000000000' '65740c2a'),
      );
    });

    test('hideEmptyPages sets bit7 and encodes as one byte', () {
      const on = WatchSettings(hideEmptyPages: true);
      expect(on.encode(), _hex('53455431' '08' '80' '00' '00' '01' '5471397e'));
      const off = WatchSettings(hideEmptyPages: false);
      expect(off.encode(), _hex('53455431' '08' '80' '00' '00' '00' 'c2413e09'));
    });

    test('pages and hideEmpty keep bit order after the earlier fields', () {
      const settings = WatchSettings(
        maxHr: 190,
        pages: -1, // every bit set: the full 64-bit mask
        hideEmptyPages: false,
      );
      expect(
        settings.encode(),
        _hex('53455431' '08' 'c1' '00' '00' 'be00' 'ffffffffffffffff' '00'
            '830596a2'),
      );
    });

    test('tz-only frame matches the firmware golden byte-for-byte', () {
      // -570 (Marquesas, -9:30) pins the two's-complement i16 encoding; the
      // same vector is frozen in the Rust `golden_vector_tz_only` test.
      const settings = WatchSettings(tzOffsetMin: -570);
      expect(
        settings.encode(),
        _hex('53455431' '08' '00' '01' '00' 'c6fd' 'ce5b97f0'),
      );
    });

    test('a positive tz offset encodes as i16 LE after every flags field', () {
      const settings = WatchSettings(maxHr: 190, tzOffsetMin: 345);
      expect(
        settings.encode(),
        _hex('53455431' '08' '01' '01' '00' 'be00' '5901' '1b258741'),
      );
    });

    test('a zero tz offset (UTC zone) is still a present field', () {
      const settings = WatchSettings(tzOffsetMin: 0);
      expect(
        settings.encode(),
        _hex('53455431' '08' '00' '01' '00' '0000' 'a7a53bae'),
      );
    });

    test('distanceIntervalM sets flags2 bit1 and 0 disarms the alert', () {
      const armed = WatchSettings(distanceIntervalM: 1000);
      expect(
        armed.encode(),
        _hex('53455431' '08' '00' '02' '00' 'e8030000' 'ad643a91'),
      );
      // A present field carrying the zero sentinel, not an omitted one: the
      // phone has to be able to turn the alert off, not only on.
      const off = WatchSettings(distanceIntervalM: 0);
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '02' '00' '00000000' '23b3b780'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
    });

    test('timeIntervalS sets flags2 bit2 and 0 disarms the alert', () {
      const armed = WatchSettings(timeIntervalS: 1800);
      expect(
        armed.encode(),
        _hex('53455431' '08' '00' '04' '00' '08070000' '546e1596'),
      );
      const off = WatchSettings(timeIntervalS: 0);
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '04' '00' '00000000' '3e50ee56'),
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
        _hex('53455431' '08' '00' '08' '00' '2c01' 'a401' '8fa36677'),
      );
      expect(armed.encode(), hasLength(8 + 4 + 4));
      const off = WatchSettings(paceBand: (fastSPerKm: 0, slowSPerKm: 0));
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '08' '00' '0000' '0000' '45902c21'),
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
        _hex('53455431' '08' '00' '10' '00' 'd3a40000' '38310000' '00'
            '60b6c798'),
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
        _hex('53455431' '08' '00' '10' '00' '00000000' '00000000' '02'
            '452f82ac'),
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
        _hex('53455431' '08' '00' '20' '00' '656173792d3330' '00000000000000000000000000000000' '00' '8a72a40f'),
      );
      expect(armed.encode(), hasLength(8 + guidedRunIdLen + 4));
      // An empty id deselects — still a present field, all-zero payload.
      const off = WatchSettings(guidedRunId: '');
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '20' '00' '00000000000000000000000000000000' '0000000000000000' '50adb2aa'),
      );
    });

    test('an id longer than the wire field throws rather than truncating', () {
      // A truncated id either resolves to nothing on the watch or, worse, to a
      // different run whose id is a prefix of the one the runner picked.
      final tooLong = WatchSettings(guidedRunId: 'x' * (guidedRunIdLen + 1));
      expect(tooLong.encode, throwsArgumentError);
      final exact = WatchSettings(guidedRunId: 'x' * guidedRunIdLen);
      expect(exact.encode(), hasLength(8 + guidedRunIdLen + 4));
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
        _hex('53455431' '08' '00' '3e' '00' 'e8030000' '08070000' '2c01a401' 'd3a4000038310000' '00' '656173792d333000000000000000000000000000000000' '00' '96d47178'),
      );
    });

    test('restingHr sets flags2 bit6 and matches the firmware golden', () {
      // Frozen on both sides as the `golden_vector_resting_hr_only` pair — the
      // only vector that exercises the v5 field alone.
      const settings = WatchSettings(restingHr: 48);
      expect(
        settings.encode(),
        _hex('53455431' '08' '00' '40' '00' '3000' '0cacd552'),
      );
    });

    test('restingHr lays out after the flags fields and after guidedRunId', () {
      // The TRIMP pair travels as two independent fields: max HR under flags
      // bit0, resting HR under flags2 bit6, laid out in bit order.
      const pair = WatchSettings(maxHr: 190, restingHr: 48);
      expect(
        pair.encode(),
        _hex('53455431' '08' '01' '40' '00' 'be00' '3000' 'aa1cbb46'),
      );
      const afterGuided = WatchSettings(guidedRunId: 'easy-30', restingHr: 48);
      expect(
        afterGuided.encode(),
        _hex('53455431' '08' '00' '60' '00' '656173792d3330' '00000000000000000000000000000000' '00' '3000' '390c878c'),
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
          '53455431' '08' '00' '80' '00'
          '414c45580000000000000000000000000000000000'
          '4f204e4547000000'
          '415354484d41000000000000000000000000000000'
          '4a414d494500000000000000000000000000000000'
          '353535203031333400000000000000000000000000'
          '831e0d7c',
        ),
      );
    });

    test('an all-blank card is a real field that CLEARS the watch card', () {
      // Distinct from `ice: null`, which leaves whatever the watch holds
      // standing — a runner removing their details has to be able to say so.
      const settings = WatchSettings(ice: WatchIceCard());
      final frame = settings.encode();
      expect(frame, hasLength(8 + iceWireLen + 4));
      expect(frame[6] & 0x80, 0x80, reason: 'the presence bit is still set');
      expect(
        frame.sublist(8, 8 + iceWireLen).every((b) => b == 0),
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

    test('autoLap sets flags3 bit0 and carries the rung as one byte', () {
      const km1 = WatchSettings(autoLap: WatchAutoLap.km1);
      expect(
        km1.encode(),
        _hex('53455431' '08' '00' '00' '01' '01' '2ef67b8a'),
      );
      // OFF is a real trigger the runner chose, not an absent field: it spends
      // the 64-record lap store on hand-marked splits only.
      const off = WatchSettings(autoLap: WatchAutoLap.off);
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '00' '01' '00' 'b8c67cfd'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
      const min30 = WatchSettings(autoLap: WatchAutoLap.min30);
      expect(
        min30.encode(),
        _hex('53455431' '08' '00' '00' '01' '07' '1b531863'),
      );
    });

    test('the auto-lap rung index is the wire contract, in firmware order', () {
      // The watch reads this byte as its `AutoLap` declaration index, so
      // reordering this enum re-points every trigger already pushed — and the
      // same discriminant is packed into three bits of the CFG1 flash record.
      expect(WatchAutoLap.off.index, 0);
      expect(WatchAutoLap.km1.index, 1);
      expect(WatchAutoLap.mi1.index, 2);
      expect(WatchAutoLap.km5.index, 3);
      expect(WatchAutoLap.mi5.index, 4);
      expect(WatchAutoLap.min5.index, 5);
      expect(WatchAutoLap.min10.index, 6);
      expect(WatchAutoLap.min30.index, 7);
      expect(WatchAutoLap.values, hasLength(8));
      for (final rung in WatchAutoLap.values) {
        expect(rung.index, lessThanOrEqualTo(7),
            reason: 'CFG1 carries the rung in three bits');
      }
    });

    test('stormAlertHpa sets flags3 bit1, travels as tenths, and 0 disarms', () {
      const armed = WatchSettings(stormAlertHpa: 4.0);
      expect(
        armed.encode(),
        _hex('53455431' '08' '00' '00' '02' '2800' '06b85e48'),
      );
      const fractional = WatchSettings(stormAlertHpa: 2.5);
      expect(
        fractional.encode(),
        _hex('53455431' '08' '00' '00' '02' '1900' 'b4bf038e'),
      );
      // Disarming is a real update, not an absence — the same distinction the
      // zone ceiling has carried since v1.
      const off = WatchSettings(stormAlertHpa: 0.0);
      expect(
        off.encode(),
        _hex('53455431' '08' '00' '00' '02' '0000' 'ac160315'),
      );
      expect(off.encode(), isNot(const WatchSettings().encode()));
    });

    test('an armed threshold never rounds into the disarm sentinel', () {
      // The watch's own trend window would reject 0.02 hPa, but a wire that
      // silently turned "arm" into "off" would be a different bug in a
      // different place, with nothing left to reject it.
      const tiny = WatchSettings(stormAlertHpa: 0.02);
      expect(
        tiny.encode(),
        _hex('53455431' '08' '00' '00' '02' '0100' 'ed27180c'),
      );
    });

    test('the flags3 fields lay out last, in bit order after the ice card', () {
      const both = WatchSettings(
        autoLap: WatchAutoLap.mi1,
        stormAlertHpa: 4.0,
      );
      expect(
        both.encode(),
        _hex('53455431' '08' '00' '00' '03' '02' '2800' 'f91e12eb'),
      );
      const afterIce = WatchSettings(
        ice: WatchIceCard(
          holder: 'ALEX',
          blood: 'O NEG',
          conditions: 'ASTHMA',
          contact: 'JAMIE',
          phone: '555 0134',
        ),
        autoLap: WatchAutoLap.mi1,
      );
      expect(
        afterIce.encode(),
        _hex(
          '53455431' '08' '00' '80' '01'
          '414c45580000000000000000000000000000000000'
          '4f204e4547000000'
          '415354484d41000000000000000000000000000000'
          '4a414d494500000000000000000000000000000000'
          '353535203031333400000000000000000000000000'
          '02'
          'ff37fb2c',
        ),
      );
    });

    test('every frame stamps v8, so a v8 field can never ride a v7 header', () {
      // The watch refuses a frame whose version does not know its own presence
      // bits — an unknown bit is how it tells a corrupt push from a
      // forward-compatible one. The phone cannot produce that frame because
      // the version byte is a constant, not derived from which fields are set.
      for (final s in const [
        WatchSettings(),
        WatchSettings(maxHr: 190),
        WatchSettings(autoLap: WatchAutoLap.km1),
        WatchSettings(stormAlertHpa: 4.0),
      ]) {
        expect(s.encode()[4], 0x08);
      }
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
        autoLap: WatchAutoLap.km5,
        stormAlertHpa: 6.0,
      );
      final frame = settings.encode();
      final body = frame.sublist(0, frame.length - 4);
      final trailer =
          ByteData.sublistView(frame, frame.length - 4).getUint32(0, Endian.little);
      expect(trailer, crc32(body));
    });
  });
}
