/// Does the plan the wizard just generated match the training the runner is
/// actually doing?
///
/// `generatePlan` sizes every week off the goal race, the training days, and a
/// fitness anchor — it never looks at the runner's history. So a runner
/// averaging 20 km a week can generate a marathon plan whose first week asks
/// for 37 km and nothing says a word. That opening step is the classic
/// training injury, and the app already owns a tested policy for exactly this
/// shape of question: the coach roster's acute:chronic workload ratio. A plan
/// week IS an acute (7-day) load; the runner's trailing 28-day average IS the
/// chronic base. So the bands come from `coach_load` rather than from new
/// numbers invented here, and the two surfaces cannot drift.
///
/// Dart twin of `apps/web/src/lib/training/plan_ramp.ts` — keep in lockstep
/// (algorithm, edge cases, outputs, test counts).
library;

import 'dart:math' as math;

import 'coach_load.dart';

const int _dayMs = 86400000;

/// How many trailing 7-day windows make up the chronic base. Four weeks is
/// the ACWR convention `coach_load` already uses for its chronic average.
const int kChronicWindowWeeks = 4;

/// How many of those windows must carry at least one run before the check
/// will say anything. ACWR needs ~28 days of *consistent* history to mean
/// anything; below that the ratio is arithmetic on noise. A runner with one
/// 3 km jog in a month otherwise divides a beginner plan's opening week by
/// 0.75 km and gets told their C25K is a high injury risk.
const int kMinActiveWeeks = 3;

class RunForVolume {
  /// The raw `runs.started_at` timestamp, unparsed — the same shape the row
  /// arrives in, so [volumeSample] owns the one parse and a malformed row is
  /// dropped there rather than reaching the arithmetic.
  final String startedAt;
  final double? distanceM;
  final String? activityType;

  /// Carried by every `runs` row and deliberately NOT filtered on, unlike the
  /// coach roster, which excludes DNFs. Declared here so its absence from the
  /// filter below reads as the decision it is rather than an oversight — see
  /// decisions § 592. A DNF is only ever a post-hoc flag on an already-recorded
  /// run; nothing rewrites `distance_m` when it is set, so the distance is what
  /// the runner actually covered before stopping, and legs do not un-absorb it.
  final bool? isDnf;

  const RunForVolume({
    required this.startedAt,
    required this.distanceM,
    this.activityType,
    this.isDnf,
  });
}

class RecentVolume {
  /// Mean weekly running distance (metres) across the chronic window.
  final double weeklyM;

  /// Running distance (metres) in the most recent 7-day window alone — the
  /// acute half of an ACWR pair whose chronic half is [weeklyM]. Same
  /// traversal and same rules, so the two can never be reduced from different
  /// run sets.
  final double acuteM;

  /// How many of the trailing windows carried at least one counted run.
  final int activeWeeks;

  const RecentVolume({
    required this.weeklyM,
    required this.acuteM,
    required this.activeWeeks,
  });
}

class VolumeSample {
  final int startedMs;
  final double distanceM;
  const VolumeSample({required this.startedMs, required this.distanceM});
}

/// The one definition of "this row is running volume", and the countable
/// numbers it yields. Cycling is excluded (a bike ride is not running volume —
/// the same rule `goals` and `fitness` apply); everything else that carries
/// distance counts, including treadmill runs, which are real load even though
/// they are barred from anchoring fitness.
///
/// Extracted rather than inlined because web's `comeback.ts` reduces the SAME
/// runs over a different window: two copies of the filter would let a runner's
/// pre-break base and their current week come from different run sets, which
/// is the one way a comparison between the two can silently lie.
VolumeSample? volumeSample(RunForVolume run) {
  if (run.activityType == 'cycle') return null;
  final distanceM = run.distanceM;
  if (distanceM == null || !distanceM.isFinite || distanceM <= 0) return null;
  final started = DateTime.tryParse(run.startedAt);
  if (started == null) return null;
  return VolumeSample(
    startedMs: started.millisecondsSinceEpoch,
    distanceM: distanceM,
  );
}

/// The runner's chronic weekly running volume from their recent runs.
///
/// Windows are rolling 7-day buckets counted back from [nowMs], not calendar
/// weeks: a calendar week straddling today is only partly elapsed, so it
/// under-reports volume and would drag the average down for no reason.
RecentVolume recentRunVolume(List<RunForVolume> runs, int nowMs) {
  var totalM = 0.0;
  var acuteM = 0.0;
  final active = <int>{};
  for (final r in runs) {
    final sample = volumeSample(r);
    if (sample == null) continue;
    // A device whose clock runs ahead stamps a just-finished run in the
    // future; that is this week's load, not a row to drop.
    final age = math.max(0, nowMs - sample.startedMs);
    final week = age ~/ (7 * _dayMs);
    if (week >= kChronicWindowWeeks) continue;
    totalM += sample.distanceM;
    if (week == 0) acuteM += sample.distanceM;
    active.add(week);
  }
  return RecentVolume(
    weeklyM: totalM / kChronicWindowWeeks,
    acuteM: acuteM,
    activeWeeks: active.length,
  );
}

enum PlanRampVerdict { unknown, under, matched, elevated, high }

class PlanRampCheck {
  final PlanRampVerdict verdict;

  /// Opening week / chronic weekly average, and peak week / the same. Both
  /// are 0 when the verdict is unknown, so a caller can never render a ratio
  /// the check refused to stand behind.
  final double openingRatio;
  final double peakRatio;
  final double openingWeekM;
  final double peakWeekM;
  final double recentWeeklyM;
  final int activeWeeks;

  const PlanRampCheck({
    required this.verdict,
    required this.openingRatio,
    required this.peakRatio,
    required this.openingWeekM,
    required this.peakWeekM,
    required this.recentWeeklyM,
    required this.activeWeeks,
  });
}

/// One generated week reduced to what the ramp check grades on.
class PlanWeekVolume {
  final int weekIndex;
  final double targetVolumeM;
  const PlanWeekVolume({required this.weekIndex, required this.targetVolumeM});
}

/// The plan's opening ask, in metres. Taken by lowest
/// [PlanWeekVolume.weekIndex] rather than by list position — the generator
/// emits weeks in order but a pasted or re-read plan carries no such
/// guarantee.
double openingWeekVolumeM(List<PlanWeekVolume> weeks) {
  int? openingIndex;
  var openingVolume = 0.0;
  for (final w in weeks) {
    if (!w.targetVolumeM.isFinite) continue;
    if (openingIndex == null || w.weekIndex < openingIndex) {
      openingIndex = w.weekIndex;
      openingVolume = w.targetVolumeM;
    }
  }
  return openingIndex == null ? 0 : openingVolume;
}

/// The plan's heaviest week, in metres — what it is ultimately asking the
/// runner to absorb.
double peakWeekVolumeM(List<PlanWeekVolume> weeks) {
  var peak = 0.0;
  for (final w in weeks) {
    if (!w.targetVolumeM.isFinite) continue;
    if (w.targetVolumeM > peak) peak = w.targetVolumeM;
  }
  return peak;
}

/// Grade the plan against the runner's chronic base.
///
/// The two directions are not the same question and are deliberately not
/// graded off the same week. **Too much** is about the first step, so it
/// grades the opening week — that is where a plan injures someone. **Too
/// little** is about the whole plan, so it grades the PEAK week: every
/// well-formed plan opens well below its own peak (the generator's week 0 is
/// 0.6x), so grading "under" off the opening week would tell a runner already
/// training at the plan's peak volume that the plan is too light for them,
/// which is exactly backwards.
///
/// Safety wins the tie: an opening week that is too big is reported even if
/// the peak is also modest.
///
/// Fail-closed in both directions: too little history, or a plan with no
/// volume to grade, returns [PlanRampVerdict.unknown] — the caller shows
/// nothing rather than guessing, and in particular never reports a reassuring
/// "matched" it has no evidence for.
///
/// Only the chronic half of [recent] is consumed: the plan's own opening week
/// is the acute term, so `acuteM` (what the runner has actually just done)
/// would be the wrong numerator for a question about a hypothetical plan.
PlanRampCheck planRampCheck(
  double openingWeekM,
  double peakWeekM,
  RecentVolume recent,
) {
  PlanRampCheck build(
    PlanRampVerdict verdict,
    double openingRatio,
    double peakRatio,
  ) {
    return PlanRampCheck(
      verdict: verdict,
      openingRatio: openingRatio,
      peakRatio: peakRatio,
      openingWeekM: openingWeekM,
      peakWeekM: peakWeekM,
      recentWeeklyM: recent.weeklyM,
      activeWeeks: recent.activeWeeks,
    );
  }

  final ungraded = build(PlanRampVerdict.unknown, 0, 0);
  if (!openingWeekM.isFinite || openingWeekM <= 0) return ungraded;
  if (!peakWeekM.isFinite || peakWeekM <= 0) return ungraded;
  if (recent.activeWeeks < kMinActiveWeeks) return ungraded;
  final openingBand = injuryRiskBand(openingWeekM, recent.weeklyM);
  if (openingBand == InjuryRiskBand.insufficient) return ungraded;
  final openingRatio = acwr(openingWeekM, recent.weeklyM);
  final peakRatio = acwr(peakWeekM, recent.weeklyM);
  if (openingBand == InjuryRiskBand.elevated) {
    return build(PlanRampVerdict.elevated, openingRatio, peakRatio);
  }
  if (openingBand == InjuryRiskBand.high) {
    return build(PlanRampVerdict.high, openingRatio, peakRatio);
  }
  if (injuryRiskBand(peakWeekM, recent.weeklyM) == InjuryRiskBand.low) {
    return build(PlanRampVerdict.under, openingRatio, peakRatio);
  }
  return build(PlanRampVerdict.matched, openingRatio, peakRatio);
}

/// Whether the wizard should say anything at all.
///
/// Silence on `matched` is the point: a note that renders on every plan is
/// noise a runner learns to skip, and the check only earns its place when it
/// has something to report. `under` is an optimisation nudge rather than a
/// safety one, so it is withheld from a beginner walk-run plan — that runner
/// deliberately asked for the gentlest possible on-ramp and does not need to
/// be told it is gentle.
bool shouldSurfaceRampNote(
  PlanRampCheck check, {
  bool beginnerWalkRun = false,
}) {
  if (check.verdict == PlanRampVerdict.unknown ||
      check.verdict == PlanRampVerdict.matched) {
    return false;
  }
  if (check.verdict == PlanRampVerdict.under && beginnerWalkRun) return false;
  return true;
}
