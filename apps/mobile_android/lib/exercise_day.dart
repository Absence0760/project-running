import 'package:api_client/api_client.dart';

import 'exercise_calories.dart';

/// Split the `activities` view rows falling inside `[start, end)` local time
/// into the inputs the exercise-calorie and hydration add-ons consume.
///
/// Mobile-only glue, and deliberately not a parity pair: web resolves the same
/// day by pushing the window down to PostgREST as `fetchRuns` /
/// `fetchGymWorkouts` bounds and feeding the two results straight into
/// `exerciseCaloriesForDay`. This bucketing exists only because mobile reads
/// one merged view and narrows it client-side, so there is no TS twin for it
/// to drift from.
///
/// Match on [ActivityRow.kindRun] / [ActivityRow.kindLift], never on a bare
/// string: the view's gym branch emits `lift`, so a filter written against
/// `'gym'` silently matched nothing and every strength session contributed
/// zero calories and zero hydration minutes.
///
/// Lives here rather than in either consuming screen: `nutrition_screen` and
/// `nutrition_targets_screen` both need it, and a pure reduction parked in one
/// of them makes a widget file a library for the other (decisions § 695).
({List<RunForCalories> runs, List<GymSessionForCalories> gym, double seconds})
    exerciseInputsForDay(
  List<ActivityRow> activities,
  DateTime start,
  DateTime end,
) {
  var seconds = 0.0;
  final runs = <RunForCalories>[];
  final gym = <GymSessionForCalories>[];
  for (final a in activities) {
    if (a.kind != ActivityRow.kindRun && a.kind != ActivityRow.kindLift) {
      continue;
    }
    final at = a.startedAt.toLocal();
    if (at.isBefore(start) || !at.isBefore(end)) continue;
    final durationS = (a.summary['duration_s'] as num?)?.toDouble();
    seconds += durationS ?? 0;
    if (a.kind == ActivityRow.kindRun) {
      runs.add(RunForCalories((a.summary['distance_m'] as num?)?.toDouble()));
    } else {
      gym.add(GymSessionForCalories(durationS));
    }
  }
  return (runs: runs, gym: gym, seconds: seconds);
}
