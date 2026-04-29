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

/// Per-run training stress score. Tier ladder (matches web):
/// 1. Banister TRIMP when avg_bpm + resting + max are all known.
/// 2. Distance proxy: 10 points per kilometre.
/// 3. Zero when neither distance nor duration is set.
double computeStress(Run run, [HrPrefs prefs = const HrPrefs()]) {
  if (run.distanceMetres <= 0 && run.duration.inSeconds <= 0) return 0;

  final avgBpm = _numericOrNull(run.metadata?['avg_bpm']);
  final rest = _numericOrNull(prefs.restingHrBpm);
  final max = _numericOrNull(prefs.maxHrBpm);

  if (avgBpm != null && rest != null && max != null && max > rest) {
    final durationMin = run.duration.inSeconds / 60.0;
    final hrr = math.max(0.0, math.min(1.0, (avgBpm - rest) / (max - rest)));
    const k = 1.92;
    return durationMin * hrr * 0.64 * math.exp(k * hrr);
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
  final out = <DateTime, double>{};
  for (final r in runs) {
    final stress = computeStress(r, prefs);
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
