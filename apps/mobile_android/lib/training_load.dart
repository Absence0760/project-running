import 'dart:math' as math;

import 'package:core_models/core_models.dart';

/// Pure Dart port of `apps/web/src/lib/training_load.ts` (decisions §34).
/// Computes a per-run training-stress score (TRIMP when HR available,
/// distance proxy otherwise), aggregates by local calendar day, and
/// returns a 90-day daily series with the EWMA Fitness / Fatigue / Form
/// trio. Stays in sync with the web copy.

/// Consecutive run-less days after which fitness is treated as lost and
/// the CTL/ATL EWMAs reset to zero. Mirrors `kLayoffResetDays` in
/// `training_load.ts` / `fitness.ts` (and `fitness.dart`) — keep all four
/// in lockstep. Persona-hunt comeback #29.
const int kLayoffResetDays = 28;

class HrPrefs {
  final num? restingHrBpm;
  final num? maxHrBpm;
  const HrPrefs({this.restingHrBpm, this.maxHrBpm});
}

class TrainingLoadPoint {
  final DateTime date;

  /// Total daily stress (run + lift). Equals runStress when no lifts are
  /// passed, so the run-only curve is unchanged.
  final double stress;

  /// Provenance split — runStress is always recoverable so a lift-load bug
  /// can't corrupt run-only readiness. liftStress is 0 when no lifts pass.
  final double runStress;
  final double liftStress;
  final double atl;
  final double ctl;
  final double tsb;
  const TrainingLoadPoint({
    required this.date,
    required this.stress,
    this.runStress = 0,
    this.liftStress = 0,
    required this.atl,
    required this.ctl,
    required this.tsb,
  });
}

// ─────────────────── Lift load (Phase 4 multi-modal, decisions §63) ───────────────────
//
// Dart twin of the lift-load block in
// `apps/web/src/lib/training/training_load.ts` — keep behaviour in lockstep
// (multi_modal.md § "Lift training-load spec"). Lifts feed the SAME daily
// series as runs but carry separable provenance: pass no lifts and the
// run-only curve a runner trusts is recoverable unchanged.

class LiftSetForLoad {
  final num? reps;
  final num? weightKg;
  final num? rpe;
  const LiftSetForLoad({this.reps, this.weightKg, this.rpe});
}

class LiftForLoad {
  final DateTime startedAt;
  final List<LiftSetForLoad> sets;
  const LiftForLoad({required this.startedAt, required this.sets});
}

/// Tonnage → stress. Calibrated against a ~8,000 kg hard session at RPE 8 so
/// it scores ≈50 — the easy-run TSS band.
const double kLiftStressPerKgTonnage = 50 / 8000;

/// Per-session hard cap so a typo'd weight can't spike the shared curve.
const double kLiftStressCap = 150;

/// RPE → intensity multiplier, anchored at RPE 8 = 1.0; absent RPE = 1.0;
/// bounded so a stray value can't dominate tonnage.
double rpeFactor(num? rpe) {
  if (rpe == null || !rpe.toDouble().isFinite) return 1.0;
  final f = 0.5 + rpe / 16;
  return math.max(0.5, math.min(1.25, f.toDouble()));
}

/// Per-session lift stress: `k · Σ(reps · weight_kg · rpeFactor)`, capped.
/// Sets missing reps or weight contribute nothing.
double computeLiftStress(LiftForLoad lift) {
  var weighted = 0.0;
  for (final s in lift.sets) {
    final reps = s.reps;
    final weight = s.weightKg;
    if (reps == null || reps <= 0 || weight == null || weight <= 0) continue;
    weighted += reps * weight * rpeFactor(s.rpe);
  }
  final stress = weighted * kLiftStressPerKgTonnage;
  return math.min(stress, kLiftStressCap);
}

/// Sum lift stress by local calendar day, mirroring aggregateDailyStress.
Map<DateTime, double> aggregateDailyLiftStress(List<LiftForLoad> lifts) {
  final out = <DateTime, double>{};
  for (final l in lifts) {
    final stress = computeLiftStress(l);
    if (stress <= 0) continue;
    final local = l.startedAt.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    out[key] = (out[key] ?? 0) + stress;
  }
  return out;
}

/// Stress-model calibration for a window. Persona-hunt finding Pro #2
/// (decisions §34): a per-run "TRIMP when HR present, else distance"
/// fallback produces wildly different stress for the same effort —
/// an easy 12 km run = ~80 TRIMP with strap, 120 distance-fallback
/// without. A single strap-less day faked a 3× spike in the daily
/// series → TSB drifted tens of points → wrong tapering decisions.
///
/// The fix: pick ONE mode per window and calibrate the fallback so
/// runs without HR contribute comparable load. `mode='trimp'` uses
/// the runner's own data — median TRIMP-per-km across HR-eligible
/// runs in the window — as the fallback rate for runs that lack HR.
class StressCalibration {
  final String mode; // 'trimp' | 'distance'
  final double? trimpPerKmFallback;
  const StressCalibration({required this.mode, this.trimpPerKmFallback});
}

/// Decide the calibration for a window. If the user has the HR prefs
/// configured AND at least one run with avg_bpm in the window, mode
/// is 'trimp' — fallback rate is the median TRIMP-per-km of the
/// eligible runs (anchored to the user's own intensity profile).
/// Otherwise mode is 'distance' (legacy 10 pts/km).
StressCalibration computeCalibration(
  List<Run> runs, [
  HrPrefs prefs = const HrPrefs(),
]) {
  final rest = _numericOrNull(prefs.restingHrBpm);
  final max = _numericOrNull(prefs.maxHrBpm);
  if (rest == null || max == null || max <= rest) {
    return const StressCalibration(mode: 'distance');
  }
  final trimpsPerKm = <double>[];
  for (final r in runs) {
    final avgBpm = _numericOrNull(r.metadata?['avg_bpm']);
    final km = r.distanceMetres / 1000.0;
    if (avgBpm == null || km <= 0 || r.duration.inSeconds <= 0) continue;
    final trimp = _banisterTrimp(r.duration.inSeconds, avgBpm, rest, max);
    if (trimp > 0) trimpsPerKm.add(trimp / km);
  }
  if (trimpsPerKm.isEmpty) {
    return const StressCalibration(mode: 'distance');
  }
  return StressCalibration(
    mode: 'trimp',
    trimpPerKmFallback: _median(trimpsPerKm),
  );
}

double _banisterTrimp(int durationS, double avgBpm, double rest, double max) {
  final durationMin = durationS / 60.0;
  final hrr = math.max(0.0, math.min(1.0, (avgBpm - rest) / (max - rest)));
  const k = 1.92;
  return durationMin * hrr * 0.64 * math.exp(k * hrr);
}

double _median(List<double> xs) {
  final sorted = [...xs]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length % 2 == 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

/// Per-run training stress score. Pass a `calibration` to honour the
/// window-level mode (recommended via `aggregateDailyStress`, which
/// derives one calibration for the whole window). The legacy per-run
/// dispatch (no calibration arg) is kept for callers that score a
/// single isolated run.
double computeStress(
  Run run, [
  HrPrefs prefs = const HrPrefs(),
  StressCalibration? calibration,
]) {
  if (run.distanceMetres <= 0 && run.duration.inSeconds <= 0) return 0;

  final cal = calibration ?? computeCalibration([run], prefs);

  final avgBpm = _numericOrNull(run.metadata?['avg_bpm']);
  final rest = _numericOrNull(prefs.restingHrBpm);
  final max = _numericOrNull(prefs.maxHrBpm);

  if (cal.mode == 'trimp') {
    final km = run.distanceMetres / 1000.0;
    final rate = cal.trimpPerKmFallback ?? 7;
    if (avgBpm != null && rest != null && max != null && max > rest) {
      final trimp = _banisterTrimp(run.duration.inSeconds, avgBpm, rest, max);
      // A run whose avg_bpm <= resting_hr (misconfigured resting HR, strap
      // dropout, a genuine recovery shuffle) computes hrr=0 → trimp=0, and
      // the stress<=0 skip in aggregateDailyStress would silently drop a real
      // logged run off the fatigue/form curve. Fall back to the same distance
      // proxy an HR-less run uses so a real effort always counts.
      if (trimp > 0) return trimp;
      return km * rate;
    }
    return km * rate;
  }

  return (run.distanceMetres / 1000.0) * 10;
}

double? _numericOrNull(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final n = double.tryParse(v);
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

/// Sum stresses by local calendar day. Returned map is keyed by
/// midnight-local DateTime so callers can sort / index them as values
/// rather than parsing yyyy-mm-dd strings.
Map<DateTime, double> aggregateDailyStress(
  List<Run> runs, [
  HrPrefs prefs = const HrPrefs(),
]) {
  final calibration = computeCalibration(runs, prefs);
  final out = <DateTime, double>{};
  for (final r in runs) {
    final stress = computeStress(r, prefs, calibration);
    if (stress <= 0) continue;
    final local = r.startedAt.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    out[key] = (out[key] ?? 0) + stress;
  }
  return out;
}

/// EWMA trio over a fixed-length daily window ending today (local tz).
/// Days with no stress still tick the decay — that's the whole point.
/// alpha = 1 - exp(-1/tau). ATL time constant = 7 days, CTL = 42 days.
///
/// Persona-hunt Round 2 finding Pro #2: a pro with years of history
/// has been at CTL ≈ 80 for ages; initialising atl=0, ctl=0 and
/// walking only the last 90 days made the chart ramp from 0 over the
/// first 6 weeks. The warm-up walk (3× CTL halflife = 126 days
/// before the displayed window) seeds the EWMAs to steady state so
/// day 1 of the chart starts at the right level.
List<TrainingLoadPoint> computeTrainingLoadSeries(
  List<Run> runs, {
  HrPrefs prefs = const HrPrefs(),
  int windowDays = 90,
  DateTime? endDate,
  List<LiftForLoad> lifts = const [],
}) {
  final daily = aggregateDailyStress(runs, prefs);
  final dailyLift = aggregateDailyLiftStress(lifts);
  final atlAlpha = 1 - math.exp(-1 / 7);
  final ctlAlpha = 1 - math.exp(-1 / 42);

  const warmupDays = 42 * 3;

  var atl = 0.0;
  var ctl = 0.0;
  // Consecutive zero-stress days. After a sustained layoff
  // (kLayoffResetDays of no runs) fitness is genuinely lost, so we zero
  // the EWMAs — otherwise CTL (42-day halflife) lingers while ATL
  // (7-day) craters, faking a high TSB that reads as "fresh, train hard"
  // to a returning runner. Carries across the warm-up → display boundary.
  // Persona-hunt comeback #29. Mirrors training_load.ts.
  var zeroStreak = 0;
  void step(double stress) {
    if (stress > 0) {
      zeroStreak = 0;
    } else {
      zeroStreak++;
      if (zeroStreak >= kLayoffResetDays) {
        atl = 0;
        ctl = 0;
      }
    }
    atl = atl + atlAlpha * (stress - atl);
    ctl = ctl + ctlAlpha * (stress - ctl);
  }

  final now = endDate ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Walk warm-up days first to seed EWMAs. No chart points emitted
  // for these — they only update the running totals. Cursor steps
  // are CALENDAR additions (DateTime(y, m, d + 1)) rather than
  // Duration(days: 1) so a DST transition doesn't shift the cursor
  // off midnight and miss the day's daily-map key.
  for (var i = 0; i < warmupDays; i++) {
    final day = DateTime(today.year, today.month,
        today.day - (windowDays - 1) - warmupDays + i);
    step((daily[day] ?? 0).toDouble() + (dailyLift[day] ?? 0).toDouble());
  }

  final points = <TrainingLoadPoint>[];
  for (var i = 0; i < windowDays; i++) {
    final day =
        DateTime(today.year, today.month, today.day - (windowDays - 1) + i);
    final runStress = (daily[day] ?? 0).toDouble();
    final liftStress = (dailyLift[day] ?? 0).toDouble();
    final stress = runStress + liftStress;
    step(stress);
    points.add(TrainingLoadPoint(
      date: day,
      stress: stress,
      runStress: _round2(runStress),
      liftStress: _round2(liftStress),
      atl: _round2(atl),
      ctl: _round2(ctl),
      tsb: _round2(ctl - atl),
    ));
  }
  return points;
}

double _round2(double n) => (n * 100).roundToDouble() / 100;

/// True when at least one run carries a TRIMP-eligible HR signal —
/// drives the chart subtitle ("HR-based" vs "volume-based").
bool hasTrimpSignal(List<Run> runs, [HrPrefs prefs = const HrPrefs()]) {
  if (prefs.restingHrBpm == null || prefs.maxHrBpm == null) return false;
  for (final r in runs) {
    if (_numericOrNull(r.metadata?['avg_bpm']) != null) return true;
  }
  return false;
}
