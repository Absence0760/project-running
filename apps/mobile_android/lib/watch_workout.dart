import 'dart:math' as math;
import 'dart:typed_data';

import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::workout_store` WKT1
/// wire format — the phone → watch structured-workout push.
///
/// The phone expands a planned workout with `expandWorkoutSteps` (the plan's
/// structure + paces bag live here, not on the watch) and encodes the flat
/// step list as a fixed little-endian frame the firmware decodes into the
/// step machine its workout runner executes:
///
///   magic("WKT1", 4) | version(1) | step_count(1, u8) | flags(1) |
///   step[N] | crc32(4, u32 LE)
///
/// where each step is `kind(1) | rep_index(1) | rep_total(1) |
/// tolerance_s_per_km(1) | target_distance_m(4, u32 LE) |
/// target_duration_s(2, u16 LE) | target_pace_s_per_km(2, u16 LE)`.
///
/// The CRC32 trailer is mandatory from v1 (the CRS1 v3 reasoning): a flipped
/// byte in a target distance decodes as a plausible *different* workout, and
/// per-step validation can't tell 400 m from 4496 m. The firmware rejects a
/// step with both end axes set, so a duration-based step encodes distance 0
/// regardless of the source step's distance field.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeWorkoutSteps]
/// is unit-testable against the frozen golden vector shared with the Rust
/// tests (`watch_core::workout_store`), reusing the run-sync module's [crc32]
/// like `watch_course.dart` / `watch_settings.dart`.
const int _workoutVersion = 0x01;

/// Tier-1 step capacity — mirrors `watch_core::workout::MAX_WORKOUT_STEPS`.
const int kMaxWorkoutSteps = 64;

const int _workoutHeaderLen = 7;
const int _workoutStepLen = 12;
const int _workoutCrcLen = 4;

/// Max payload per chunk = the watch's `WORKOUT_CHUNK_CAP` (244) minus the
/// 2-byte offset header each chunk carries.
const int kWorkoutChunkPayloadMax = 242;

/// The plausibility band the firmware enforces per step's target pace —
/// mirrors `alerts::PACE_BAND_MIN_S_PER_KM..=PACE_BAND_MAX_S_PER_KM`.
const int kWorkoutPaceMinSecPerKm = 120;
const int kWorkoutPaceMaxSecPerKm = 5940;

/// The firmware's max plausible step distance —
/// `pacer::GOAL_DISTANCE_MAX_M`.
const int kWorkoutDistanceMaxM = 1000000;

int _kindCode(WorkoutStepKind kind) {
  switch (kind) {
    case WorkoutStepKind.warmup:
      return 0;
    case WorkoutStepKind.rep:
      return 1;
    case WorkoutStepKind.recovery:
      return 2;
    case WorkoutStepKind.walk:
      return 3;
    case WorkoutStepKind.steady:
      return 4;
    case WorkoutStepKind.cooldown:
      return 5;
  }
}

/// Encode a pre-expanded step list into a WKT1 frame, sealed with the CRC32
/// trailer the watch checks before it will arm the workout. Throws when the
/// list is empty or over [kMaxWorkoutSteps], or when a step carries a target
/// the firmware would reject (no positive end axis, a distance past
/// [kWorkoutDistanceMaxM], a pace outside the plausibility band, a tolerance
/// past the wire's u8, a duration past the wire's u16) — fail-closed at the
/// sender, matching `workout_store::encode`.
Uint8List encodeWorkoutSteps(List<WorkoutStep> steps) {
  if (steps.isEmpty || steps.length > kMaxWorkoutSteps) {
    throw ArgumentError(
      'workout must have 1..$kMaxWorkoutSteps steps, got ${steps.length}',
    );
  }
  final out = ByteData(
    _workoutHeaderLen + steps.length * _workoutStepLen + _workoutCrcLen,
  );
  out.setUint8(0, 0x57); // W
  out.setUint8(1, 0x4b); // K
  out.setUint8(2, 0x54); // T
  out.setUint8(3, 0x31); // 1
  out.setUint8(4, _workoutVersion);
  out.setUint8(5, steps.length);
  out.setUint8(6, 0);

  var off = _workoutHeaderLen;
  for (final s in steps) {
    final durationBased = s.isDurationBased;
    final durationS = durationBased ? s.targetDurationSec! : 0;
    final distanceM = durationBased ? 0 : s.targetDistanceMetres.round();
    if (durationBased ? durationS > 0xFFFF : distanceM <= 0) {
      throw ArgumentError(
        'step "${s.label}" needs one positive end axis inside the wire range',
      );
    }
    if (distanceM > kWorkoutDistanceMaxM) {
      throw ArgumentError('step "${s.label}" distance $distanceM m implausible');
    }
    if (s.targetPaceSecPerKm < kWorkoutPaceMinSecPerKm ||
        s.targetPaceSecPerKm > kWorkoutPaceMaxSecPerKm) {
      throw ArgumentError(
        'step "${s.label}" pace ${s.targetPaceSecPerKm} s/km implausible',
      );
    }
    if (s.toleranceSecPerKm < 0 || s.toleranceSecPerKm > 0xFF) {
      throw ArgumentError(
        'step "${s.label}" tolerance ${s.toleranceSecPerKm} exceeds the wire',
      );
    }
    out.setUint8(off, _kindCode(s.kind));
    out.setUint8(off + 1, s.repIndex ?? 0);
    out.setUint8(off + 2, s.repTotal ?? 0);
    out.setUint8(off + 3, s.toleranceSecPerKm);
    out.setUint32(off + 4, distanceM, Endian.little);
    out.setUint16(off + 8, durationS, Endian.little);
    out.setUint16(off + 10, s.targetPaceSecPerKm, Endian.little);
    off += _workoutStepLen;
  }

  final frame = out.buffer.asUint8List();
  out.setUint32(off, crc32(frame.sublist(0, off)), Endian.little);
  return frame;
}

/// Split a WKT1 [frame] into ordered BLE chunks — each is
/// `offset(2, u16 LE) | payload` — so the watch's `WorkoutAssembler` can
/// rebuild it. The phone writes these in order to the `workout`
/// characteristic.
List<Uint8List> chunkWorkout(
  Uint8List frame, {
  int payloadMax = kWorkoutChunkPayloadMax,
}) {
  final chunks = <Uint8List>[];
  var offset = 0;
  while (offset < frame.length) {
    final end = math.min(offset + payloadMax, frame.length);
    final chunk = Uint8List(2 + (end - offset));
    final view = ByteData.sublistView(chunk);
    view.setUint16(0, offset, Endian.little);
    chunk.setRange(2, chunk.length, frame, offset);
    chunks.add(chunk);
    offset = end;
  }
  return chunks;
}
