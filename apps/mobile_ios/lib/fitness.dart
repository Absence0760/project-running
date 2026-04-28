import 'dart:math' as math;

import 'package:core_models/core_models.dart';

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

/// Qualifying runs for fitness math: an actual recording or reliable
/// import, distance >= 3 km, duration >= 5 min.
List<Run> qualifyingRuns(Iterable<Run> runs) {
  return [
    for (final r in runs)
      if (r.distanceMetres >= 3000 &&
          r.duration.inSeconds >= 300 &&
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

/// Threshold pace (s/km) from VDOT — Daniels T-pace inversion of his
/// pace tables. T-pace ≈ 1000 / (0.0003·V³ − 0.021·V² + 0.6·V + 2.0).
double? thresholdPaceSecPerKmFromVdot(double? vdot) {
  if (vdot == null) return null;
  final mps = 0.0003 * vdot * vdot * vdot -
      0.021 * vdot * vdot +
      0.6 * vdot +
      2.0;
  if (mps <= 0) return null;
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

double _ewma(double prev, double sample, double tau) {
  return prev + (sample - prev) / tau;
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
TrainingLoad trainingLoad(
  Iterable<Run> runs,
  double? thresholdPaceSecPerKm, {
  DateTime? now,
}) {
  if (thresholdPaceSecPerKm == null || runs.isEmpty) {
    return const TrainingLoad(
        acuteLoad: null, chronicLoad: null, trainingStressBal: null);
  }
  final byDay = <String, double>{};
  for (final r in qualifyingRuns(runs)) {
    final key = _dayKey(r.startedAt.toUtc());
    final tss = runTss(r.distanceMetres, r.duration.inSeconds,
        thresholdPaceSecPerKm);
    byDay.update(key, (existing) => existing + tss, ifAbsent: () => tss);
  }
  if (byDay.isEmpty) {
    return const TrainingLoad(
        acuteLoad: null, chronicLoad: null, trainingStressBal: null);
  }

  final t = (now ?? DateTime.now()).toUtc();
  final endDay = DateTime.utc(t.year, t.month, t.day);
  final earliestMs = byDay.keys
      .map((k) => DateTime.parse('${k}T00:00:00Z').millisecondsSinceEpoch)
      .reduce(math.min);
  final earliestStart =
      math.min(earliestMs, endDay.millisecondsSinceEpoch - 42 * 86400000);
  final startDay = DateTime.fromMillisecondsSinceEpoch(earliestStart, isUtc: true);

  var atl = 0.0;
  var ctl = 0.0;
  for (var d = startDay;
      !d.isAfter(endDay);
      d = d.add(const Duration(days: 1))) {
    final tss = byDay[_dayKey(d)] ?? 0.0;
    atl = _ewma(atl, tss, 7);
    ctl = _ewma(ctl, tss, 42);
  }
  return TrainingLoad(
    acuteLoad: atl,
    chronicLoad: ctl,
    trainingStressBal: ctl - atl,
  );
}

String _dayKey(DateTime dt) {
  final yyyy = dt.year.toString().padLeft(4, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd';
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

/// Rule-based recovery advice from TSB + CTL. Mirrors the web's
/// thresholds 1:1.
String recoveryAdvice(double? tsb, double? ctl) {
  if (tsb == null || ctl == null) {
    return 'Not enough data yet — log a few runs with HR and try again.';
  }
  if (ctl < 10) {
    return 'Fitness is still building. Focus on consistency; one quality '
        'session a week is plenty for now.';
  }
  if (tsb < -30) {
    return "You're heavily loaded — easy running or a rest day today.";
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
