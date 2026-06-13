import 'dart:math' as math;

import 'package:core_models/core_models.dart';

import 'training_load.dart' show kLayoffResetDays;

/// Fitness metrics — VO2 max + training-load math.
///
/// Dart port of `apps/web/src/lib/fitness.ts`. Pure functions; inputs are
/// plain `Run` objects, outputs are scalars / small structs. No
/// Supabase or auth calls. Keep the formulas in sync with the web module
/// — the same numbers should appear on every surface.
///
/// Keep the formulas honest. These are well-known running-science
/// heuristics, not proprietary research:
///
/// - **VO2 max (Daniels' "%VO2max at race pace" curve):** derived from
///   a run's pace + duration. Behaves better at sub-maximal paces than
///   the raw Cooper 12-minute test.
/// - **Training stress score (TSS):** duration · intensity², where
///   intensity is current pace / threshold pace.
/// - **ATL / CTL / TSB:** standard exponentially-weighted moving
///   averages over daily TSS. 7-day ATL, 42-day CTL, TSB = CTL − ATL.

class FitnessSnapshot {
  final double? vdot;
  final double? vo2Max;
  final double? acuteLoad;
  final double? chronicLoad;
  final double? trainingStressBal;
  final int qualifyingRunCount;

  const FitnessSnapshot({
    required this.vdot,
    required this.vo2Max,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.trainingStressBal,
    required this.qualifyingRunCount,
  });
}

/// Minimum qualifying-run distance (metres) for fitness math. Lowered from
/// 3 km to 1.5 km so a comeback / new runner rebuilding at 1-2 km per outing
/// still gets a fitness + volume signal instead of an empty Fitness card
/// forever (persona round-5 runner-comeback). 1.5 km paired with the 5-min
/// duration floor below means a qualifying run is a sustained effort of at
/// least ~3:20/km — noisy 1 km all-out sprints (which would inflate the VDOT
/// ceiling, since [currentVdot] takes the max over runs) stay excluded, and a
/// true sprint is also caught by [vdotFromRun]'s own 1 km / 2 min gate. We
/// deliberately did NOT drop to 1 km: the gap between 1 and 1.5 km is where
/// short all-out efforts produce the most VDOT inflation. Mirrors fitness.ts.
const double kMinQualifyingDistanceM = 1500;

/// Qualifying runs for fitness math: an actual recording or reliable
/// import, distance >= kMinQualifyingDistanceM, duration >= 5 min. Indoor /
/// treadmill runs are excluded — belt-/estimate-derived distance must not feed
/// VDOT (#16).
List<Run> qualifyingRuns(Iterable<Run> runs) {
  return [
    for (final r in runs)
      if (r.distanceMetres >= kMinQualifyingDistanceM &&
          r.duration.inSeconds >= 300 &&
          r.metadata?['indoor'] != true &&
          (r.source == RunSource.app ||
              r.source == RunSource.watch ||
              r.source == RunSource.strava ||
              r.source == RunSource.garmin ||
              r.source == RunSource.healthkit ||
              r.source == RunSource.healthconnect))
        r,
  ];
}

/// Runner's VDOT from a single run. Inverts Daniels' "%VO2max at a
/// given race pace" tables:
///
///     VO2 demand (ml/kg/min) = -4.60 + 0.182258·v + 0.000104·v²
///     %VO2max = 0.8 + 0.1894393·exp(-0.012778·t) + 0.2989558·exp(-0.1932605·t)
///     VDOT    = VO2 demand / %VO2max
///
/// where v is velocity in m/min and t is duration in minutes.
double? vdotFromRun(double distanceM, int durationS) {
  if (distanceM < 1000 || durationS < 120) return null;
  final tMin = durationS / 60;
  final v = distanceM / tMin;
  final vo2Demand = -4.6 + 0.182258 * v + 0.000104 * v * v;
  final pctVo2Max = 0.8 +
      0.1894393 * math.exp(-0.012778 * tMin) +
      0.2989558 * math.exp(-0.1932605 * tMin);
  if (pctVo2Max <= 0) return null;
  final vdot = vo2Demand / pctVo2Max;
  if (!vdot.isFinite || vdot <= 0) return null;
  // Reject a physiologically impossible VDOT. The human ceiling is ~85
  // (elite marathoners sit around there); a value above this means corrupt
  // input — a GPS distance spike or a bad import. Since `currentVdot` takes
  // the MAX over a 90-day window, one such run would otherwise poison
  // threshold pace and every TSS for three months. Drop it rather than let
  // it set the ceiling. (The duration/distance floors guard the short-sprint
  // inflation case; this guards the fast-distance-glitch case.)
  if (vdot > 90) return null;
  return vdot;
}

/// Current VDOT — the best single qualifying run in the last ~90 days.
/// A runner's fitness ceiling is what their hardest recent run proved.
double? currentVdot(Iterable<Run> runs, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final cutoff = t.subtract(const Duration(days: 90));
  double? best;
  for (final r in qualifyingRuns(runs)) {
    if (r.startedAt.isBefore(cutoff)) continue;
    final v = vdotFromRun(r.distanceMetres, r.duration.inSeconds);
    if (v != null && (best == null || v > best)) best = v;
  }
  return best;
}

/// Cooper-style VO2 max — same value as VDOT at these scales. We surface
/// it under the consumer-recognised label.
double? vo2MaxFromVdot(double? vdot) => vdot;

/// Threshold pace (s/km) from VDOT — Daniels T-pace. Solve the VO2
/// demand quadratic at 88% of VDOT (Daniels' "T-pace ≈ 88% vVO2max"
/// rule of thumb) for velocity in m/min, then convert to s/km:
///
///     demand(v) = -4.6 + 0.182258 v + 0.000104 v² = 0.88 × VDOT
///
/// Spot checks against Daniels' published table — VDOT 50 → 4:15/km,
/// VDOT 60 → 3:40/km, VDOT 70 → 3:14/km — match within a couple of
/// seconds across VDOT 30-70. Mirrors apps/web/src/lib/fitness.ts.
double? thresholdPaceSecPerKmFromVdot(double? vdot) {
  if (vdot == null || vdot <= 0) return null;
  final target = 0.88 * vdot + 4.6;
  const a = 0.000104;
  const b = 0.182258;
  final disc = b * b + 4 * a * target;
  if (disc < 0) return null;
  final vMpm = (-b + math.sqrt(disc)) / (2 * a);
  if (vMpm <= 0) return null;
  final mps = vMpm / 60;
  return 1000 / mps;
}

/// Training stress score for a single run.
double runTss(double distanceM, int durationS, double thresholdPaceSecPerKm) {
  if (distanceM < 100 || durationS < 30 || thresholdPaceSecPerKm <= 0) {
    return 0;
  }
  final runPaceSecPerKm = durationS / (distanceM / 1000);
  if (runPaceSecPerKm <= 0) return 0;
  final intensity = thresholdPaceSecPerKm / runPaceSecPerKm;
  final durationH = durationS / 3600;
  return durationH * intensity * intensity * 100;
}

/// EWMA: new = old + alpha · (sample − old). Alpha is a per-day decay
/// rate. Matches the curve in `training_load.dart` so the dashboard's
/// fitness/fatigue/form chart and this Fitness-card rollup agree.
double _ewma(double prev, double sample, double alpha) {
  return prev + alpha * (sample - prev);
}

class TrainingLoad {
  final double? acuteLoad;
  final double? chronicLoad;
  final double? trainingStressBal;
  const TrainingLoad({
    required this.acuteLoad,
    required this.chronicLoad,
    required this.trainingStressBal,
  });
}

/// Daily-bucketed TSS → 7-day ATL, 42-day CTL, TSB = CTL − ATL,
/// evaluated at `now`. Returns nulls when there's no data.
///
/// Computes fitness the same way as `training_load.dart` (the app's
/// prevailing convention, shared with streaks / recap): runs bucket by
/// LOCAL calendar day, and the EWMAs use alpha = 1 − exp(−1/halflife)
/// (a proper time constant) rather than a 1/N step. ATL halflife = 7,
/// CTL halflife = 42.
TrainingLoad trainingLoad(
  Iterable<Run> runs,
  double? thresholdPaceSecPerKm, {
  DateTime? now,
}) {
  if (thresholdPaceSecPerKm == null || runs.isEmpty) {
    return const TrainingLoad(
        acuteLoad: null, chronicLoad: null, trainingStressBal: null);
  }
  final byDay = <DateTime, double>{};
  for (final r in qualifyingRuns(runs)) {
    final key = _dayKey(r.startedAt);
    final tss = runTss(r.distanceMetres, r.duration.inSeconds,
        thresholdPaceSecPerKm);
    byDay.update(key, (existing) => existing + tss, ifAbsent: () => tss);
  }
  if (byDay.isEmpty) {
    return const TrainingLoad(
        acuteLoad: null, chronicLoad: null, trainingStressBal: null);
  }

  final t = (now ?? DateTime.now()).toLocal();
  final endDay = DateTime(t.year, t.month, t.day);
  final earliestMs = byDay.keys.map((k) => k.millisecondsSinceEpoch).reduce(math.min);
  final earliestStart =
      math.min(earliestMs, endDay.millisecondsSinceEpoch - 42 * 86400000);
  final startDay = DateTime.fromMillisecondsSinceEpoch(earliestStart);

  final atlAlpha = 1 - math.exp(-1 / 7);
  final ctlAlpha = 1 - math.exp(-1 / 42);
  var atl = 0.0;
  var ctl = 0.0;
  // After a sustained layoff (kLayoffResetDays of no runs) fitness is
  // genuinely lost — zero the EWMAs so a returning runner doesn't carry
  // a phantom CTL that fakes a high TSB and "very fresh, race soon"
  // advice. Persona-hunt comeback #29. Mirrors fitness.ts.
  var zeroStreak = 0;
  for (var d = startDay;
      !d.isAfter(endDay);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final tss = byDay[_dayKey(d)] ?? 0.0;
    if (tss > 0) {
      zeroStreak = 0;
    } else if (++zeroStreak >= kLayoffResetDays) {
      atl = 0;
      ctl = 0;
    }
    atl = _ewma(atl, tss, atlAlpha);
    ctl = _ewma(ctl, tss, ctlAlpha);
  }
  return TrainingLoad(
    acuteLoad: atl,
    chronicLoad: ctl,
    trainingStressBal: ctl - atl,
  );
}

DateTime _dayKey(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  return DateTime(local.year, local.month, local.day);
}

/// Top-level snapshot — combines VDOT, VO2 max, and training load into
/// a single struct for the dashboard cards.
FitnessSnapshot computeSnapshot(Iterable<Run> runs, {DateTime? now}) {
  final vdot = currentVdot(runs, now: now);
  final threshold = thresholdPaceSecPerKmFromVdot(vdot);
  final load = trainingLoad(runs, threshold, now: now);
  return FitnessSnapshot(
    vdot: vdot,
    vo2Max: vo2MaxFromVdot(vdot),
    acuteLoad: load.acuteLoad,
    chronicLoad: load.chronicLoad,
    trainingStressBal: load.trainingStressBal,
    qualifyingRunCount: qualifyingRuns(runs).length,
  );
}

/// Whether the runner is returning from a layoff: their most recent
/// qualifying run is recent (≤ 14 days before [now]) but the gap before
/// it was ≥ kLayoffResetDays. Drives the gentle "rebuild gradually"
/// framing so a returning runner isn't told they're "very fresh — race
/// soon". Mirrors fitness.ts. Persona-hunt comeback #29.
bool isReturningFromLayoff(Iterable<Run> runs, {DateTime? now}) {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final days = qualifyingRuns(runs)
      .map((r) => r.startedAt.millisecondsSinceEpoch)
      .where((t) => t <= nowMs)
      .toList()
    ..sort();
  if (days.isEmpty) return false;
  const dayMs = 24 * 3600 * 1000;
  final latest = days.last;
  if (nowMs - latest > 14 * dayMs) return false; // not currently active
  if (days.length == 1) return false; // one run can't prove a prior gap
  final prev = days[days.length - 2];
  return latest - prev >= kLayoffResetDays * dayMs;
}

/// Whether the runner is mid-gap returning: at least one run in their
/// history but the most recent is older than [gapDays]. Inverse case to
/// [isReturningFromLayoff] — that one fires once a recent run follows a
/// gap (already back), this fires while the gap is still open (reopening
/// the app cold). Drives the gentle "Welcome back" surface. Counts every
/// run (not just qualifying ones) — any logged activity proves prior
/// history. Mirrors fitness.ts. Persona round-5 comeback.
bool isReturningFromGap(Iterable<Run> runs,
    {int gapDays = 60, DateTime? now}) {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  var latest = -1 << 62;
  for (final r in runs) {
    final t = r.startedAt.millisecondsSinceEpoch;
    if (t <= nowMs && t > latest) latest = t;
  }
  if (latest == -1 << 62) return false;
  return nowMs - latest >= gapDays * 24 * 3600 * 1000;
}

/// Rule-based recovery advice from TSB + CTL. Mirrors the web's
/// thresholds 1:1.
String recoveryAdvice(double? tsb, double? ctl,
    {bool returningFromLayoff = false}) {
  if (tsb == null || ctl == null) {
    return 'Not enough data yet — log a few runs with HR and try again.';
  }
  // A returning runner can show a high TSB purely because ATL decayed
  // faster than CTL during the break — detraining, not freshness.
  // Persona-hunt comeback #29.
  if (returningFromLayoff) {
    return 'Welcome back. Your form numbers reset after the break — '
        'rebuild gradually with easy, consistent running before any hard '
        'sessions.';
  }
  // Heavy acute overload warrants a rest warning even at low chronic load.
  // A new runner who just spiked a hard week (low CTL, deeply negative TSB)
  // is exactly the at-injury-risk case the ctl<10 "still building" message
  // would otherwise mask — so the overload guard comes first.
  if (tsb < -30) {
    return "You're heavily loaded — easy running or a rest day today.";
  }
  if (ctl < 10) {
    return 'Fitness is still building. Focus on consistency; one quality '
        'session a week is plenty for now.';
  }
  if (tsb < -10) {
    return 'Loaded but within build territory. Easy / steady is right '
        'for today.';
  }
  if (tsb < 10) {
    return 'Sweet spot — a steady run or a tempo effort works.';
  }
  if (tsb < 25) {
    return 'Tapering / freshening up — a race or hard workout will land '
        'well in the next few days.';
  }
  return "Very fresh — if you've been tapering on purpose, race soon. "
      "Otherwise, it's time to build again.";
}

/// TSB at or above which a hard / quality session is advisable. Below
/// this the runner is still loaded enough that the next session should
/// stay easy. Matches the boundary in `recoveryAdvice` where the advice
/// flips from "easy / steady" to "a steady run or a tempo effort works".
const double kHardSessionTsbThreshold = -10;

/// Estimate how many easy / rest days until Form (TSB) recovers enough
/// for the next hard session. Projects the ATL / CTL EWMAs forward with
/// zero added stress — the fastest realistic recovery — so the answer
/// is a floor, not a promise. Returns 0 when already recovered, a
/// positive day count when recovery lands within [maxDays], or null
/// when it would take longer. Mirrors the web `daysUntilNextHardSession`.
int? daysUntilNextHardSession(double? atl, double? ctl, {int maxDays = 21}) {
  if (atl == null || ctl == null) return null;
  final atlDecay = math.exp(-1 / 7);
  final ctlDecay = math.exp(-1 / 42);
  var a = atl;
  var c = ctl;
  for (var d = 0; d <= maxDays; d++) {
    if (c - a >= kHardSessionTsbThreshold) return d;
    a *= atlDecay;
    c *= ctlDecay;
  }
  return null;
}
