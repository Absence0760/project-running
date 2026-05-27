import 'dart:math' as math;

import 'package:core_models/core_models.dart';

/// Pure Dart port of `apps/web/src/lib/training_load.ts` (decisions §34).
/// Computes a per-run training-stress score (TRIMP when HR available,
/// distance proxy otherwise), aggregates by local calendar day, and
/// returns a 90-day daily series with the EWMA Fitness / Fatigue / Form
/// trio. Stays in sync with the web copy.

class HrPrefs {
  final num? restingHrBpm;
  final num? maxHrBpm;
  const HrPrefs({this.restingHrBpm, this.maxHrBpm});
}

class TrainingLoadPoint {
  final DateTime date;
  final double stress;
  final double atl;
  final double ctl;
  final double tsb;
  const TrainingLoadPoint({
    required this.date,
    required this.stress,
    required this.atl,
    required this.ctl,
    required this.tsb,
  });
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
    if (avgBpm != null && rest != null && max != null && max > rest) {
      return _banisterTrimp(run.duration.inSeconds, avgBpm, rest, max);
    }
    final km = run.distanceMetres / 1000.0;
    final rate = cal.trimpPerKmFallback ?? 7;
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
/// alpha = 1 - exp(-1/halflife). ATL halflife = 7, CTL halflife = 42.
List<TrainingLoadPoint> computeTrainingLoadSeries(
  List<Run> runs, {
  HrPrefs prefs = const HrPrefs(),
  int windowDays = 90,
  DateTime? endDate,
}) {
  final daily = aggregateDailyStress(runs, prefs);
  final atlAlpha = 1 - math.exp(-1 / 7);
  final ctlAlpha = 1 - math.exp(-1 / 42);

  var atl = 0.0;
  var ctl = 0.0;
  final points = <TrainingLoadPoint>[];

  final now = endDate ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var cursor = today.subtract(Duration(days: windowDays - 1));

  for (var i = 0; i < windowDays; i++) {
    final stress = daily[cursor] ?? 0;
    atl = atl + atlAlpha * (stress - atl);
    ctl = ctl + ctlAlpha * (stress - ctl);
    points.add(TrainingLoadPoint(
      date: cursor,
      stress: stress,
      atl: _round2(atl),
      ctl: _round2(ctl),
      tsb: _round2(ctl - atl),
    ));
    cursor = cursor.add(const Duration(days: 1));
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
