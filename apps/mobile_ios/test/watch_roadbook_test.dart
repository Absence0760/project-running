import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_roadbook.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::roadbook_store::golden_frame_is_stable` (the canned sim
/// schedule: start, an aid at 90 m, the 180 m finish, plus the two sim cut-offs,
/// sealed with the v1 CRC32 trailer), so a wire-format drift on either side is
/// caught here rather than on a wrist mid-race.
const _goldenHex =
    '52424b3101030200'
    '0000000000000000000000000001'
    '5a0000005a0000001e0000000101'
    'b40000005a0000003c0000000200'
    '5a00000078000000'
    'aa000000f0000000'
    '79e5afab';

const _crcLen = 4;

const _simCheckpoints = [
  WatchRoadbookCheckpoint(
    cumDistanceM: 0,
    legDistanceM: 0,
    projectedElapsedSec: 0,
    isRefill: true,
  ),
  WatchRoadbookCheckpoint(
    cumDistanceM: 90,
    legDistanceM: 90,
    projectedElapsedSec: 30,
    cutoff: WatchCutoffStatus.safe,
    isRefill: true,
  ),
  WatchRoadbookCheckpoint(
    cumDistanceM: 180,
    legDistanceM: 90,
    projectedElapsedSec: 60,
    cutoff: WatchCutoffStatus.tight,
  ),
];

const _simCutoffs = [
  WatchCutoffLeg(cumDistanceM: 90, limitElapsedSec: 120),
  WatchCutoffLeg(cumDistanceM: 170, limitElapsedSec: 240),
];

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

int _u32(Uint8List frame, int at) =>
    ByteData.sublistView(frame).getUint32(at, Endian.little);

void main() {
  group('encodeRoadbook', () {
    test('the sim schedule matches the golden vector byte-for-byte', () {
      expect(
        encodeRoadbook(_simCheckpoints, _simCutoffs),
        equals(_hex(_goldenHex)),
        reason:
            'wire format changed — update BOTH this vector and the Rust mirror '
            'in apps/custom_watch/core/src/roadbook_store.rs',
      );
    });

    test('the trailer is the derived crc32 of everything before it', () {
      final frame = encodeRoadbook(_simCheckpoints, _simCutoffs);
      final body = frame.sublist(0, frame.length - _crcLen);
      expect(_u32(frame, body.length), equals(crc32(body)));
    });

    test('the header names the frame and both counts', () {
      final frame = encodeRoadbook(_simCheckpoints, _simCutoffs);
      expect(frame.sublist(0, 4), equals(_hex('52424b31')));
      expect(frame[4], equals(1), reason: 'v1 is the only version');
      expect(frame[5], equals(3));
      expect(frame[6], equals(2));
      expect(frame[7], equals(0), reason: 'no frame-level flag bits yet');
    });

    test('an empty schedule encodes as the clear', () {
      final frame = encodeRoadbook(const [], const []);
      expect(frame.length, equals(8 + 4));
      expect(frame[5], equals(0));
      expect(frame[6], equals(0));
      expect(
        _u32(frame, 8),
        equals(crc32(frame.sublist(0, 8))),
        reason: 'even the empty frame is sealed',
      );
    });

    test('either series alone is a legal frame', () {
      final onlyCheckpoints = encodeRoadbook(_simCheckpoints, const []);
      expect(onlyCheckpoints[5], equals(3));
      expect(onlyCheckpoints[6], equals(0));
      expect(onlyCheckpoints.length, equals(8 + 3 * 14 + 4));

      final onlyCutoffs = encodeRoadbook(const [], _simCutoffs);
      expect(onlyCutoffs[5], equals(0));
      expect(onlyCutoffs[6], equals(2));
      expect(onlyCutoffs.length, equals(8 + 2 * 8 + 4));
    });

    test('a refill checkpoint sets the flag bit and a dry one clears it', () {
      final frame = encodeRoadbook(_simCheckpoints, const []);
      expect(frame[8 + 13], equals(kCheckpointFlagRefill));
      expect(frame[8 + 14 + 13], equals(kCheckpointFlagRefill));
      expect(frame[8 + 28 + 13], equals(0));
    });

    test('the cut-off status byte is the declaration order plus one', () {
      // Declaration order is the wire contract, so pin it: 0 means the
      // checkpoint carries no cut-off, and a reorder here would silently turn
      // every safe checkpoint on the watch into a missed one.
      expect(WatchCutoffStatus.values, equals(const [
        WatchCutoffStatus.safe,
        WatchCutoffStatus.tight,
        WatchCutoffStatus.miss,
      ]));
      for (final entry in {
        null: 0,
        WatchCutoffStatus.safe: 1,
        WatchCutoffStatus.tight: 2,
        WatchCutoffStatus.miss: 3,
      }.entries) {
        final frame = encodeRoadbook([
          WatchRoadbookCheckpoint(
            cumDistanceM: 100,
            legDistanceM: 100,
            projectedElapsedSec: 60,
            cutoff: entry.key,
          ),
        ], const []);
        expect(frame[8 + 12], equals(entry.value), reason: '${entry.key}');
      }
    });

    test('distances round to whole metres the way the firmware does', () {
      final frame = encodeRoadbook([
        const WatchRoadbookCheckpoint(
          cumDistanceM: 1234.5,
          legDistanceM: 999.4,
          projectedElapsedSec: 600,
        ),
      ], const []);
      expect(_u32(frame, 8), equals(1235), reason: 'half away from zero');
      expect(_u32(frame, 12), equals(999));
    });

    test('both series encode at their caps', () {
      final frame = encodeRoadbook([
        for (var i = 0; i < kMaxRoadbookCheckpoints; i++)
          WatchRoadbookCheckpoint(
            cumDistanceM: (i + 1) * 5000,
            legDistanceM: 5000,
            projectedElapsedSec: (i + 1) * 1800,
            cutoff: WatchCutoffStatus.miss,
            isRefill: i.isEven,
          ),
      ], [
        for (var i = 0; i < kMaxRoadbookCutoffs; i++)
          WatchCutoffLeg(
            cumDistanceM: (i + 1) * 5000,
            limitElapsedSec: (i + 1) * 2000,
          ),
      ]);
      expect(
        frame.length,
        equals(8 + 16 * 14 + 16 * 8 + 4),
        reason: 'the 364-byte worst case the chunking exists for',
      );
    });

    test('an over-cap series is refused, never trimmed', () {
      expect(
        () => encodeRoadbook([
          for (var i = 0; i <= kMaxRoadbookCheckpoints; i++)
            WatchRoadbookCheckpoint(
              cumDistanceM: i * 100,
              legDistanceM: 100,
              projectedElapsedSec: i * 60,
            ),
        ], const []),
        throwsArgumentError,
      );
      expect(
        () => encodeRoadbook(const [], [
          for (var i = 0; i <= kMaxRoadbookCutoffs; i++)
            WatchCutoffLeg(cumDistanceM: i * 100, limitElapsedSec: i * 60),
        ]),
        throwsArgumentError,
      );
    });

    test('a distance the wire cannot carry is refused', () {
      for (final bad in [double.nan, double.infinity, -1.0, 5e9]) {
        expect(
          () => encodeRoadbook([
            WatchRoadbookCheckpoint(
              cumDistanceM: bad,
              legDistanceM: 0,
              projectedElapsedSec: 0,
            ),
          ], const []),
          throwsArgumentError,
          reason: 'checkpoint distance $bad',
        );
        expect(
          () => encodeRoadbook(const [], [
            WatchCutoffLeg(cumDistanceM: bad, limitElapsedSec: 0),
          ]),
          throwsArgumentError,
          reason: 'cut-off distance $bad',
        );
      }
    });

    test('a negative elapsed time is refused', () {
      expect(
        () => encodeRoadbook([
          const WatchRoadbookCheckpoint(
            cumDistanceM: 0,
            legDistanceM: 0,
            projectedElapsedSec: -1,
          ),
        ], const []),
        throwsArgumentError,
      );
      expect(
        () => encodeRoadbook(const [], [
          const WatchCutoffLeg(cumDistanceM: 0, limitElapsedSec: -1),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('chunkRoadbook', () {
    test('the sim frame fits one chunk, offset zero', () {
      final frame = encodeRoadbook(_simCheckpoints, _simCutoffs);
      final chunks = chunkRoadbook(frame);
      expect(chunks.length, equals(1));
      expect(chunks.first[0], equals(0));
      expect(chunks.first[1], equals(0));
      expect(chunks.first.sublist(2), equals(frame));
    });

    test('the worst-case frame needs two chunks and reassembles exactly', () {
      final frame = encodeRoadbook([
        for (var i = 0; i < kMaxRoadbookCheckpoints; i++)
          WatchRoadbookCheckpoint(
            cumDistanceM: (i + 1) * 1000,
            legDistanceM: 1000,
            projectedElapsedSec: (i + 1) * 300,
          ),
      ], [
        for (var i = 0; i < kMaxRoadbookCutoffs; i++)
          WatchCutoffLeg(
            cumDistanceM: (i + 1) * 1000,
            limitElapsedSec: (i + 1) * 400,
          ),
      ]);
      final chunks = chunkRoadbook(frame);
      expect(chunks.length, equals(2));
      final rebuilt = <int>[];
      var expectedOffset = 0;
      for (final chunk in chunks) {
        expect(
          ByteData.sublistView(chunk).getUint16(0, Endian.little),
          equals(expectedOffset),
          reason: 'chunks are written in order',
        );
        expect(chunk.length, lessThanOrEqualTo(244));
        rebuilt.addAll(chunk.sublist(2));
        expectedOffset = rebuilt.length;
      }
      expect(Uint8List.fromList(rebuilt), equals(frame));
    });

    test('a smaller payload cap splits into more ordered chunks', () {
      final frame = encodeRoadbook(_simCheckpoints, _simCutoffs);
      final chunks = chunkRoadbook(frame, payloadMax: 16);
      expect(chunks.length, equals((frame.length / 16).ceil()));
      final rebuilt = <int>[];
      for (final chunk in chunks) {
        rebuilt.addAll(chunk.sublist(2));
      }
      expect(Uint8List.fromList(rebuilt), equals(frame));
    });
  });
}
