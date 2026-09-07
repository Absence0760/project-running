import 'package:core_models/core_models.dart';

/// Time-weighted heart-rate zone breakdown over a run's GPS track.
///
/// Mirrors the algorithm in `apps/web/src/routes/runs/[id]/+page.svelte`:
/// each sample is weighted by half the gap to the previous + half the
/// gap to the next (each capped at 30 s so a paused recording can't let
/// one sample dominate). When timestamps are missing the breakdown
/// falls back to sample-count weighting.
///
/// `cutoffs` are zone *upper bounds* — a BPM ≤ cutoffs[0] is Z1, ≤ cutoffs[1]
/// is Z2, etc. Pass null to use the classic 60/70/80/90/100 % HR-max bands
/// keyed off 190 bpm max.
List<HrZoneBucket> hrZoneBreakdown(
  List<Waypoint> track, {
  List<int>? cutoffs,
}) {
  final c = cutoffs ?? const [114, 133, 152, 171, 190];
  if (c.length != 5) {
    throw ArgumentError('cutoffs must have exactly 5 entries');
  }

  final samples = <_Sample>[];
  for (final w in track) {
    final b = w.bpm;
    if (b == null || b < 30 || b > 230) continue;
    final ts = w.timestamp?.millisecondsSinceEpoch;
    samples.add(_Sample(b, ts));
  }
  if (samples.isEmpty) return const [];

  final haveTime = samples.every((s) => s.tMs != null);
  final weights = List<double>.filled(samples.length, 1);
  if (haveTime) {
    final ts = samples.map((s) => s.tMs!).toList();
    for (var i = 0; i < ts.length; i++) {
      final prev = i > 0 ? (ts[i] - ts[i - 1]).toDouble() : 0.0;
      final next = i < ts.length - 1 ? (ts[i + 1] - ts[i]).toDouble() : 0.0;
      final w = _capHalf(prev) + _capHalf(next);
      weights[i] = w < 0 ? 0 : w;
    }
  }

  final totals = List<double>.filled(5, 0);
  var totalWeight = 0.0;
  for (var i = 0; i < samples.length; i++) {
    totals[_zoneIndex(samples[i].bpm, c)] += weights[i];
    totalWeight += weights[i];
  }
  if (totalWeight <= 0) {
    for (final s in samples) {
      totals[_zoneIndex(s.bpm, c)] += 1;
    }
    totalWeight = samples.length.toDouble();
  }

  return List.generate(5, (i) {
    return HrZoneBucket(
      index: i,
      pct: ((totals[i] / totalWeight) * 100).round(),
      seconds: haveTime ? (totals[i] / 1000).round() : null,
    );
  });
}

/// The range a stored `max_hr_bpm` has to fall in to be used as one. It is a
/// jsonb prefs key with no column and therefore no CHECK, so every reader
/// carries this bound itself; a value outside it is ignored rather than
/// trusted, and the derivation falls through to age or to the legacy ladder.
const int kMaxHrBpmMin = 80;
const int kMaxHrBpmMax = 240;

/// Whether a stored `max_hr_bpm` may be used as one. Every reader ignores a
/// value outside the range, so every WRITER has to refuse the same one, or the
/// runner types a figure the app accepts and then silently declines to use
/// (decisions § 1407). Stating the test once is the point: the bound was
/// already named per rail, and it was the three separate spellings of it that
/// let the Wear OS rail apply a value the other two ignored (§ 1245).
bool isUsableMaxHrBpm(int? value) =>
    value != null && value >= kMaxHrBpmMin && value <= kMaxHrBpmMax;

/// The range a stored `resting_hr_bpm` has to fall in to be used as one. The
/// second jsonb HR pref with no column and therefore no CHECK, so it is named
/// beside the max-HR range rather than in `training_load` (its only reader):
/// "what range is an HR pref allowed to be" having one home is the whole
/// lesson of § 1245, where three separate spellings of the max-HR bound let
/// one rail use a value the other two ignored.
///
/// 20..200 is the WIDER of the two ranges the tree already shipped — this
/// screen's own picker took 20..200 while both web inputs carry an advisory
/// `min="30" max="120"` that never reaches constraint validation — so naming
/// it refuses nothing any rail accepts today.
const int kRestingHrBpmMin = 20;
const int kRestingHrBpmMax = 200;

/// Whether a typed `resting_hr_bpm` may be stored as one. Unlike
/// `isUsableMaxHrBpm` this is a WRITE-side test only: `training_load` reads the
/// key with no bound of its own beyond requiring `rest < max`, so nothing here
/// is claiming the readers ignore what it refuses.
bool isUsableRestingHrBpm(int? value) =>
    value != null && value >= kRestingHrBpmMin && value <= kRestingHrBpmMax;

/// The age range Tanaka is applied over, for the same reason.
const int kTanakaAgeMin = 5;
const int kTanakaAgeMax = 120;

/// Tanaka (2001) age-predicted maximal heart rate: 208 − 0.7 × age.
/// More accurate for masters runners than the classic 220 − age, which
/// systematically overestimates HR-max past ~40 and pushed older
/// runners into falsely-low zones (persona-hunt Older #8). The Dart twin of
/// `apps/web/src/lib/training/hr_zones.ts` (`tanakaMaxHr`), which also has a
/// THIRD rail outside the enforced pair: the Wear OS `resolveZoneCutoffs` in
/// `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/SupabaseClient.kt`.
/// All three share the derivation and the input range; the watch alone returns
/// null rather than the legacy 190 ladder when there is no usable signal, which
/// is deliberate and stated on all three rails (decisions § 1245).
int tanakaMaxHr(int ageYears) => (208 - 0.7 * ageYears).round();

/// Zone upper bounds (Z1..Z5) at 60/70/80/90/100 % of a max HR.
List<int> zoneCutoffsFromMaxHr(int maxHr) =>
    [0.6, 0.7, 0.8, 0.9, 1.0].map((p) => (maxHr * p).round()).toList();

/// Default zone cutoffs when the runner hasn't set explicit `hr_zones`.
/// Precedence: an explicit `max_hr_bpm` override → Tanaka from age →
/// the legacy 190-bpm fallback (`zoneCutoffsFromMaxHr(190)` ==
/// `[114, 133, 152, 171, 190]`). Mirrors the TS `defaultZoneCutoffs`.
List<int> defaultZoneCutoffs({int? maxHrBpm, int? ageYears}) {
  if (isUsableMaxHrBpm(maxHrBpm)) {
    return zoneCutoffsFromMaxHr(maxHrBpm!);
  }
  if (ageYears != null && ageYears >= kTanakaAgeMin && ageYears <= kTanakaAgeMax) {
    return zoneCutoffsFromMaxHr(tanakaMaxHr(ageYears));
  }
  return zoneCutoffsFromMaxHr(190);
}

double _capHalf(double gap) {
  // 30 s cap on either half-gap so a multi-minute pause can't inflate one
  // sample's slice into the entire run.
  const cap = 30000.0;
  final half = gap / 2;
  return half > cap ? cap : half;
}

int _zoneIndex(int bpm, List<int> cutoffs) {
  if (bpm <= cutoffs[0]) return 0;
  if (bpm <= cutoffs[1]) return 1;
  if (bpm <= cutoffs[2]) return 2;
  if (bpm <= cutoffs[3]) return 3;
  return 4;
}

class HrZoneBucket {
  final int index; // 0..4
  final int pct;
  final int? seconds;

  const HrZoneBucket({
    required this.index,
    required this.pct,
    this.seconds,
  });

  String get label {
    switch (index) {
      case 0:
        return 'Recovery';
      case 1:
        return 'Easy';
      case 2:
        return 'Aerobic';
      case 3:
        return 'Threshold';
      default:
        return 'Max';
    }
  }
}

class _Sample {
  final int bpm;
  final int? tMs;
  const _Sample(this.bpm, this.tMs);
}

/// Min / max / mean of the per-point BPM samples on a run track. Returns
/// null when no valid samples are present.
({int min, int max, int avg})? bpmStatsOf(List<Waypoint> track) {
  int? min;
  int? max;
  var sum = 0;
  var count = 0;
  for (final w in track) {
    final b = w.bpm;
    if (b == null || b < 30 || b > 230) continue;
    if (min == null || b < min) min = b;
    if (max == null || b > max) max = b;
    sum += b;
    count++;
  }
  if (count == 0) return null;
  return (min: min!, max: max!, avg: (sum / count).round());
}
