import 'dart:typed_data';

import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::workout` WKT1 wire
/// format — the phone → watch structured-workout push (firmware decisions
/// §354).
///
/// The phone expands a planned workout to its flat step list (the same
/// `expandWorkoutSteps` the mobile runner executes) and encodes it as a fixed
/// little-endian frame the firmware decodes into its `WorkoutRunner`:
///
///   magic("WKT1", 4) | version(1) | count(1) | step[N] | crc32(4, u32 LE)
///
/// where each step is `kind(1) | rep_index(1) | rep_total(1) |
/// tolerance_s_per_km(1) | target_distance_m(4, u32 LE) |
/// target_duration_s(2, u16 LE) | target_pace_s_per_km(2, u16 LE)`. A
/// positive duration puts the step on the time axis (the runner's
/// `isDurationBased` rule); rep labels are 1-based with 0 = unlabelled; a
/// zero pace means no target. The kind byte is [WatchWorkoutStepKind]'s
/// declaration index, which mirrors the runner's `WorkoutStepKind` order on
/// both sides — reordering either enum re-points every pushed step.
///
/// Like the course frame (and unlike `SET1`), the CRC trailer is mandatory
/// from v1: most byte patterns are a legal step, so the checksum is the only
/// integrity gate. A whole frame exceeds one BLE write, so [chunkWorkout]
/// splits it into the same ordered `offset(2, u16 LE) | payload` chunks the
/// course push uses; the watch's `WorkoutAssembler` reassembles them.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeWorkout] is
/// unit-testable against the golden frame shared with the Rust test, reusing
/// the run-sync module's [crc32] like every other watch wire mirror.
const int _workoutVersion = 0x01;

/// Tier-1 step capacity — mirrors `watch_core::workout::MAX_WORKOUT_STEPS`.
const int kMaxWorkoutSteps = 32;

const int _workoutHeaderLen = 6;
const int _workoutStepLen = 12;
const int _workoutCrcLen = 4;

/// Max payload per chunk = the watch's chunk characteristic capacity (244)
/// minus the 2-byte offset header — the course push's exact chunk shape.
const int kWorkoutChunkPayloadMax = 242;

/// The firmware's step kinds, in its enum declaration order — which is also
/// the runner's `WorkoutStepKind` order. The wire carries the index, so this
/// list's ORDER is the contract.
enum WatchWorkoutStepKind { warmup, rep, recovery, walk, steady, cooldown }

class WatchWorkoutStep {
  final WatchWorkoutStepKind kind;

  /// 1-based rep labels; 0 = unlabelled (warmups, steady blocks).
  final int repIndex;
  final int repTotal;
  final int toleranceSPerKm;

  /// The end condition: metres when [targetDurationS] is 0, else seconds.
  final int targetDistanceM;
  final int targetDurationS;

  /// 0 = no pace target.
  final int targetPaceSPerKm;

  const WatchWorkoutStep({
    required this.kind,
    this.repIndex = 0,
    this.repTotal = 0,
    this.toleranceSPerKm = 10,
    this.targetDistanceM = 0,
    this.targetDurationS = 0,
    this.targetPaceSPerKm = 0,
  });
}

/// The wire steps for a runner-shaped step list — the seam between the
/// mobile `WorkoutRunner`'s steps and the watch push. Duration-based steps
/// carry their seconds and drop the distance (the firmware's axis rule);
/// distance steps round to whole metres.
List<WatchWorkoutStep> watchWorkoutStepsFrom(List<WorkoutStep> steps) {
  return steps.map((s) {
    final durationBased = s.isDurationBased;
    return WatchWorkoutStep(
      kind: WatchWorkoutStepKind.values[WorkoutStepKind.values.indexOf(s.kind)],
      repIndex: s.repIndex ?? 0,
      repTotal: s.repTotal ?? 0,
      toleranceSPerKm: s.toleranceSecPerKm,
      targetDistanceM: durationBased ? 0 : s.targetDistanceMetres.round(),
      targetDurationS: durationBased ? s.targetDurationSec! : 0,
      targetPaceSPerKm: s.targetPaceSecPerKm,
    );
  }).toList();
}

/// Encode a WKT1 v1 frame, sealed with the CRC32 trailer the watch checks
/// before it will arm the workout. Throws on an empty list, more than
/// [kMaxWorkoutSteps] steps, or a step with no end condition — the same
/// shapes the firmware refuses, failed closed here so a broken push is a
/// thrown error at the seam rather than a silently ignored write.
Uint8List encodeWorkout(List<WatchWorkoutStep> steps) {
  if (steps.isEmpty || steps.length > kMaxWorkoutSteps) {
    throw ArgumentError.value(
      steps.length,
      'steps',
      'a workout push carries 1..=$kMaxWorkoutSteps steps',
    );
  }
  final len =
      _workoutHeaderLen + steps.length * _workoutStepLen + _workoutCrcLen;
  final out = ByteData(len);
  out.setUint8(0, 0x57); // W
  out.setUint8(1, 0x4b); // K
  out.setUint8(2, 0x54); // T
  out.setUint8(3, 0x31); // 1
  out.setUint8(4, _workoutVersion);
  out.setUint8(5, steps.length);
  var off = _workoutHeaderLen;
  for (final s in steps) {
    if (s.targetDistanceM <= 0 && s.targetDurationS <= 0) {
      throw ArgumentError('a step needs a distance or duration end condition');
    }
    out.setUint8(off, s.kind.index);
    out.setUint8(off + 1, s.repIndex);
    out.setUint8(off + 2, s.repTotal);
    out.setUint8(off + 3, s.toleranceSPerKm);
    out.setUint32(off + 4, s.targetDistanceM, Endian.little);
    out.setUint16(off + 8, s.targetDurationS, Endian.little);
    out.setUint16(off + 10, s.targetPaceSPerKm, Endian.little);
    off += _workoutStepLen;
  }
  final frame = out.buffer.asUint8List();
  out.setUint32(off, crc32(frame.sublist(0, off)), Endian.little);
  return frame;
}

/// Split an encoded frame into ordered `offset(2, u16 LE) | payload` chunks
/// sized for one BLE write each — the course push's chunk shape, reassembled
/// by the watch's `WorkoutAssembler`.
List<Uint8List> chunkWorkout(
  Uint8List frame, {
  int payloadMax = kWorkoutChunkPayloadMax,
}) {
  final chunks = <Uint8List>[];
  for (var off = 0; off < frame.length; off += payloadMax) {
    final end = (off + payloadMax) > frame.length ? frame.length : off + payloadMax;
    final chunk = ByteData(2 + end - off);
    chunk.setUint16(0, off, Endian.little);
    chunk.buffer.asUint8List().setRange(2, 2 + end - off, frame, off);
    chunks.add(chunk.buffer.asUint8List());
  }
  return chunks;
}
