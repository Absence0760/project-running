import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/sim_watch_sync.dart' show crc32;
import '../lib/watch_workout.dart';

/// The frozen golden vector — kept byte-identical to the firmware's
/// `watch_core::workout_store` golden test (the six-step demo workout:
/// warmup, 2x (rep / 90 s walk recovery), steady, cooldown), so a wire-format
/// drift on either side is caught here.
const _goldenHex =
    '574b54310106000000000a20030000000068010101020a900100000000f0'
    '000301010f000000005a00a4010102020a900100000000f0000400000ce8'
    '03000000002c010500000a5802000000006801a9d7dbb8';

const _crcLen = 4;
const _headerLen = 7;
const _stepLen = 12;

WorkoutStep _dist({
  required WorkoutStepKind kind,
  int? repIndex,
  int? repTotal,
  required double distanceM,
  required int pace,
  int tolerance = 10,
}) {
  return WorkoutStep(
    kind: kind,
    repIndex: repIndex,
    repTotal: repTotal,
    targetDistanceMetres: distanceM,
    targetPaceSecPerKm: pace,
    toleranceSecPerKm: tolerance,
    label: 'test',
  );
}

/// The demo workout the Rust golden test pins, built from the same
/// `run_recorder` step type `expandWorkoutSteps` emits.
List<WorkoutStep> _demoSteps() {
  return [
    _dist(kind: WorkoutStepKind.warmup, distanceM: 800, pace: 360),
    _dist(
      kind: WorkoutStepKind.rep,
      repIndex: 1,
      repTotal: 2,
      distanceM: 400,
      pace: 240,
    ),
    const WorkoutStep(
      kind: WorkoutStepKind.walk,
      repIndex: 1,
      repTotal: 1,
      targetDistanceMetres: 0,
      targetDurationSec: 90,
      targetPaceSecPerKm: 420,
      toleranceSecPerKm: 15,
      label: 'test',
    ),
    _dist(
      kind: WorkoutStepKind.rep,
      repIndex: 2,
      repTotal: 2,
      distanceM: 400,
      pace: 240,
    ),
    _dist(
      kind: WorkoutStepKind.steady,
      distanceM: 1000,
      pace: 300,
      tolerance: 12,
    ),
    _dist(kind: WorkoutStepKind.cooldown, distanceM: 600, pace: 360),
  ];
}

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('encodeWorkoutSteps', () {
    test('the demo workout matches the golden vector byte-for-byte', () {
      final frame = encodeWorkoutSteps(_demoSteps());
      expect(frame, _hex(_goldenHex));
      expect(frame, hasLength(_headerLen + 6 * _stepLen + _crcLen));
    });

    test('header carries magic, version, count, and empty flags', () {
      final frame = encodeWorkoutSteps(_demoSteps());
      expect(frame.sublist(0, 4), [0x57, 0x4b, 0x54, 0x31]);
      expect(frame[4], 0x01);
      expect(frame[5], 6);
      expect(frame[6], 0);
    });

    test('the trailer is the derived crc32 of everything before it', () {
      final frame = encodeWorkoutSteps(_demoSteps());
      final body = frame.length - _crcLen;
      final want = crc32(frame.sublist(0, body));
      expect(
        ByteData.sublistView(frame).getUint32(body, Endian.little),
        want,
      );
    });

    test('a duration step encodes distance 0 and its seconds', () {
      final frame = encodeWorkoutSteps(_demoSteps());
      final walkAt = _headerLen + 2 * _stepLen;
      final view = ByteData.sublistView(frame);
      expect(frame[walkAt], 3, reason: 'walk kind code');
      expect(view.getUint32(walkAt + 4, Endian.little), 0);
      expect(view.getUint16(walkAt + 8, Endian.little), 90);
      expect(view.getUint16(walkAt + 10, Endian.little), 420);
    });

    test('rejects an empty or over-cap step list', () {
      expect(() => encodeWorkoutSteps(const []), throwsArgumentError);
      final over = List<WorkoutStep>.filled(
        kMaxWorkoutSteps + 1,
        _dist(kind: WorkoutStepKind.rep, distanceM: 100, pace: 300),
      );
      expect(() => encodeWorkoutSteps(over), throwsArgumentError);
      final atCap = List<WorkoutStep>.filled(
        kMaxWorkoutSteps,
        _dist(kind: WorkoutStepKind.rep, distanceM: 100, pace: 300),
      );
      expect(encodeWorkoutSteps(atCap), isA<Uint8List>());
    });

    test('rejects a step the firmware would refuse', () {
      expect(
        () => encodeWorkoutSteps(
          [_dist(kind: WorkoutStepKind.rep, distanceM: 0, pace: 300)],
        ),
        throwsArgumentError,
        reason: 'no end axis',
      );
      expect(
        () => encodeWorkoutSteps(
          [_dist(kind: WorkoutStepKind.rep, distanceM: 2000000, pace: 300)],
        ),
        throwsArgumentError,
        reason: 'implausible distance',
      );
      expect(
        () => encodeWorkoutSteps(
          [_dist(kind: WorkoutStepKind.rep, distanceM: 400, pace: 60)],
        ),
        throwsArgumentError,
        reason: 'pace beyond any human',
      );
      expect(
        () => encodeWorkoutSteps(
          [_dist(kind: WorkoutStepKind.rep, distanceM: 400, pace: 6000)],
        ),
        throwsArgumentError,
        reason: 'pace past the live ceiling',
      );
      expect(
        () => encodeWorkoutSteps([
          _dist(
            kind: WorkoutStepKind.rep,
            distanceM: 400,
            pace: 300,
            tolerance: 300,
          ),
        ]),
        throwsArgumentError,
        reason: 'tolerance past the wire u8',
      );
    });

    test('an expanded plan round-trips through the encoder', () {
      final steps = expandWorkoutSteps(
        structure: {
          'warmup': {'distance_m': 800, 'pace': 'easy'},
          'repeats': {
            'count': 2,
            'distance_m': 400,
            'pace_sec_per_km': 240,
            'recovery_duration_s': 90,
            'recovery_pace': 'walk',
          },
          'cooldown': {'distance_m': 600, 'pace': 'easy'},
        },
        paces: {'easy': 360},
        toleranceSecPerKm: 10,
      );
      final frame = encodeWorkoutSteps(steps);
      expect(frame[5], steps.length);
      expect(frame.length, _headerLen + steps.length * _stepLen + _crcLen);
    });
  });

  group('chunkWorkout', () {
    test('splits a frame into ordered offset-tagged chunks', () {
      final frame = encodeWorkoutSteps(_demoSteps());
      final chunks = chunkWorkout(frame, payloadMax: 16);
      var offset = 0;
      final rebuilt = <int>[];
      for (final chunk in chunks) {
        final view = ByteData.sublistView(chunk);
        expect(view.getUint16(0, Endian.little), offset);
        rebuilt.addAll(chunk.sublist(2));
        offset += chunk.length - 2;
      }
      expect(rebuilt, frame);
    });

    test('a frame under the payload cap travels as one chunk', () {
      final frame = encodeWorkoutSteps([
        _dist(kind: WorkoutStepKind.steady, distanceM: 5000, pace: 330),
      ]);
      final chunks = chunkWorkout(frame);
      expect(chunks, hasLength(1));
      expect(chunks.first.length, frame.length + 2);
    });
  });
}
