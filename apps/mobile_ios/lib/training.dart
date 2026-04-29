// Training engine — Dart port of apps/web/src/lib/training.ts.
//
// Must produce byte-identical paces + phase labels for the same inputs. If
// you change a number here, change it in training.ts and re-run both test
// suites. See docs/training.md.

import 'dart:math';

enum GoalEvent { distance5k, distance10k, distanceHalf, distanceFull, custom }

enum WorkoutKind {
  easy,
  long,
  recovery,
  tempo,
  interval,
  marathonPace,
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
      WorkoutKind.race => 'race',
      WorkoutKind.rest => 'rest',
    };

String workoutKindLabel(WorkoutKind k) => switch (k) {
      WorkoutKind.easy => 'Easy',
      WorkoutKind.long => 'Long run',
      WorkoutKind.recovery => 'Recovery',
      WorkoutKind.tempo => 'Tempo',
      WorkoutKind.interval => 'Intervals',
      WorkoutKind.marathonPace => 'Marathon pace',
      WorkoutKind.race => 'Race',
      WorkoutKind.rest => 'Rest',
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

String planPhaseLabel(PlanPhase p) => switch (p) {
      PlanPhase.base => 'Base',
      PlanPhase.build => 'Build',
      PlanPhase.peak => 'Peak',
      PlanPhase.taper => 'Taper',
      PlanPhase.race => 'Race week',
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

TrainingPaces pacesFromGoalPace(double goalPaceSecPerKm) => TrainingPaces(
      easy: (goalPaceSecPerKm * 1.22).round(),
      marathon: (goalPaceSecPerKm * 1.06).round(),
      tempo: (goalPaceSecPerKm * 0.97).round(),
      interval: (goalPaceSecPerKm * 0.9).round(),
      repetition: (goalPaceSecPerKm * 0.85).round(),
    );

TrainingPaces resolveTrainingPaces({
  required double goalDistanceM,
  int? goalTimeSec,
  int? recent5kSec,
}) {
  double goalPace;
  if (recent5kSec != null) {
    final predicted = riegelPredict(5000, recent5kSec, goalDistanceM);
    goalPace = predicted / (goalDistanceM / 1000);
  } else if (goalTimeSec != null) {
    goalPace = goalTimeSec / (goalDistanceM / 1000);
  } else {
    goalPace = 600;
  }
  return pacesFromGoalPace(goalPace);
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

  const GeneratedPlan({
    required this.weeks,
    required this.paces,
    required this.vdot,
    required this.endDate,
    required this.goalDistanceM,
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

  const GeneratePlanInput({
    required this.goalEvent,
    this.goalDistanceM,
    this.goalTimeSec,
    this.recent5kSec,
    required this.startDate,
    required this.daysPerWeek,
    this.weeks,
  });
}

GeneratedPlan generatePlan(GeneratePlanInput input) {
  final goalDistance = input.goalEvent == GoalEvent.custom
      ? input.goalDistanceM!
      : kGoalDistancesM[input.goalEvent]!;
  final totalWeeks = input.weeks ?? defaultPlanWeeks(input.goalEvent);
  final paces = resolveTrainingPaces(
    goalDistanceM: goalDistance,
    goalTimeSec: input.goalTimeSec,
    recent5kSec: input.recent5kSec,
  );
  double? vdot;
  if (input.recent5kSec != null) {
    vdot = vdotFromRace(5000, input.recent5kSec!);
  } else if (input.goalTimeSec != null) {
    vdot = vdotFromRace(goalDistance, input.goalTimeSec!);
  }

  final weeks = <GeneratedWeek>[];
  for (var i = 0; i < totalWeeks; i++) {
    final phase = phaseFor(i, totalWeeks);
    final peakKm = _peakVolumeKm(goalDistance, input.daysPerWeek);
    final frac = _mileageFraction(i, totalWeeks, phase);
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
    );
    weeks.add(GeneratedWeek(
      weekIndex: i,
      phase: phase,
      targetVolumeM: weeklyKm * 1000.0,
      notes: _weekNote(phase, i, totalWeeks),
      workouts: workouts,
    ));
  }

  return GeneratedPlan(
    weeks: weeks,
    paces: paces,
    vdot: vdot,
    endDate: input.startDate.add(Duration(days: totalWeeks * 7 - 1)),
    goalDistanceM: goalDistance,
  );
}

double _peakVolumeKm(double goalDistanceM, int daysPerWeek) {
  final baseMul = goalDistanceM <= 10000
      ? 5.0
      : goalDistanceM <= 21100
          ? 2.5
          : 1.8;
  final dayFactor = 0.7 + (daysPerWeek - 3) * 0.1;
  return ((goalDistanceM / 1000) * baseMul * dayFactor).roundToDouble();
}

double _mileageFraction(int i, int total, PlanPhase phase) {
  if (phase == PlanPhase.race) return 0.35;
  if (phase == PlanPhase.taper) return 0.55;
  final ramp = 0.6 + (0.4 * i) / max(1, total - 3);
  final stepBack = i > 0 && i % 4 == 3 ? 0.82 : 1;
  return min(1.0, ramp * stepBack);
}

String? _weekNote(PlanPhase phase, int i, int total) {
  if (phase == PlanPhase.race) return 'Race week — trust the work.';
  if (phase == PlanPhase.taper) return 'Taper — volume down, sharpness stays.';
  if (i > 0 && i % 4 == 3) return 'Step-back week — recover before the next build.';
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
}) {
  // Same allocation as web: Mon rest, Sun long, Tue qualityA, Thu qualityB.
  const restDow = 1, longDow = 0, qaDow = 2, qbDow = 4;
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
  final daysUsed = <int>{longDow, restDow};
  if (daysPerWeek >= 4) daysUsed.add(qaDow);
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
    if (dow == qaDow && daysPerWeek >= 4 && quality.a != null) {
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
    if (daysPerWeek >= 4) a = _tempo(placeholder, 6, paces);
  } else if (phase == PlanPhase.build) {
    if (daysPerWeek >= 4) a = _intervals(placeholder, paces);
    if (daysPerWeek >= 5) b = _tempo(placeholder, 7, paces);
  } else if (phase == PlanPhase.peak) {
    if (daysPerWeek >= 4) a = _intervals(placeholder, paces);
    if (daysPerWeek >= 5) b = _marathonPace(placeholder, paces, goalDistanceM);
  } else if (phase == PlanPhase.taper) {
    if (daysPerWeek >= 4) a = _tempo(placeholder, 4, paces);
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
  return [
    for (final w in ws)
      if (remove > 0 && w.kind == WorkoutKind.easy)
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
  final m = secPerKm ~/ 60;
  final s = (secPerKm % 60).toString().padLeft(2, '0');
  return '$m:$s/km';
}

String fmtKm(num? metres, [int digits = 1]) {
  if (metres == null) return '—';
  return '${(metres / 1000).toStringAsFixed(digits)} km';
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
