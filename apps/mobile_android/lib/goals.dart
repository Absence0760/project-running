import 'package:core_models/core_models.dart';

/// How wide a net the goal covers.
enum GoalPeriod { week, month }

/// A metric a [RunGoal] can track. A single goal can have any subset of
/// these active — the dashboard card shows one progress row per active
/// target, so "20 km, 5 runs, 5:00/km average" is a single goal with three
/// targets, not three separate goals.
enum GoalTargetKind { distance, time, avgPace, runCount }

/// Human-readable label used in the editor and dashboard card.
String goalKindLabel(GoalTargetKind kind) {
  return switch (kind) {
    GoalTargetKind.distance => 'Distance',
    GoalTargetKind.time => 'Time',
    GoalTargetKind.avgPace => 'Avg pace',
    GoalTargetKind.runCount => 'Runs',
  };
}

/// A user-defined training goal. One goal holds the period plus zero or
/// more concrete targets (distance / time / avg pace / run count). Stored
/// locally in [Preferences]; never round-tripped to Supabase.
class RunGoal {
  final String id;
  final GoalPeriod period;

  /// Optional display name. Null means "auto-label from targets" — see
  /// [displayTitle]. Exists so a user with two goals in the same period
  /// can tell them apart ("Base miles" vs "Speed work").
  final String? title;

  final double? distanceMetres;
  final double? timeSeconds;
  final double? avgPaceSecPerKm;
  final double? runCount;

  const RunGoal({
    required this.id,
    required this.period,
    this.title,
    this.distanceMetres,
    this.timeSeconds,
    this.avgPaceSecPerKm,
    this.runCount,
  });

  /// The target kinds on this goal, in display order.
  List<GoalTargetKind> get activeKinds => [
        if (distanceMetres != null) GoalTargetKind.distance,
        if (timeSeconds != null) GoalTargetKind.time,
        if (avgPaceSecPerKm != null) GoalTargetKind.avgPace,
        if (runCount != null) GoalTargetKind.runCount,
      ];

  bool get isEmpty => activeKinds.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'period': period.name,
        if (title != null && title!.isNotEmpty) 'title': title,
        if (distanceMetres != null) 'distance_m': distanceMetres,
        if (timeSeconds != null) 'time_s': timeSeconds,
        if (avgPaceSecPerKm != null) 'pace_s_per_km': avgPaceSecPerKm,
        if (runCount != null) 'run_count': runCount,
      };

  factory RunGoal.fromJson(Map<String, dynamic> json) {
    final period = GoalPeriod.values.firstWhere(
      (p) => p.name == json['period'],
      orElse: () => GoalPeriod.week,
    );

    // Data migration: the first goals build used a single-target shape
    // `{type, period, target}`. Detect it by the presence of 'type' and
    // splat the value into the matching optional field. The next
    // [_persistGoals] writes the new shape back out, so this branch only
    // fires on the upgrade boot.
    if (json.containsKey('type')) {
      final type = json['type'] as String;
      final target = (json['target'] as num).toDouble();
      return RunGoal(
        id: json['id'] as String,
        period: period,
        distanceMetres: type == 'distance' ? target : null,
        timeSeconds: type == 'time' ? target : null,
        avgPaceSecPerKm: type == 'avgPace' ? target : null,
        runCount: type == 'runCount' ? target : null,
      );
    }

    final rawTitle = json['title'] as String?;
    return RunGoal(
      id: json['id'] as String,
      period: period,
      title: (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : null,
      distanceMetres: (json['distance_m'] as num?)?.toDouble(),
      timeSeconds: (json['time_s'] as num?)?.toDouble(),
      avgPaceSecPerKm: (json['pace_s_per_km'] as num?)?.toDouble(),
      runCount: (json['run_count'] as num?)?.toDouble(),
    );
  }
}

/// Generate an opaque id for a new goal. Not globally unique — fine for a
/// local-only list where collisions at microsecond resolution are impossible
/// in practice.
String newGoalId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// Progress on a single target within a goal.
class TargetProgress {
  final GoalTargetKind kind;

  /// Current value in canonical units (metres / seconds / sec-per-km / count).
  final double current;

  /// Copy of the target in the same canonical units.
  final double target;

  /// Progress fraction in `[0, 1]`. For lower-is-better targets (avg pace)
  /// this is `target / current` clamped.
  final double percent;
  final bool complete;
  final String feedback;

  const TargetProgress({
    required this.kind,
    required this.current,
    required this.target,
    required this.percent,
    required this.complete,
    required this.feedback,
  });
}

/// Snapshot of how a goal is tracking. One [TargetProgress] per active
/// target on the [RunGoal], plus an aggregate [overallPercent] and a
/// single [complete] flag that's true only when every target is met.
class GoalProgress {
  final List<TargetProgress> targets;
  final double overallPercent;
  final bool complete;
  final int runCount;

  const GoalProgress({
    required this.targets,
    required this.overallPercent,
    required this.complete,
    required this.runCount,
  });
}

/// Pure evaluator: given a goal and the full run list, compute progress
/// for every active target.
GoalProgress evaluateGoal(RunGoal goal, List<Run> runs, DateTime now) {
  final periodStart = goalPeriodStart(goal.period, now);
  final periodEnd = goalPeriodEnd(goal.period, now);

  final inPeriod = runs
      .where((r) =>
          !r.startedAt.isBefore(periodStart) &&
          r.startedAt.isBefore(periodEnd))
      .toList();

  // Pace calculations exclude cycling — a distance-weighted average would
  // otherwise be dominated by a single long bike ride.
  final paceEligible = inPeriod
      .where((r) => r.metadata?['activity_type'] != 'cycle')
      .toList();

  final totalMetres = inPeriod.fold<double>(0, (s, r) => s + r.distanceMetres);
  final totalSeconds =
      inPeriod.fold<int>(0, (s, r) => s + r.duration.inSeconds);

  final targets = <TargetProgress>[];

  if (goal.distanceMetres != null) {
    targets.add(_evalCumulative(
      kind: GoalTargetKind.distance,
      target: goal.distanceMetres!,
      current: totalMetres,
      runsInPeriod: inPeriod.length,
      now: now,
      periodStart: periodStart,
      periodEnd: periodEnd,
      format: (m) => '${(m / 1000).toStringAsFixed(1)} km',
    ));
  }

  if (goal.timeSeconds != null) {
    targets.add(_evalCumulative(
      kind: GoalTargetKind.time,
      target: goal.timeSeconds!,
      current: totalSeconds.toDouble(),
      runsInPeriod: inPeriod.length,
      now: now,
      periodStart: periodStart,
      periodEnd: periodEnd,
      format: _formatSecondsCoarse,
    ));
  }

  if (goal.avgPaceSecPerKm != null) {
    final paceMetres =
        paceEligible.fold<double>(0, (s, r) => s + r.distanceMetres);
    final paceSecondsSum =
        paceEligible.fold<int>(0, (s, r) => s + r.duration.inSeconds);
    final current =
        paceMetres > 10 ? paceSecondsSum / (paceMetres / 1000) : 0.0;
    targets.add(_evalPace(
      target: goal.avgPaceSecPerKm!,
      current: current,
      runningRuns: paceEligible.length,
    ));
  }

  if (goal.runCount != null) {
    targets.add(_evalRunCount(
      target: goal.runCount!,
      current: inPeriod.length.toDouble(),
    ));
  }

  final overall = targets.isEmpty
      ? 0.0
      : targets.map((t) => t.percent).reduce((a, b) => a + b) / targets.length;
  final complete =
      targets.isNotEmpty && targets.every((t) => t.complete);

  return GoalProgress(
    targets: targets,
    overallPercent: overall,
    complete: complete,
    runCount: inPeriod.length,
  );
}

/// Progress for a higher-is-better cumulative target (distance, time).
TargetProgress _evalCumulative({
  required GoalTargetKind kind,
  required double target,
  required double current,
  required int runsInPeriod,
  required DateTime now,
  required DateTime periodStart,
  required DateTime periodEnd,
  required String Function(double) format,
}) {
  final percent = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
  final complete = target > 0 && current >= target;

  String feedback;
  if (runsInPeriod == 0) {
    feedback = 'Log a run to start tracking';
  } else if (complete) {
    feedback = 'Goal reached';
  } else {
    final totalSec = periodEnd.difference(periodStart).inSeconds.toDouble();
    final elapsedSec =
        now.difference(periodStart).inSeconds.clamp(0, totalSec.toInt());
    final expected = totalSec > 0 ? target * (elapsedSec / totalSec) : 0.0;
    final delta = current - expected;
    feedback = delta > 0
        ? '${format(delta)} ahead of pace'
        : '${format(target - current)} to go';
  }

  return TargetProgress(
    kind: kind,
    current: current,
    target: target,
    percent: percent,
    complete: complete,
    feedback: feedback,
  );
}

TargetProgress _evalPace({
  required double target,
  required double current,
  required int runningRuns,
}) {
  double percent;
  bool complete;
  String feedback;

  if (current <= 0) {
    percent = 0;
    complete = false;
    feedback = runningRuns == 0
        ? 'Log a running activity to track pace'
        : 'Log a run to start tracking';
  } else if (current <= target) {
    percent = 1.0;
    complete = true;
    feedback = 'Goal reached';
  } else {
    percent = (target / current).clamp(0.0, 1.0);
    complete = false;
    final delta = current - target;
    if (delta.abs() < 1) {
      feedback = 'On target';
    } else {
      feedback = '${delta.abs().round()}s off target';
    }
  }

  return TargetProgress(
    kind: GoalTargetKind.avgPace,
    current: current,
    target: target,
    percent: percent,
    complete: complete,
    feedback: feedback,
  );
}

TargetProgress _evalRunCount({
  required double target,
  required double current,
}) {
  final percent = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
  final complete = target > 0 && current >= target;

  String feedback;
  if (complete) {
    feedback = 'Goal reached';
  } else if (current == 0) {
    feedback = 'Log a run to start tracking';
  } else {
    final remaining = (target - current).ceil();
    feedback = '$remaining to go';
  }

  return TargetProgress(
    kind: GoalTargetKind.runCount,
    current: current,
    target: target,
    percent: percent,
    complete: complete,
    feedback: feedback,
  );
}

String _formatSecondsCoarse(double seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin >= 60) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
  return '${totalMin}m';
}

/// Monday 00:00 local time of the ISO week containing [now]. The single
/// source of truth for "this week" across goals, the history filter, and
/// the dashboard summary cards — keeping them in lockstep so a future
/// change of convention (e.g. Sunday-start) is a one-file edit.
DateTime weekStartLocal(DateTime now) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final daysFromMonday = (now.weekday - DateTime.monday) % 7;
  return startOfToday.subtract(Duration(days: daysFromMonday));
}

/// Start of the period containing [now], inclusive, in local time.
DateTime goalPeriodStart(GoalPeriod period, DateTime now) {
  switch (period) {
    case GoalPeriod.week:
      return weekStartLocal(now);
    case GoalPeriod.month:
      return DateTime(now.year, now.month, 1);
  }
}

/// Exclusive end of the period containing [now], in local time.
DateTime goalPeriodEnd(GoalPeriod period, DateTime now) {
  switch (period) {
    case GoalPeriod.week:
      return goalPeriodStart(period, now).add(const Duration(days: 7));
    case GoalPeriod.month:
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final year = now.month == 12 ? now.year + 1 : now.year;
      return DateTime(year, nextMonth, 1);
  }
}
