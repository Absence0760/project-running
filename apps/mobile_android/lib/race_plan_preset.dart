/// Derive a training-plan preset from a race on the calendar, so "train for
/// this race" lands on a plan whose final race week contains race day.
///
/// Two constraints drive every number here:
///
///  - `generatePlan` hard-anchors day 0 of the start week to the Sunday long
///    run, so a derived start date must be a Sunday or every day-role shifts.
///  - The generated plan's last week is the `race` week, spanning
///    `[start + (weeks-1)*7, start + weeks*7 - 1]`. Anchoring that week's
///    Sunday to the Sunday on or before race day puts race day inside it for
///    any weekday the race falls on.
///
/// Dates are compared as whole UTC epoch-days rather than by elapsed time: a
/// span crossing a DST transition is 167 or 169 hours, which truncates a day
/// short and would shift the anchor by a week.
///
/// Dart twin of `apps/web/src/lib/training/race_plan_preset.ts` — keep the
/// arithmetic, tolerances, refusals, and test counts in lockstep. The surfaces
/// are `RaceCalendarCard.svelte` → `/plans/new` there and the races screen's
/// "train for this race" action → `PlanNewScreen` here.
library;

import 'dart:math' as math;

import 'training.dart';

const int _dayMs = 86400000;

/// Shortest plan the preset will propose. Mirrors the wizard's own four-week
/// floor — a shorter build isn't a plan, it's a taper.
const int kRacePlanMinWeeks = 4;

/// How far a race's advertised distance may sit from a standard rung and
/// still be treated as that event. Courses are certified to the metre but
/// listings round ("21.1 km"), so an exact match is too strict.
const double kRacePlanDistanceTolerance = 0.02;

enum RacePlanRefusal {
  /// Race day has been and gone (or is today) — nothing left to train for.
  past,

  /// Fewer than [kRacePlanMinWeeks] whole weeks remain before race week.
  tooSoon,

  /// The race date isn't a usable `yyyy-mm-dd`.
  invalid,
}

class RacePlanPreset {
  /// The standard event the race distance matches, or null when it matches
  /// none. The wizard has no custom-distance input, so claiming the nearest
  /// rung for (say) a 50k would silently train the runner for a marathon;
  /// null leaves the goal on the wizard's own default and still presets the
  /// dates, which is the half of the answer we can stand behind.
  final GoalEvent? goalEvent;

  /// Total plan weeks, >= [kRacePlanMinWeeks].
  final int weeks;

  /// ISO `yyyy-mm-dd`, always a Sunday, never before today.
  final String startDate;

  const RacePlanPreset({
    required this.goalEvent,
    required this.weeks,
    required this.startDate,
  });
}

/// Web models this as a discriminated union; Dart carries the two arms on one
/// small class, the same idiomatic shape difference `password_change` records.
class RacePlanPresetResult {
  final RacePlanPreset? preset;
  final RacePlanRefusal? reason;

  const RacePlanPresetResult.ok(RacePlanPreset this.preset) : reason = null;
  const RacePlanPresetResult.refused(RacePlanRefusal this.reason)
      : preset = null;

  bool get ok => preset != null;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Whole days since the epoch for an ISO date, or null when unparseable.
/// UTC-based so the count is immune to DST and to the caller's offset; both
/// inputs go through the same function, so only their difference matters.
int? _epochDay(String iso) {
  if (!_isoDate.hasMatch(iso)) return null;
  final parts = iso.split('-').map(int.parse).toList();
  final utc = DateTime.utc(parts[0], parts[1], parts[2]);
  // Round-trip guards an out-of-range component ("2026-02-31" rolls over).
  if (utc.year != parts[0] || utc.month != parts[1] || utc.day != parts[2]) {
    return null;
  }
  return utc.millisecondsSinceEpoch ~/ _dayMs;
}

String _isoFromEpochDay(int day) {
  final d = DateTime.fromMillisecondsSinceEpoch(day * _dayMs, isUtc: true);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// Day of week for an epoch day, 0 = Sunday. Epoch day 0 (1970-01-01) was a
/// Thursday, hence the +4.
int _dayOfWeek(int day) => ((day + 4) % 7 + 7) % 7;

/// The standard goal event a race distance represents, or null when it sits
/// outside [kRacePlanDistanceTolerance] of every rung.
GoalEvent? goalEventForDistance(num? distanceM) {
  final d = distanceM?.toDouble();
  if (d == null || !d.isFinite || d <= 0) return null;
  for (final entry in kGoalDistancesM.entries) {
    if ((d - entry.value).abs() / entry.value <= kRacePlanDistanceTolerance) {
      return entry.key;
    }
  }
  return null;
}

/// Propose the plan shape that peaks on a race.
///
/// `weeks` is capped at the goal's own default rather than filling every week
/// between now and race day: a marathon 30 weeks out wants the standard
/// 16-week build starting in 14 weeks, not a 30-week grind.
RacePlanPresetResult racePlanPreset({
  required String raceDateIso,
  required String todayIso,
  num? distanceM,
}) {
  final raceDay = _epochDay(raceDateIso);
  final today = _epochDay(todayIso);
  if (raceDay == null || today == null) {
    return const RacePlanPresetResult.refused(RacePlanRefusal.invalid);
  }
  if (raceDay <= today) {
    return const RacePlanPresetResult.refused(RacePlanRefusal.past);
  }

  final goalEvent = goalEventForDistance(distanceM);

  // The race week is the calendar week (Sunday-based) race day falls in.
  final raceWeekStart = raceDay - _dayOfWeek(raceDay);
  // Earliest legal start: the Sunday on or after today. Starting today is
  // fine — the wizard only rejects a start date strictly in the past.
  final firstStart = today + (7 - _dayOfWeek(today)) % 7;

  final available = (raceWeekStart - firstStart) ~/ 7 + 1;
  if (available < kRacePlanMinWeeks) {
    return const RacePlanPresetResult.refused(RacePlanRefusal.tooSoon);
  }

  final weeks =
      math.min(available, defaultPlanWeeks(goalEvent ?? GoalEvent.custom));
  return RacePlanPresetResult.ok(RacePlanPreset(
    goalEvent: goalEvent,
    weeks: weeks,
    startDate: _isoFromEpochDay(raceWeekStart - (weeks - 1) * 7),
  ));
}
