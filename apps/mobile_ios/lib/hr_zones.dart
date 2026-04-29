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
