// Training engine — Dart port of apps/web/src/lib/training.ts.
//
// Must produce byte-identical paces + phase labels for the same inputs. If
// you change a number here, change it in training.ts and re-run both test
// suites. See docs/features/training.md.

import 'dart:math';

import 'l10n/locale_support.dart' show activeLocaleTag;
import 'l10n/number_format.dart' show formatFixed;
import 'preferences.dart' show DistanceUnit, activeDistanceUnit;

enum GoalEvent { distance5k, distance10k, distanceHalf, distanceFull, custom }

enum WorkoutKind {
  easy,
  long,
  recovery,
  tempo,
  interval,
  marathonPace,
  walkRun,
  race,
  rest,
}

enum PlanPhase { base, build, peak, taper, race }

const Map<GoalEvent, double> kGoalDistancesM = {
  GoalEvent.distance5k: 5000,
  GoalEvent.distance10k: 10000,
  GoalEvent.distanceHalf: 21097.5,
  GoalEvent.distanceFull: 42195,
};

const Map<GoalEvent, int> _defaultWeeks = {
  GoalEvent.distance5k: 8,
  GoalEvent.distance10k: 8,
  GoalEvent.distanceHalf: 12,
  GoalEvent.distanceFull: 16,
};

int defaultPlanWeeks(GoalEvent g) =>
    g == GoalEvent.custom ? 12 : _defaultWeeks[g]!;

/// Default week count for a beginner C25K walk-run plan. The continuous-run
/// default (`defaultPlanWeeks(GoalEvent.distance5k)` = 8) is one week shorter
/// than the `kWalkRunProgression` table, so feeding it to the walk-run
/// generator drops the final graduation week (the single continuous run).
/// Callers that build a beginner plan should size `weeks` from this, not
/// `defaultPlanWeeks`. Mirrors `walkRunDefaultWeeks` in training.ts. Persona
/// round-5 runner-new.
int walkRunDefaultWeeks() => kWalkRunProgression.length;

String goalEventDbValue(GoalEvent g) => switch (g) {
      GoalEvent.distance5k => 'distance_5k',
      GoalEvent.distance10k => 'distance_10k',
      GoalEvent.distanceHalf => 'distance_half',
      GoalEvent.distanceFull => 'distance_full',
      GoalEvent.custom => 'custom',
    };

GoalEvent goalEventFromDb(String s) => switch (s) {
      'distance_5k' => GoalEvent.distance5k,
      'distance_10k' => GoalEvent.distance10k,
      'distance_half' => GoalEvent.distanceHalf,
      'distance_full' => GoalEvent.distanceFull,
      _ => GoalEvent.custom,
    };

String goalEventLabel(GoalEvent g) => switch (g) {
      GoalEvent.distance5k => '5K',
      GoalEvent.distance10k => '10K',
      GoalEvent.distanceHalf => 'Half marathon',
      GoalEvent.distanceFull => 'Marathon',
      GoalEvent.custom => 'Custom',
    };

WorkoutKind workoutKindFromDb(String s) => switch (s) {
      'easy' => WorkoutKind.easy,
      'long' => WorkoutKind.long,
      'recovery' => WorkoutKind.recovery,
      'tempo' => WorkoutKind.tempo,
      'interval' => WorkoutKind.interval,
      'marathon_pace' => WorkoutKind.marathonPace,
      'walk_run' => WorkoutKind.walkRun,
      'race' => WorkoutKind.race,
      _ => WorkoutKind.rest,
    };

String workoutKindDbValue(WorkoutKind k) => switch (k) {
      WorkoutKind.easy => 'easy',
      WorkoutKind.long => 'long',
      WorkoutKind.recovery => 'recovery',
      WorkoutKind.tempo => 'tempo',
      WorkoutKind.interval => 'interval',
      WorkoutKind.marathonPace => 'marathon_pace',
      WorkoutKind.walkRun => 'walk_run',
      WorkoutKind.race => 'race',
      WorkoutKind.rest => 'rest',
    };


PlanPhase planPhaseFromDb(String s) => switch (s) {
      'base' => PlanPhase.base,
      'build' => PlanPhase.build,
      'peak' => PlanPhase.peak,
      'taper' => PlanPhase.taper,
      'race' => PlanPhase.race,
      _ => PlanPhase.base,
    };

String planPhaseDbValue(PlanPhase p) => switch (p) {
      PlanPhase.base => 'base',
      PlanPhase.build => 'build',
      PlanPhase.peak => 'peak',
      PlanPhase.taper => 'taper',
      PlanPhase.race => 'race',
    };

// ─────────────────────── VDOT ───────────────────────

double vdotFromRace(double distanceMetres, int timeSeconds) {
  final minutes = timeSeconds / 60.0;
  final v = distanceMetres / minutes;
  final vo2 = -4.6 + 0.182258 * v + 0.000104 * v * v;
  final pct = 0.8 +
      0.1894393 * exp(-0.012778 * minutes) +
      0.2989558 * exp(-0.1932605 * minutes);
  return vo2 / pct;
}

double riegelPredict(double knownDistanceM, int knownTimeSec, double targetDistanceM,
    [double exponent = 1.06]) {
  return knownTimeSec * pow(targetDistanceM / knownDistanceM, exponent).toDouble();
}

enum PredictionConfidence { high, moderate, low }

/// Machine-readable reason code for the binding limit on a prediction's
/// confidence. Mirrors the web `PredictionReason` union.
enum PredictionReason { similar, extrapolated, stale, limited }

class PredictionQuality {
  final PredictionConfidence confidence;
  final PredictionReason reason;
  const PredictionQuality(this.confidence, this.reason);
}

/// Beyond this Riegel extrapolation factor the prediction is little
/// better than a guess (a marathon off a 5k is ~8.4x). Caps at 'low'.
const double _riegelFarFactor = 4;

/// Grade the data quality behind a Riegel race-time prediction. Mirrors
/// the web `predictionConfidence` 1:1 — keep the thresholds in lockstep.
PredictionQuality predictionConfidence({
  required double knownDistanceM,
  required double targetDistanceM,
  required int daysSinceBest,
  required int qualifyingRunCount,
}) {
  if (knownDistanceM <= 0 || targetDistanceM <= 0 || qualifyingRunCount <= 0) {
    return const PredictionQuality(
        PredictionConfidence.low, PredictionReason.limited);
  }
  final ratio = targetDistanceM / knownDistanceM;
  final factor = ratio > 1 / ratio ? ratio : 1 / ratio;

  if (factor > _riegelFarFactor) {
    return const PredictionQuality(
        PredictionConfidence.low, PredictionReason.extrapolated);
  }

  // A >60d anchor is too stale to anchor a race-day prediction at all, so it
  // caps confidence at 'low' regardless of the distance gap. Checked before
  // the distance-gap branch below: otherwise a far-AND-stale prediction fell
  // through to `!closeDistance` → 'moderate', outranking a close-BUT-stale one
  // ('low') — a doubly-bad prediction can never be more confident than a
  // singly-bad one.
  if (daysSinceBest > 60) {
    return const PredictionQuality(
        PredictionConfidence.low, PredictionReason.stale);
  }

  final closeDistance = factor <= 2;
  final recent = daysSinceBest <= 30;
  final wellSampled = qualifyingRunCount >= 3;

  if (closeDistance && recent && wellSampled) {
    return const PredictionQuality(
        PredictionConfidence.high, PredictionReason.similar);
  }

  if (!closeDistance) {
    return const PredictionQuality(
        PredictionConfidence.moderate, PredictionReason.extrapolated);
  }
  // 31–60 days: a soft staleness caveat (the harder >60d case already
  // returned 'low' above).
  if (!recent) {
    return const PredictionQuality(
        PredictionConfidence.moderate, PredictionReason.stale);
  }
  return const PredictionQuality(
      PredictionConfidence.moderate, PredictionReason.limited);
}

// ─────────────────────── Paces ───────────────────────

class TrainingPaces {
  final int easy;
  final int marathon;
  final int tempo;
  final int interval;
  final int repetition;

  const TrainingPaces({
    required this.easy,
    required this.marathon,
    required this.tempo,
    required this.interval,
    required this.repetition,
  });
}

/// Optional gender hint for pace derivation. Matches the `gender`
/// column on `user_profiles`. Mirrored from web
/// `training.ts#TrainingGender`. Persona-hunt Round 3 finding Woman #3.
typedef TrainingGender = String?; // 'male' | 'female' | 'nonbinary' | null

// Female-specific calibration constant. See web training.ts for the
// full rationale comment; keep both helpers in lockstep.
const double _kFemalePaceCalibration = 1.03;

double _genderPaceMultiplier(TrainingGender gender) =>
    gender == 'female' ? _kFemalePaceCalibration : 1.0;

// Masters (50+) recovery calibration. Mirrors MASTERS_AGE +
// isMastersAge in apps/web/src/lib/training.ts — see the full rationale
// comment there. At or above this age the plan widens the first hard
// day to 72h after the long run (Wed not Tue, second hard day Fri not
// Thu) and steps volume back every 3rd week instead of every 4th. Pace
// bands stay on the shared Daniels curve. Persona-hunt finding Older
// #30.
const int kMastersAge = 50;

bool isMastersAge(int? age) => age != null && age >= kMastersAge;

/// Web `isWorkoutSkipped` twin — a planned workout is "skipped" when the
/// runner deliberately dropped it (`skippedAt` stamped). Skip and done
/// are mutually exclusive at the write layer, so a skipped workout is
/// neither a debt (it leaves the progress denominator) nor an
/// achievement (it isn't done). Read sites that filter the active
/// to-do set exclude skipped alongside completed.
bool isWorkoutSkipped(DateTime? skippedAt) => skippedAt != null;

TrainingPaces pacesFromGoalPace(
  double goalPaceSecPerKm, [
  TrainingGender gender,
]) {
  final g = _genderPaceMultiplier(gender);
  return TrainingPaces(
    easy: (goalPaceSecPerKm * 1.22 * g).round(),
    marathon: (goalPaceSecPerKm * 1.06 * g).round(),
    tempo: (goalPaceSecPerKm * 0.97 * g).round(),
    interval: (goalPaceSecPerKm * 0.9 * g).round(),
    repetition: (goalPaceSecPerKm * 0.85 * g).round(),
  );
}

/// The conservative goal pace (sec/km) used when the runner gave us neither a
/// recent race nor a goal time. ~10:00/km. `resolveTrainingPacesWithMeta`
/// flags when it's in play so the caller can disclose it instead of
/// presenting it as real. Mirrors training.ts. Persona round-5
/// runner-comeback.
const double _kFallbackGoalPaceSecPerKm = 600;

class ResolvedPaces {
  final TrainingPaces paces;
  final bool isFallback;
  const ResolvedPaces(this.paces, this.isFallback);
}

/// Resolve the runner's training paces plus whether they came from a real
/// fitness anchor or the conservative fallback. `isFallback` is true only when
/// neither a recent 5k nor a goal time was given. The numbers are always
/// usable; the flag lets the wizard label the preview "estimated — add a
/// recent run for personalised paces". Mirrors `resolveTrainingPacesWithMeta`
/// in training.ts. Persona round-5 runner-comeback.
ResolvedPaces resolveTrainingPacesWithMeta({
  required double goalDistanceM,
  int? goalTimeSec,
  int? recent5kSec,
  TrainingGender gender,
}) {
  double goalPace;
  var isFallback = false;
  // Positivity, not just non-null: a 0 anchor is "no usable time" (matches the
  // web twin's JS truthiness). Treating `0 != null` as a real anchor ran Riegel
  // on a 0 time → goalPace 0 → every pace band rounded to 0, and suppressed the
  // "estimated paces" fallback flag — a plan whose every target was 0:00/km.
  if (recent5kSec != null && recent5kSec > 0) {
    final predicted = riegelPredict(5000, recent5kSec, goalDistanceM);
    goalPace = predicted / (goalDistanceM / 1000);
  } else if (goalTimeSec != null && goalTimeSec > 0) {
    goalPace = goalTimeSec / (goalDistanceM / 1000);
  } else {
    goalPace = _kFallbackGoalPaceSecPerKm;
    isFallback = true;
  }
  return ResolvedPaces(pacesFromGoalPace(goalPace, gender), isFallback);
}

TrainingPaces resolveTrainingPaces({
  required double goalDistanceM,
  int? goalTimeSec,
  int? recent5kSec,
  TrainingGender gender,
}) {
  return resolveTrainingPacesWithMeta(
    goalDistanceM: goalDistanceM,
    goalTimeSec: goalTimeSec,
    recent5kSec: recent5kSec,
    gender: gender,
  ).paces;
}

// ─────────────────────── Phases ───────────────────────

PlanPhase phaseFor(int weekIndex, int totalWeeks) {
  final base = (totalWeeks * 0.3).floor();
  final build = (totalWeeks * 0.4).floor();
  final peak = (totalWeeks * 0.2).floor();
  if (weekIndex >= totalWeeks - 1) return PlanPhase.race;
  if (weekIndex < base) return PlanPhase.base;
  if (weekIndex < base + build) return PlanPhase.build;
  if (weekIndex < base + build + peak) return PlanPhase.peak;
  return PlanPhase.taper;
}

// ─────────────────────── Plan generation ───────────────────────

class WorkoutStructure {
  final Map<String, dynamic>? warmup;
  final Map<String, dynamic>? repeats;
  final Map<String, dynamic>? steady;
  final Map<String, dynamic>? cooldown;

  const WorkoutStructure({this.warmup, this.repeats, this.steady, this.cooldown});

  Map<String, dynamic> toJson() => {
        if (warmup != null) 'warmup': warmup,
        if (repeats != null) 'repeats': repeats,
        if (steady != null) 'steady': steady,
        if (cooldown != null) 'cooldown': cooldown,
      };

  factory WorkoutStructure.fromJson(Map<String, dynamic> j) => WorkoutStructure(
        warmup: j['warmup'] as Map<String, dynamic>?,
        repeats: j['repeats'] as Map<String, dynamic>?,
        steady: j['steady'] as Map<String, dynamic>?,
        cooldown: j['cooldown'] as Map<String, dynamic>?,
      );
}

class GeneratedWorkout {
  final DateTime scheduledDate;
  final WorkoutKind kind;
  final double? targetDistanceM;
  final int? targetDurationSeconds;
  final int? targetPaceSecPerKm;
  final int? targetPaceToleranceSec;
  final WorkoutStructure? structure;
  final String? notes;

  const GeneratedWorkout({
    required this.scheduledDate,
    required this.kind,
    this.targetDistanceM,
    this.targetDurationSeconds,
    this.targetPaceSecPerKm,
    this.targetPaceToleranceSec,
    this.structure,
    this.notes,
  });
}

class GeneratedWeek {
  final int weekIndex;
  final PlanPhase phase;
  final double targetVolumeM;
  final String? notes;
  final List<GeneratedWorkout> workouts;

  const GeneratedWeek({
    required this.weekIndex,
    required this.phase,
    required this.targetVolumeM,
    this.notes,
    required this.workouts,
  });
}

class GeneratedPlan {
  final List<GeneratedWeek> weeks;
  final TrainingPaces paces;
  final double? vdot;
  final DateTime endDate;
  final double goalDistanceM;

  /// True when [paces] are the conservative 10:00/km fallback (no recent
  /// race, no goal time) rather than derived from real fitness. The plan is
  /// still valid; the caller should disclose the paces are estimated. Mirrors
  /// training.ts. Persona round-5 runner-comeback.
  final bool pacesAreFallback;

  const GeneratedPlan({
    required this.weeks,
    required this.paces,
    required this.vdot,
    required this.endDate,
    required this.goalDistanceM,
    required this.pacesAreFallback,
  });
}

class GeneratePlanInput {
  final GoalEvent goalEvent;
  final double? goalDistanceM;
  final int? goalTimeSec;
  final int? recent5kSec;
  final DateTime startDate;
  final int daysPerWeek;
  final int? weeks;
  /// Optional gender from `user_profiles.gender` — applies the
  /// female-specific calibration to derived training paces.
  /// Persona-hunt Round 3 finding Woman #3.
  final TrainingGender gender;

  /// Optional age (years) from `user_profiles.date_of_birth`. At or above
  /// kMastersAge it applies the masters recovery calibration — wider
  /// hard-day spacing + a 3-week build/recover cycle. Persona-hunt
  /// finding Older #30.
  final int? age;

  /// When true, produce a beginner C25K-style walk-run plan instead of the
  /// continuous-running plan. Goal stays a 5k; every session is a walk_run
  /// workout of timed run/walk intervals (persona #22).
  final bool beginnerWalkRun;

  const GeneratePlanInput({
    required this.goalEvent,
    this.goalDistanceM,
    this.goalTimeSec,
    this.recent5kSec,
    required this.startDate,
    required this.daysPerWeek,
    this.weeks,
    this.gender,
    this.age,
    this.beginnerWalkRun = false,
  });
}

GeneratedPlan generatePlan(GeneratePlanInput input) {
  final goalDistance = input.goalEvent == GoalEvent.custom
      ? input.goalDistanceM!
      : kGoalDistancesM[input.goalEvent]!;
  final totalWeeks = input.weeks ?? defaultPlanWeeks(input.goalEvent);
  final resolved = resolveTrainingPacesWithMeta(
    goalDistanceM: goalDistance,
    goalTimeSec: input.goalTimeSec,
    recent5kSec: input.recent5kSec,
    gender: input.gender,
  );
  final paces = resolved.paces;
  final pacesAreFallback = resolved.isFallback;
  // Guard positivity, not just non-null: web uses JS truthiness here so a 0
  // anchor is "no anchor", but `0 != null` is true in Dart — a zero recent-5k
  // / goal-time would otherwise call vdotFromRace with time 0 (velocity =
  // distance/0 = Infinity → non-finite VDOT) and scale peak volume as if a
  // real anchor existed, diverging from web.
  double? vdot;
  if (input.recent5kSec != null && input.recent5kSec! > 0) {
    vdot = vdotFromRace(5000, input.recent5kSec!);
  } else if (input.goalTimeSec != null && input.goalTimeSec! > 0) {
    vdot = vdotFromRace(goalDistance, input.goalTimeSec!);
  }

  if (input.beginnerWalkRun) {
    return _generateWalkRunPlan(input, goalDistance, paces, vdot, pacesAreFallback);
  }

  final weeks = <GeneratedWeek>[];
  final masters = isMastersAge(input.age);
  for (var i = 0; i < totalWeeks; i++) {
    final phase = phaseFor(i, totalWeeks);
    final peakKm = _peakVolumeKm(
        goalDistance,
        input.daysPerWeek,
        (input.goalTimeSec != null && input.goalTimeSec! > 0) ||
            (input.recent5kSec != null && input.recent5kSec! > 0));
    final frac = _mileageFraction(i, totalWeeks, phase, masters);
    final weeklyKm = (peakKm * frac).round();
    final weekStart = input.startDate.add(Duration(days: i * 7));
    final workouts = _generateWeek(
      weekIndex: i,
      phase: phase,
      weekStart: weekStart,
      daysPerWeek: input.daysPerWeek,
      weeklyKm: weeklyKm,
      paces: paces,
      goalDistanceM: goalDistance,
      goalPaceSecPerKm: paces.marathon * (goalDistance >= 21000 ? 1 : 0.95),
      masters: masters,
    );
    // The stated weekly volume must equal what the week actually
    // prescribes. The emitted workouts are rounded/floored per-day (easy
    // filler clamps to >=3 km, intervals/tempo/long carry their own
    // distances), so `weeklyKm * 1000` overstated the real ask by ~25-70%
    // on small-volume (5k/half) plans. Sum the emitted distances so the
    // headline number is honest. Quality + long run stay uncapped (that's
    // training design); only the stated total is reconciled. Mirrors
    // training.ts.
    weeks.add(GeneratedWeek(
      weekIndex: i,
      phase: phase,
      targetVolumeM:
          workouts.fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0)),
      notes: _weekNote(phase, i, totalWeeks, masters),
      workouts: workouts,
    ));
  }

  return GeneratedPlan(
    weeks: weeks,
    paces: paces,
    vdot: vdot,
    endDate: input.startDate.add(Duration(days: totalWeeks * 7 - 1)),
    goalDistanceM: goalDistance,
    pacesAreFallback: pacesAreFallback,
  );
}

// ─────────────────────── Beginner walk-run (C25K) ───────────────────────
// Mirror of WALK_RUN_PROGRESSION / generateWalkRunPlan in
// apps/web/src/lib/training.ts — keep in lockstep.
const kWalkRunProgression = <({int runSec, int walkSec, int count})>[
  (runSec: 60, walkSec: 90, count: 8),
  (runSec: 90, walkSec: 120, count: 7),
  (runSec: 120, walkSec: 120, count: 6),
  (runSec: 180, walkSec: 120, count: 5),
  (runSec: 300, walkSec: 120, count: 4),
  (runSec: 480, walkSec: 150, count: 3),
  (runSec: 600, walkSec: 120, count: 3),
  (runSec: 900, walkSec: 180, count: 2),
  (runSec: 1500, walkSec: 0, count: 1),
];
const _kWalkRunWarmupS = 300;
const _kWalkRunCooldownS = 300;
const _kWalkPaceSecPerKm = 700;

GeneratedWorkout _walkRunWorkout(
    DateTime date, int weekIndex, int easyPaceSecPerKm) {
  final prog = kWalkRunProgression[
      weekIndex < kWalkRunProgression.length
          ? weekIndex
          : kWalkRunProgression.length - 1];
  final hasRecovery = prog.count > 1 && prog.walkSec > 0;
  final repeats = <String, dynamic>{
    'count': prog.count,
    'duration_s': prog.runSec,
    'pace_sec_per_km': easyPaceSecPerKm,
    'recovery_pace': 'walk',
    if (hasRecovery) 'recovery_duration_s': prog.walkSec,
  };
  final totalRunSec = prog.count * prog.runSec;
  final totalWalkSec =
      (hasRecovery ? (prog.count - 1) * prog.walkSec : 0) +
          _kWalkRunWarmupS +
          _kWalkRunCooldownS;
  final estDistanceM =
      ((totalRunSec * 1000) / easyPaceSecPerKm +
              (totalWalkSec * 1000) / _kWalkPaceSecPerKm)
          .round()
          .toDouble();
  return GeneratedWorkout(
    scheduledDate: date,
    kind: WorkoutKind.walkRun,
    targetDistanceM: estDistanceM,
    targetDurationSeconds: totalRunSec + totalWalkSec,
    targetPaceSecPerKm: easyPaceSecPerKm,
    structure: WorkoutStructure(
      warmup: {'duration_s': _kWalkRunWarmupS, 'pace': 'easy'},
      repeats: repeats,
      cooldown: {'duration_s': _kWalkRunCooldownS, 'pace': 'easy'},
    ),
    notes: hasRecovery
        ? 'Walk ${_kWalkRunWarmupS ~/ 60} min, then run ${prog.runSec}s / walk ${prog.walkSec}s × ${prog.count}, walk ${_kWalkRunCooldownS ~/ 60} min.'
        : 'Walk ${_kWalkRunWarmupS ~/ 60} min, run ${(prog.runSec / 60).round()} min continuous, walk ${_kWalkRunCooldownS ~/ 60} min. Graduation week.',
  );
}

GeneratedPlan _generateWalkRunPlan(GeneratePlanInput input,
    double goalDistanceM, TrainingPaces paces, double? vdot,
    bool pacesAreFallback) {
  // Never run fewer weeks than the progression has stages — truncating it
  // drops the final graduation week (the single continuous run), which is the
  // whole point of a C25K plan. A default 5k plan arrives here with weeks=8
  // (defaultPlanWeeks(distance5k)) against a 9-stage table, so without this
  // floor the graduation week silently vanishes. Persona round-5 runner-new.
  // A longer request is honoured (the last stage repeats via the index clamp
  // in _walkRunWorkout). Mirrors training.ts.
  final totalWeeks =
      max(input.weeks ?? kWalkRunProgression.length, kWalkRunProgression.length);
  final runDays = input.daysPerWeek.clamp(1, 3);
  final dayOffsets = [0, 2, 4, 1, 3, 5, 6].sublist(0, runDays)..sort();
  final runSet = dayOffsets.toSet();
  final weeks = <GeneratedWeek>[];
  for (var i = 0; i < totalWeeks; i++) {
    final weekStart = input.startDate.add(Duration(days: i * 7));
    final workouts = <GeneratedWorkout>[];
    for (var d = 0; d < 7; d++) {
      final date = weekStart.add(Duration(days: d));
      if (runSet.contains(d)) {
        workouts.add(_walkRunWorkout(date, i, paces.easy));
      } else {
        workouts.add(GeneratedWorkout(
          scheduledDate: date,
          kind: WorkoutKind.rest,
        ));
      }
    }
    weeks.add(GeneratedWeek(
      weekIndex: i,
      phase: i == totalWeeks - 1 ? PlanPhase.race : PlanPhase.build,
      targetVolumeM:
          workouts.fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0)),
      notes: i == totalWeeks - 1
          ? 'Final week — you can run the distance continuously now.'
          : 'Take the walk breaks even when you feel good — they make the runs sustainable.',
      workouts: workouts,
    ));
  }
  return GeneratedPlan(
    weeks: weeks,
    paces: paces,
    vdot: vdot,
    endDate: input.startDate.add(Duration(days: totalWeeks * 7 - 1)),
    goalDistanceM: goalDistanceM,
    pacesAreFallback: pacesAreFallback,
  );
}

double _peakVolumeKm(double goalDistanceM, int daysPerWeek,
    [bool hasAnchor = true]) {
  final baseMul = goalDistanceM <= 10000
      ? 5.0
      : goalDistanceM <= 21100
          ? 2.5
          : 1.8;
  final dayFactor = 0.7 + (daysPerWeek - 3) * 0.1;
  // No fitness anchor (no goal time, no recent 5k) -> scale the peak down so
  // a no-info 5k plan doesn't open with a punishing week 1 (new persona #23).
  final anchorFactor = hasAnchor ? 1.0 : 0.6;
  return ((goalDistanceM / 1000) * baseMul * dayFactor * anchorFactor)
      .roundToDouble();
}

// Masters recover on a 3-week cycle; the default is 4 weeks. Week 0 is
// never a step-back so the plan doesn't open on a recovery week.
bool _isStepBackWeek(int i, bool masters) {
  if (i == 0) return false;
  return masters ? i % 3 == 2 : i % 4 == 3;
}

double _mileageFraction(int i, int total, PlanPhase phase,
    [bool masters = false]) {
  if (phase == PlanPhase.race) return 0.35;
  if (phase == PlanPhase.taper) return 0.55;
  final ramp = 0.6 + (0.4 * i) / max(1, total - 3);
  final stepBack = _isStepBackWeek(i, masters) ? 0.82 : 1;
  return min(1.0, ramp * stepBack);
}

String? _weekNote(PlanPhase phase, int i, int total, [bool masters = false]) {
  if (phase == PlanPhase.race) return 'Race week — trust the work.';
  if (phase == PlanPhase.taper) return 'Taper — volume down, sharpness stays.';
  if (_isStepBackWeek(i, masters)) {
    return 'Step-back week — recover before the next build.';
  }
  return null;
}

List<GeneratedWorkout> _generateWeek({
  required int weekIndex,
  required PlanPhase phase,
  required DateTime weekStart,
  required int daysPerWeek,
  required int weeklyKm,
  required TrainingPaces paces,
  required double goalDistanceM,
  required double goalPaceSecPerKm,
  bool masters = false,
}) {
  // Same allocation as web: Mon rest, Sun long, Tue qualityA, Thu qualityB.
  // Masters (Older #30) push the first quality day to Wed (72h after the
  // Sunday long run) and the second to Fri, keeping ~48h between hards.
  // Monday is the rest day — UNLESS the runner asked to run all 7 days, in
  // which case there is no rest day (restDow = -1, a dow no day matches) and
  // Monday falls through to an easy run. Both wizards offer up to 7 d/wk; a
  // hardwired Monday rest silently capped a 7-day plan at 6 active days.
  final restDow = daysPerWeek >= 7 ? -1 : 1;
  const longDow = 0;
  final qaDow = masters ? 3 : 2; // Wed for masters, else Tue
  final qbDow = masters ? 5 : 4; // Fri for masters, else Thu
  final workouts = <GeneratedWorkout>[];

  final longKm = (weeklyKm * 0.33).round();
  final quality = _allocateQuality(
    phase: phase,
    daysPerWeek: daysPerWeek,
    paces: paces,
    goalDistanceM: goalDistanceM,
  );
  final qualityKm = (quality.a?.targetDistanceM ?? 0) / 1000 +
      (quality.b?.targetDistanceM ?? 0) / 1000;
  final remaining = max(0.0, weeklyKm - longKm - qualityKm);
  final daysUsed = restDow >= 0 ? <int>{longDow, restDow} : <int>{longDow};
  // Persona-hunt Intermediate #4: a 3-day plan used to be all
  // long-run + easy with zero quality across every phase. Drop the
  // gate from >=4 to >=3 so 3-day plans get one tempo/interval per
  // week (the phase picks which). Race + recovery phases still
  // produce a null quality.a and fall through to easy below.
  if (daysPerWeek >= 3) daysUsed.add(qaDow);
  if (daysPerWeek >= 5) daysUsed.add(qbDow);
  final easyDays = daysPerWeek - daysUsed.where((d) => d != restDow).length;
  final easyKm = easyDays > 0 ? remaining / easyDays : 0.0;

  for (var dow = 0; dow < 7; dow++) {
    final date = DateTime(weekStart.year, weekStart.month, weekStart.day)
        .add(Duration(days: dow));
    if (dow == restDow) {
      workouts.add(GeneratedWorkout(
        scheduledDate: date,
        kind: WorkoutKind.rest,
      ));
      continue;
    }
    if (dow == longDow) {
      if (phase == PlanPhase.race) {
        workouts.add(GeneratedWorkout(
          scheduledDate: date,
          kind: WorkoutKind.race,
          targetDistanceM: goalDistanceM,
          targetPaceSecPerKm: goalPaceSecPerKm.round(),
          targetPaceToleranceSec: 5,
          notes: 'Race day. Execute the plan.',
        ));
      } else {
        workouts.add(_longRun(date, longKm, paces));
      }
      continue;
    }
    if (dow == qaDow && daysPerWeek >= 3 && quality.a != null) {
      workouts.add(quality.a!._withDate(date));
      continue;
    }
    if (dow == qbDow && daysPerWeek >= 5 && quality.b != null) {
      workouts.add(quality.b!._withDate(date));
      continue;
    }
    workouts.add(_easy(date, easyKm, paces));
  }

  return _limitToDays(workouts, daysPerWeek);
}

class _QualityPair {
  final GeneratedWorkout? a;
  final GeneratedWorkout? b;
  const _QualityPair(this.a, this.b);
}

_QualityPair _allocateQuality({
  required PlanPhase phase,
  required int daysPerWeek,
  required TrainingPaces paces,
  required double goalDistanceM,
}) {
  GeneratedWorkout? a, b;
  final placeholder = DateTime(2000, 1, 1);
  if (phase == PlanPhase.base) {
    if (daysPerWeek >= 3) a = _tempo(placeholder, 6, paces);
  } else if (phase == PlanPhase.build) {
    if (daysPerWeek >= 3) a = _intervals(placeholder, paces);
    if (daysPerWeek >= 5) b = _tempo(placeholder, 7, paces);
  } else if (phase == PlanPhase.peak) {
    if (daysPerWeek >= 3) a = _intervals(placeholder, paces);
    if (daysPerWeek >= 5) b = _marathonPace(placeholder, paces, goalDistanceM);
  } else if (phase == PlanPhase.taper) {
    if (daysPerWeek >= 3) a = _tempo(placeholder, 4, paces);
  }
  return _QualityPair(a, b);
}

GeneratedWorkout _longRun(DateTime date, int km, TrainingPaces p) => GeneratedWorkout(
      scheduledDate: date,
      kind: WorkoutKind.long,
      targetDistanceM: km * 1000.0,
      targetPaceSecPerKm: p.easy,
      targetPaceToleranceSec: 20,
    );

GeneratedWorkout _easy(DateTime date, double km, TrainingPaces p) => GeneratedWorkout(
      scheduledDate: date,
      kind: km < 4 ? WorkoutKind.recovery : WorkoutKind.easy,
      targetDistanceM: max(3, km.round()) * 1000.0,
      targetPaceSecPerKm: p.easy,
      targetPaceToleranceSec: 30,
    );

GeneratedWorkout _tempo(DateTime date, int totalKm, TrainingPaces p) {
  final steady = max(2, totalKm - 3);
  return GeneratedWorkout(
    scheduledDate: date,
    kind: WorkoutKind.tempo,
    targetDistanceM: totalKm * 1000.0,
    targetPaceSecPerKm: p.tempo,
    targetPaceToleranceSec: 8,
    structure: WorkoutStructure(
      warmup: {'distance_m': 1500, 'pace': 'easy'},
      steady: {'distance_m': steady * 1000, 'pace_sec_per_km': p.tempo},
      cooldown: {'distance_m': 1500, 'pace': 'easy'},
    ),
    notes: 'Tempo: $steady km @ threshold.',
  );
}

GeneratedWorkout _intervals(DateTime date, TrainingPaces p) {
  const reps = 5, repDistance = 1000, recovery = 400;
  return GeneratedWorkout(
    scheduledDate: date,
    kind: WorkoutKind.interval,
    targetDistanceM: (1500 + reps * (repDistance + recovery) + 1500).toDouble(),
    targetPaceSecPerKm: p.interval,
    targetPaceToleranceSec: 5,
    structure: WorkoutStructure(
      warmup: {'distance_m': 1500, 'pace': 'easy'},
      repeats: {
        'count': reps,
        'distance_m': repDistance,
        'pace_sec_per_km': p.interval,
        'recovery_distance_m': recovery,
        'recovery_pace': 'jog',
      },
      cooldown: {'distance_m': 1500, 'pace': 'easy'},
    ),
    notes: '$reps× $repDistance m @ VO2 with $recovery m jog.',
  );
}

GeneratedWorkout _marathonPace(DateTime date, TrainingPaces p, double goalDistanceM) {
  final mpKm = goalDistanceM >= 21000 ? 10 : 5;
  return GeneratedWorkout(
    scheduledDate: date,
    kind: WorkoutKind.marathonPace,
    targetDistanceM: (mpKm + 3) * 1000.0,
    targetPaceSecPerKm: p.marathon,
    targetPaceToleranceSec: 8,
    structure: WorkoutStructure(
      warmup: {'distance_m': 1500, 'pace': 'easy'},
      steady: {'distance_m': mpKm * 1000, 'pace_sec_per_km': p.marathon},
      cooldown: {'distance_m': 1500, 'pace': 'easy'},
    ),
    notes: '$mpKm km @ goal marathon pace.',
  );
}

List<GeneratedWorkout> _limitToDays(List<GeneratedWorkout> ws, int days) {
  final activeCount = ws.where((w) => w.kind != WorkoutKind.rest).length;
  if (activeCount <= days) return ws;
  var remove = activeCount - days;
  // Drop auto-generated filler days (easy AND recovery — a short easy day is
  // emitted as recovery, which the old check missed, so a 4-day plan ran 6
  // days and stacked floored 3 km recoveries into an impossible week 1 —
  // new persona #23). Long runs + quality sessions are preserved.
  return [
    for (final w in ws)
      if (remove > 0 &&
          (w.kind == WorkoutKind.easy || w.kind == WorkoutKind.recovery))
        (() {
          remove--;
          return GeneratedWorkout(
            scheduledDate: w.scheduledDate,
            kind: WorkoutKind.rest,
          );
        })()
      else
        w
  ];
}

extension on GeneratedWorkout {
  GeneratedWorkout _withDate(DateTime date) => GeneratedWorkout(
        scheduledDate: date,
        kind: kind,
        targetDistanceM: targetDistanceM,
        targetDurationSeconds: targetDurationSeconds,
        targetPaceSecPerKm: targetPaceSecPerKm,
        targetPaceToleranceSec: targetPaceToleranceSec,
        structure: structure,
        notes: notes,
      );
}

// ─────────────────────── Formatters ───────────────────────

String fmtPace(int? secPerKm) {
  if (secPerKm == null || secPerKm <= 0) return '—';
  // Honour the user's active unit pref. The stored value is always
  // sec/km (DB shape is unit-agnostic); convert to sec/mi at render
  // time when the user is in imperial mode.
  final unit = activeDistanceUnit;
  if (unit == DistanceUnit.mi) {
    const metresPerMile = 1609.344;
    final secPerMi = (secPerKm * (metresPerMile / 1000)).round();
    final m = secPerMi ~/ 60;
    final s = (secPerMi % 60).toString().padLeft(2, '0');
    return '$m:$s/mi';
  }
  final m = secPerKm ~/ 60;
  final s = (secPerKm % 60).toString().padLeft(2, '0');
  return '$m:$s/km';
}

String fmtKm(num? metres, [int digits = 1]) {
  if (metres == null) return '—';
  // Honour the user's active unit pref. Function name kept as
  // `fmtKm` (legacy from before the unit-aware sweep) — the
  // implementation now reads activeDistanceUnit so a mi-mode user
  // sees "5.0 mi" instead of "5.0 km".
  final unit = activeDistanceUnit;
  final tag = activeLocaleTag;
  if (unit == DistanceUnit.mi) {
    const metresPerMile = 1609.344;
    return '${formatFixed(metres / metresPerMile, digits, tag)} mi';
  }
  return '${formatFixed(metres / 1000, digits, tag)} km';
}

String fmtHms(int? sec) {
  if (sec == null || sec <= 0) return '—';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) {
  final parts = s.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}
