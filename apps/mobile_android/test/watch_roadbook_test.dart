import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/roadbook.dart';
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

  group('watchRoadbookFromRoadbook', () {
    /// A straight west-to-east line at a fixed latitude, `count` legs of
    /// roughly `legM` metres, flat so the effort model degrades to even pace and
    /// the projected arrivals are exactly proportional to distance.
    List<RoadbookWaypoint> line(int count, double legM) {
      // ~85.4 m per 0.001° of longitude at 40°N; close enough — the tests
      // assert on relative structure, not on absolute metres.
      final step = legM / (111320 * 0.766);
      return [
        for (var i = 0; i <= count; i++)
          RoadbookWaypoint(lat: 40, lng: -105 + i * step),
      ];
    }

    RoadbookMarker aid(double posM, {String kind = 'aid_station'}) =>
        RoadbookMarker(
          positionM: posM,
          kind: kind,
          label: 'stop $posM',
          meta: const {'services': ['water']},
        );

    RoadbookMarker cutoff(double posM, int limitS) => RoadbookMarker(
          positionM: posM,
          kind: 'cutoff',
          label: 'barrier $posM',
          meta: {'cutoff_elapsed_s': limitS},
        );

    Roadbook build(List<RoadbookMarker> markers,
            {int count = 40, double legM = 1000, double goal = 36000}) =>
        buildRoadbook(
          line(count, legM),
          markers,
          goalSeconds: goal,
          model: PacingModel.effort,
        );

    test('the synthetic start is dropped and the finish always survives', () {
      final rb = build([aid(10000), aid(20000)]);
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.refusal, isNull);
      expect(out.checkpoints, hasLength(3));
      expect(out.checkpoints!.first.cumDistanceM, greaterThan(0),
          reason: 'the 0 m / 0 s start row carries nothing the watch lacks');
      expect(out.checkpoints!.last.cumDistanceM,
          closeTo(rb.totalDistM.roundToDouble(), 1));
      expect(out.reduced, isFalse);
    });

    test('a route with no distance is refused, not pushed empty', () {
      final out = watchRoadbookFromRoadbook(build(const [], count: 0));
      expect(out.refusal, WatchRoadbookRefusal.noSchedule);
      expect(out.checkpoints, isNull);
      expect(out.cutoffs, isNull);
    });

    test('an over-cap route is reduced to exactly the cap, keeping the end',
        () {
      // 30 aid stations plus the finish — comfortably past the 16 cap.
      final rb = build([for (var i = 1; i <= 30; i++) aid(i * 1000)]);
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.refusal, isNull);
      expect(out.checkpoints, hasLength(kMaxRoadbookCheckpoints));
      expect(out.reduced, isTrue);
      expect(out.sourceCheckpointCount, 31);
      expect(out.checkpoints!.last.cumDistanceM,
          closeTo(rb.totalDistM.roundToDouble(), 1),
          reason: 'a schedule that ends mid-race is the worst answer');
      // The frame must still encode — the cap is what the firmware refuses past.
      expect(encodeRoadbook(out.checkpoints!, out.cutoffs!).length,
          lessThanOrEqualTo(364));
    });

    test('every cut-off survives a reduction, even a late-clumped one', () {
      // 24 aid stations spread out, plus 5 cut-offs bunched in the last 4 km —
      // even index-sampling would drop most of them.
      final rb = build([
        for (var i = 1; i <= 24; i++) aid(i * 1000),
        for (var i = 0; i < 5; i++) cutoff(26000 + i * 1000, 30000 + i * 1000),
      ]);
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.checkpoints, hasLength(kMaxRoadbookCheckpoints));
      expect(out.cutoffs, hasLength(5));
      final withCutoff =
          out.checkpoints!.where((c) => c.cutoff != null).toList();
      expect(withCutoff, hasLength(5),
          reason: 'a dropped cut-off makes the CutoffEta page confidently '
              'wrong about which limit is next');
      for (final leg in out.cutoffs!) {
        expect(
          out.checkpoints!.any((c) => c.cumDistanceM == leg.cumDistanceM),
          isTrue,
        );
      }
    });

    test('a sparse mid-course stop outranks one of a dense clump', () {
      // 40 stops crammed into the first 2 km, then 4 lonely ones spread across
      // the remaining 38 km of a 40 km course. Even index-sampling over the
      // distance-ordered list would spend almost the whole budget inside the
      // clump and leave most of the race unscheduled; farthest-point sampling
      // must take the lonely ones first, because they are the rows that break
      // up the longest stretches with nothing on them.
      final sparse = [10000.0, 18000.0, 26000.0, 34000.0];
      final rb = build([
        for (var i = 1; i <= 40; i++) aid(i * 50),
        for (final p in sparse) aid(p),
      ]);
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.checkpoints, hasLength(kMaxRoadbookCheckpoints));
      final at = out.checkpoints!.map((c) => c.cumDistanceM).toSet();
      for (final p in sparse) {
        expect(at, contains(p),
            reason: 'the $p m stop is the only thing scheduled for kilometres '
                'either side of it');
      }
      // And the clump still gets the leftover budget, spread through it.
      expect(out.checkpoints!.where((c) => c.cumDistanceM <= 2000).length,
          kMaxRoadbookCheckpoints - sparse.length - 1);

      // The anti-clump property, stated directly: no scheduled row is further
      // than one sparse spacing from its predecessor.
      var prev = 0.0;
      var widest = 0.0;
      for (final c in out.checkpoints!) {
        widest = math.max(widest, c.cumDistanceM - prev);
        prev = c.cumDistanceM;
      }
      expect(widest, lessThanOrEqualTo(8000));
    });

    test('more cut-offs than the wire carries is refused, never trimmed', () {
      final rb = build([
        for (var i = 1; i <= kMaxRoadbookCutoffs + 1; i++)
          cutoff(i * 1000, 3000 + i * 1000),
      ]);
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.refusal, WatchRoadbookRefusal.tooManyCutoffs);
      expect(out.checkpoints, isNull);
      expect(out.sourceCutoffCount, kMaxRoadbookCutoffs + 1);
    });

    test('a full 16 cut-offs plus a separate finish is refused too', () {
      // 16 cut-offs fit the cut-off series, but with the finish they need 17
      // checkpoint slots — and neither a cut-off nor the end may be dropped.
      final rb = build([
        for (var i = 1; i <= kMaxRoadbookCutoffs; i++)
          cutoff(i * 1000, 3000 + i * 1000),
      ]);
      final out = watchRoadbookFromRoadbook(rb);
      expect(out.refusal, WatchRoadbookRefusal.tooManyCutoffs);
    });

    test('two markers sharing a position collapse, the cut-off winning', () {
      // An aid station that IS the barrier — normal on a mountain ultra, and a
      // non-monotonic schedule the firmware's pacer would reject whole.
      final rb = build([aid(10000), cutoff(10000, 12000), aid(20000)]);
      final out = watchRoadbookFromRoadbook(rb);

      final at10k =
          out.checkpoints!.where((c) => c.cumDistanceM == 10000).toList();
      expect(at10k, hasLength(1), reason: 'one wire row per position');
      expect(at10k.single.cutoff, isNotNull);
      expect(out.cutoffs, hasLength(1));
    });

    test('the emitted series is strictly increasing in distance and time', () {
      final rb = build([
        for (var i = 1; i <= 30; i++) aid(i * 1000),
        // Two stops a metre apart: same wire second, so one must go.
        aid(15001),
        cutoff(25000, 28000),
      ]);
      final out = watchRoadbookFromRoadbook(rb);

      var prevDist = -1.0;
      var prevElapsed = -1;
      for (final c in out.checkpoints!) {
        expect(c.cumDistanceM, greaterThan(prevDist));
        expect(c.projectedElapsedSec, greaterThan(prevElapsed));
        prevDist = c.cumDistanceM;
        prevElapsed = c.projectedElapsedSec;
      }
    });

    test('leg distances are recomputed against the surviving predecessor', () {
      final rb = build([for (var i = 1; i <= 30; i++) aid(i * 1000)]);
      final out = watchRoadbookFromRoadbook(rb);

      var cum = 0.0;
      for (final c in out.checkpoints!) {
        expect(c.legDistanceM, closeTo(c.cumDistanceM - cum, 0.001),
            reason: 'a reduced schedule whose legs sum short would misreport '
                'every remaining leg on the watch');
        cum = c.cumDistanceM;
      }
      expect(cum, closeTo(out.checkpoints!.last.cumDistanceM, 0.001));
    });

    test('a clock-only cut-off with no start time is counted, not swallowed',
        () {
      final rb = buildRoadbook(
        line(20, 1000),
        [
          RoadbookMarker(
            positionM: 10000,
            kind: 'cutoff',
            label: 'barrier',
            meta: const {'cutoff_clock': '14:00'},
          ),
        ],
        goalSeconds: 36000,
        model: PacingModel.effort,
      );
      final out = watchRoadbookFromRoadbook(rb);

      expect(out.unresolvedCutoffCount, 1);
      expect(out.cutoffs, isEmpty,
          reason: 'no start time means no limit to project against');
      expect(out.refusal, isNull,
          reason: 'the course schedule is still worth pushing');
    });

    test('an aid station is flagged a refill point, a plain note is not', () {
      final rb = build([
        aid(10000),
        RoadbookMarker(
            positionM: 20000, kind: 'note', label: 'gate', meta: const {}),
      ]);
      final out = watchRoadbookFromRoadbook(rb);

      final at10k =
          out.checkpoints!.firstWhere((c) => c.cumDistanceM == 10000);
      final at20k =
          out.checkpoints!.firstWhere((c) => c.cumDistanceM == 20000);
      expect(at10k.isRefill, isTrue);
      expect(at20k.isRefill, isFalse);
    });

    test('a reduced schedule still chunks into at most two writes', () {
      final rb = build([
        for (var i = 1; i <= 24; i++) aid(i * 1000),
        for (var i = 0; i < 8; i++) cutoff(26000 + i * 500, 30000 + i * 600),
      ]);
      final out = watchRoadbookFromRoadbook(rb);
      final frame = encodeRoadbook(out.checkpoints!, out.cutoffs!);
      expect(chunkRoadbook(frame).length, lessThanOrEqualTo(2));
    });
  });
}
