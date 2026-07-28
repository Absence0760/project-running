import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart'
    show WorkoutStep, WorkoutStepKind;

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_workout.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('encodeWorkout', () {
    test('the golden frame body matches the firmware vector byte-for-byte', () {
      // The same warmup + paced-rep pair the Rust
      // `a_golden_frame_is_pinned_for_the_dart_encoder` test freezes.
      const steps = [
        WatchWorkoutStep(
          kind: WatchWorkoutStepKind.warmup,
          targetDistanceM: 800,
        ),
        WatchWorkoutStep(
          kind: WatchWorkoutStepKind.rep,
          repIndex: 1,
          repTotal: 3,
          targetDistanceM: 400,
          targetPaceSPerKm: 270,
        ),
      ];
      final frame = encodeWorkout(steps);
      expect(frame, hasLength(6 + 2 * 12 + 4));
      expect(
        frame.sublist(0, frame.length - 4),
        _hex('574b5431' // "WKT1"
            '01' // version
            '02' // count
            '0000000a' '20030000' '0000' '0000'
            '0101030a' '90010000' '0000' '0e01'),
      );
      // The trailer is the derived crc32 of every byte before it — the same
      // derivation the Rust twin asserts over the same body bytes.
      final body = frame.sublist(0, frame.length - 4);
      final trailer = ByteData.sublistView(frame, frame.length - 4)
          .getUint32(0, Endian.little);
      expect(trailer, crc32(body));
    });

    test('the kind byte is the runner enum order on both sides', () {
      // The wire carries the declaration index; the watch pins the same
      // six-value order, so a reorder on either side trips a test.
      expect(WatchWorkoutStepKind.warmup.index, 0);
      expect(WatchWorkoutStepKind.rep.index, 1);
      expect(WatchWorkoutStepKind.recovery.index, 2);
      expect(WatchWorkoutStepKind.walk.index, 3);
      expect(WatchWorkoutStepKind.steady.index, 4);
      expect(WatchWorkoutStepKind.cooldown.index, 5);
      expect(WatchWorkoutStepKind.values, hasLength(6));
      expect(
        WorkoutStepKind.values.map((k) => k.name),
        WatchWorkoutStepKind.values.map((k) => k.name),
      );
    });

    test('a duration step carries its seconds and drops the distance', () {
      final frame = encodeWorkout(const [
        WatchWorkoutStep(
          kind: WatchWorkoutStepKind.rep,
          targetDurationS: 30,
          targetPaceSPerKm: 240,
        ),
      ]);
      expect(
        frame.sublist(0, frame.length - 4),
        _hex('574b5431' '01' '01' '0100000a' '00000000' '1e00' 'f000'),
      );
    });

    test('an empty, oversize, or end-condition-less push throws', () {
      expect(() => encodeWorkout(const []), throwsArgumentError);
      final tooMany = List.filled(
        kMaxWorkoutSteps + 1,
        const WatchWorkoutStep(
          kind: WatchWorkoutStepKind.rep,
          targetDistanceM: 100,
        ),
      );
      expect(() => encodeWorkout(tooMany), throwsArgumentError);
      expect(
        () => encodeWorkout(
          const [WatchWorkoutStep(kind: WatchWorkoutStepKind.rep)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('watchWorkoutStepsFrom', () {
    test('maps the runner steps onto the wire shape per the axis rule', () {
      const steps = [
        WorkoutStep(
          kind: WorkoutStepKind.warmup,
          targetDistanceMetres: 800.4,
          targetPaceSecPerKm: 0,
          label: 'Warmup',
        ),
        WorkoutStep(
          kind: WorkoutStepKind.rep,
          repIndex: 2,
          repTotal: 6,
          targetDistanceMetres: 400,
          targetDurationSec: 90,
          targetPaceSecPerKm: 255,
          toleranceSecPerKm: 12,
          label: 'Rep',
        ),
      ];
      final wire = watchWorkoutStepsFrom(steps);
      expect(wire[0].kind, WatchWorkoutStepKind.warmup);
      expect(wire[0].targetDistanceM, 800);
      expect(wire[0].targetDurationS, 0);
      // A duration-based step (the runner's own isDurationBased rule) drops
      // the distance so the watch cannot pick the wrong axis.
      expect(wire[1].kind, WatchWorkoutStepKind.rep);
      expect(wire[1].targetDistanceM, 0);
      expect(wire[1].targetDurationS, 90);
      expect(wire[1].repIndex, 2);
      expect(wire[1].repTotal, 6);
      expect(wire[1].toleranceSPerKm, 12);
      expect(wire[1].targetPaceSPerKm, 255);
    });
  });

  group('chunkWorkout', () {
    test('chunks carry ascending offsets and reassemble to the frame', () {
      final steps = List.generate(
        kMaxWorkoutSteps,
        (i) => WatchWorkoutStep(
          kind: WatchWorkoutStepKind.rep,
          targetDistanceM: 100 + i,
        ),
      );
      final frame = encodeWorkout(steps);
      expect(frame.length, greaterThan(kWorkoutChunkPayloadMax));
      final chunks = chunkWorkout(frame);
      expect(chunks, hasLength(2));
      final rebuilt = <int>[];
      var expectedOffset = 0;
      for (final c in chunks) {
        final off = ByteData.sublistView(c).getUint16(0, Endian.little);
        expect(off, expectedOffset);
        rebuilt.addAll(c.sublist(2));
        expectedOffset += c.length - 2;
        expect(c.length - 2, lessThanOrEqualTo(kWorkoutChunkPayloadMax));
      }
      expect(rebuilt, frame);
    });
  });
}
