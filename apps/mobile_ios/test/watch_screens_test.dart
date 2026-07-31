import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_screens.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::screens::the_golden_frame_is_stable`, so a wire-format drift on
/// either side is caught here.
///
///   magic "SCR1" | v1 | count 1 | flags 0 | reserved 0
///     | Duo(1) Distance(2) AvgPace(3) empty(0) | crc32 LE
const _goldenHex = '5343523101010000010203007b58f901';

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('encodeWatchScreens', () {
    test('matches the firmware golden frame byte for byte', () {
      final frame = encodeWatchScreens([
        WatchScreen(WatchLayout.duo, [WatchMetric.distance, WatchMetric.avgPace]),
      ]);
      expect(_hex(frame), _goldenHex);
    });

    test('a full set fits one ATT write', () {
      final frame = encodeWatchScreens([
        WatchScreen(WatchLayout.single, [WatchMetric.elapsed]),
        WatchScreen(WatchLayout.duo, [WatchMetric.distance, WatchMetric.avgPace]),
        WatchScreen(WatchLayout.trio, [
          WatchMetric.heartRate,
          WatchMetric.altitude,
          WatchMetric.climbGain,
        ]),
        WatchScreen(WatchLayout.single, [WatchMetric.cutoffMargin]),
      ]);
      expect(frame.length, kMaxScr1Len);
      expect(kMaxScr1Len, 28);
      // The watch's flash config page writes 4-byte words.
      expect(kMaxScr1Len % 4, 0);
    });

    test('an empty set is a legitimate answer, and is how a runner clears', () {
      final frame = encodeWatchScreens([]);
      expect(frame.length, 8 + 4);
      expect(frame[5], 0, reason: 'count');
      // Still CRC-sealed, so the watch can tell "cleared" from "corrupt".
      final stored = ByteData.sublistView(frame).getUint32(8, Endian.little);
      expect(stored, crc32(Uint8List.sublistView(frame, 0, 8)));
    });

    test('the trailer is a standard CRC-32 over everything before it', () {
      final frame = encodeWatchScreens([
        WatchScreen(WatchLayout.trio, [
          WatchMetric.elapsed,
          WatchMetric.heartRate,
          WatchMetric.distance,
        ]),
      ]);
      final body = frame.length - 4;
      final stored = ByteData.sublistView(frame).getUint32(body, Endian.little);
      expect(stored, crc32(Uint8List.sublistView(frame, 0, body)));
    });

    test('slots past the layout arity are the empty byte, not stale metrics', () {
      final frame = encodeWatchScreens([
        WatchScreen(WatchLayout.single, [WatchMetric.distance]),
      ]);
      // layout | slot0 | slot1 | slot2
      expect(frame[8], WatchLayout.single.wire);
      expect(frame[9], WatchMetric.distance.wire);
      expect(frame[10], 0);
      expect(frame[11], 0);
    });

    test('refuses one screen past the cap rather than dropping it', () {
      final one = WatchScreen(WatchLayout.single, [WatchMetric.distance]);
      expect(
        () => encodeWatchScreens(List.filled(kMaxWatchScreens + 1, one)),
        throwsArgumentError,
      );
      expect(
        () => encodeWatchScreens(List.filled(kMaxWatchScreens, one)),
        returnsNormally,
      );
    });

    test('order is meaning — the same metrics swapped is a different frame', () {
      final a = encodeWatchScreens([
        WatchScreen(WatchLayout.duo, [WatchMetric.distance, WatchMetric.avgPace]),
      ]);
      final b = encodeWatchScreens([
        WatchScreen(WatchLayout.duo, [WatchMetric.avgPace, WatchMetric.distance]),
      ]);
      expect(_hex(a), isNot(_hex(b)));
    });
  });

  group('the wire contract with the firmware', () {
    test('a screen refuses a metric count its layout cannot draw', () {
      expect(
        () => WatchScreen(WatchLayout.single, [
          WatchMetric.distance,
          WatchMetric.avgPace,
        ]),
        throwsArgumentError,
      );
      expect(
        () => WatchScreen(WatchLayout.trio, [WatchMetric.distance]),
        throwsArgumentError,
      );
      expect(() => WatchScreen(WatchLayout.duo, []), throwsArgumentError);
    });

    /// The guard that makes a reorder of either enum a red test instead of a
    /// silent re-point of every screen already pushed to a watch.
    test('metric bytes are unique, stable, and cover 1..=37', () {
      final seen = <int>{};
      for (final m in WatchMetric.values) {
        expect(m.wire, greaterThanOrEqualTo(1));
        expect(m.wire, lessThanOrEqualTo(37));
        expect(seen.add(m.wire), isTrue, reason: 'byte ${m.wire} claimed twice');
        expect(m.wireName, isNotEmpty);
      }
      expect(WatchMetric.values.length, 37,
          reason: 'the catalogue and its byte map have drifted from the watch');
      // Pinned by name, so a reorder cannot quietly renumber them.
      expect(WatchMetric.elapsed.wire, 1);
      expect(WatchMetric.distance.wire, 2);
      expect(WatchMetric.heartRate.wire, 5);
      expect(WatchMetric.raceDayDays.wire, 34);
      expect(WatchMetric.raceDayDays.wireName, 'race_day_days');
      // The three 2026-07-30 metrics landed on three branches that each
      // believed 35 was free; the bytes below are the arbitration.
      expect(WatchMetric.sleepBudget.wire, 35);
      expect(WatchMetric.sleepBudget.wireName, 'sleep_budget');
      expect(WatchMetric.timerRemaining.wire, 36);
      expect(WatchMetric.timerRemaining.wireName, 'timer_remaining');
      expect(WatchMetric.backyardBell.wire, 37);
      expect(WatchMetric.backyardBell.wireName, 'backyard_bell');
    });

    test('layout bytes round-trip and reserve the Quad seat', () {
      expect(WatchLayout.single.wire, 0);
      expect(WatchLayout.duo.wire, 1);
      expect(WatchLayout.trio.wire, 2);
      expect(WatchLayout.values.map((l) => l.wire), isNot(contains(3)),
          reason: '3 is the reserved Quad seat and must not be emitted');
      expect(WatchLayout.single.slots, 1);
      expect(WatchLayout.duo.slots, 2);
      expect(WatchLayout.trio.slots, 3);
      expect(WatchLayout.values.map((l) => l.slots).reduce((a, b) => a > b ? a : b),
          kWatchScreenSlots);
    });
  });
}
