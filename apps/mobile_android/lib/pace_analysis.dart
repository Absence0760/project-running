import 'package:core_models/core_models.dart';

import 'geo.dart';
import 'grade_adjusted_pace.dart';
import 'run_stats.dart' show haversineMetres;

/// Pacing analysis for a recorded run — the interpretation layer over the
/// splits list. Two questions the raw split list never answers:
///
///  1. Did the second half go faster than the first (a negative split), slower
///     (a fade), or the same?
///  2. Was that a pacing story or a terrain story? A split that climbs 80 m
///     reads as a blow-up in raw pace even when the effort never wavered, so
///     every figure here is also offered grade-adjusted (Minetti, via
///     [gradeAdjustedPaceSecPerKm]) whenever the track carries elevation.
///
/// Halves are cut by DISTANCE, not by time — "negative split" is a statement
/// about the second half of the course, and cutting by time would put the
/// halfway mark short of it on any run that faded. Durations are elapsed
/// within the half, matching how the splits list times its own boundaries.
///
/// Twin of `apps/web/src/lib/runs/pace_analysis.ts` — keep the algorithm,
/// constants, edge cases, and test count in lockstep.

/// Relative band around the first half's pace inside which the two halves are
/// called even. 2 % of pace — 6 s/km at a 5:00/km first half — which is the
/// conventional "evenly paced" tolerance and comfortably above GPS noise over
/// a half-run's worth of samples.
const double evenBandPct = 0.02;

enum PacingVerdict { negative, even, positive }

class HalfPace {
  final double distanceM;
  final double durationS;
  final int paceSecPerKm;
  const HalfPace({
    required this.distanceM,
    required this.durationS,
    required this.paceSecPerKm,
  });
}

class PacingHalves {
  final HalfPace first;
  final HalfPace second;

  /// Second half minus first, seconds per km. Negative = sped up.
  final int deltaSecPerKm;
  final PacingVerdict verdict;
  const PacingHalves({
    required this.first,
    required this.second,
    required this.deltaSecPerKm,
    required this.verdict,
  });
}

class GradeAdjustedHalves {
  final int firstSecPerKm;
  final int secondSecPerKm;
  final int deltaSecPerKm;
  final PacingVerdict verdict;
  const GradeAdjustedHalves({
    required this.firstSecPerKm,
    required this.secondSecPerKm,
    required this.deltaSecPerKm,
    required this.verdict,
  });
}

class PacingAnalysis {
  final PacingHalves raw;

  /// Null when either half carries no elevation, so GAP would be raw pace.
  final GradeAdjustedHalves? gradeAdjusted;
  const PacingAnalysis({required this.raw, this.gradeAdjusted});
}

/// First-half vs second-half pacing for a run's GPS track. Null when the track
/// is too short, carries no distance, or either half has no usable pair of
/// timestamps to derive a duration from.
PacingAnalysis? analysePacing(List<Waypoint>? track) {
  if (track == null || track.length < 2) return null;

  var total = 0.0;
  for (var i = 1; i < track.length; i++) {
    total += haversineMetres(
        track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
  }
  if (total <= 0) return null;

  final slices = _sliceTrackAtDistances(track, [total / 2]);
  final firstSlice = slices[0];
  final secondSlice = slices[1];
  final first = _halfPace(firstSlice);
  final second = _halfPace(secondSlice);
  if (first == null || second == null) return null;

  final gapFirst = gradeAdjustedPaceSecPerKm(firstSlice);
  final gapSecond = gradeAdjustedPaceSecPerKm(secondSlice);

  return PacingAnalysis(
    raw: PacingHalves(
      first: first,
      second: second,
      deltaSecPerKm: second.paceSecPerKm - first.paceSecPerKm,
      verdict: _verdictFor(first.paceSecPerKm, second.paceSecPerKm),
    ),
    gradeAdjusted: gapFirst != null && gapSecond != null
        ? GradeAdjustedHalves(
            firstSecPerKm: gapFirst,
            secondSecPerKm: gapSecond,
            deltaSecPerKm: gapSecond - gapFirst,
            verdict: _verdictFor(gapFirst, gapSecond),
          )
        : null,
  );
}

/// Grade-adjusted pace, in seconds per kilometre, for each split whose length
/// is given in [splitDistancesM] — one entry per split, aligned index-for-index
/// so the splits list can render it as a column beside the raw pace. Null for a
/// split whose slice of the track carries no elevation or no usable timing.
///
/// Boundaries are the running sum of the splits' own lengths, so the slices
/// land on exactly the boundaries the list already displays rather than on a
/// second, independently-walked set that could drift by a point. Web passes its
/// `Split[]` and reads `distance_m` off each; mobile's `RunSplit` carries only
/// a tick and a duration, so the caller hands the lengths over directly.
List<int?> gradeAdjustedSplitPaces(
    List<Waypoint>? track, List<double> splitDistancesM) {
  if (splitDistancesM.isEmpty) return const [];
  if (track == null || track.length < 2) {
    return List<int?>.filled(splitDistancesM.length, null);
  }

  final boundaries = <double>[];
  var cum = 0.0;
  for (final d in splitDistancesM) {
    cum += d;
    boundaries.add(cum);
  }
  final slices = _sliceTrackAtDistances(track, boundaries);
  return List<int?>.generate(
      splitDistancesM.length, (i) => gradeAdjustedPaceSecPerKm(slices[i]));
}

PacingVerdict _verdictFor(int firstSecPerKm, int secondSecPerKm) {
  final band = firstSecPerKm * evenBandPct;
  final delta = secondSecPerKm - firstSecPerKm;
  if (delta < -band) return PacingVerdict.negative;
  if (delta > band) return PacingVerdict.positive;
  return PacingVerdict.even;
}

HalfPace? _halfPace(List<Waypoint> slice) {
  if (slice.length < 2) return null;
  var distanceM = 0.0;
  for (var i = 1; i < slice.length; i++) {
    distanceM += haversineMetres(
        slice[i - 1].lat, slice[i - 1].lng, slice[i].lat, slice[i].lng);
  }
  if (distanceM <= 0) return null;

  final times = <DateTime>[];
  for (final p in slice) {
    final ts = p.timestamp;
    if (ts != null) times.add(ts);
  }
  if (times.length < 2) return null;
  final durationS =
      times.last.difference(times.first).inMilliseconds / 1000;
  if (durationS <= 0) return null;

  return HalfPace(
    distanceM: distanceM,
    durationS: durationS,
    paceSecPerKm: (durationS / (distanceM / 1000)).round(),
  );
}

/// Cut a track into `boundariesM.length + 1` contiguous slices at the given
/// cumulative horizontal distances, inserting an interpolated point at each
/// cut that both adjacent slices share — so no metre and no second of the run
/// falls between two slices. Always returns exactly that many slices; a
/// boundary past the end of the track yields an empty trailing slice.
List<List<Waypoint>> _sliceTrackAtDistances(
    List<Waypoint> track, List<double> boundariesM) {
  final slices = <List<Waypoint>>[];
  if (track.length < 2) {
    slices.add(List<Waypoint>.of(track));
    while (slices.length <= boundariesM.length) {
      slices.add(<Waypoint>[]);
    }
    return slices;
  }

  var cur = <Waypoint>[track[0]];
  var cum = 0.0;
  var bi = 0;
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    final segStart = cum;
    final segDist = haversineMetres(a.lat, a.lng, b.lat, b.lng);
    cum += segDist;
    while (bi < boundariesM.length && segDist > 0 && cum >= boundariesM[bi]) {
      final f = (boundariesM[bi] - segStart) / segDist;
      final cut = f <= 0
          ? a
          : f >= 1
              ? b
              : _interpolatePoint(a, b, f);
      if (!identical(cur.last, cut)) cur.add(cut);
      slices.add(cur);
      cur = <Waypoint>[cut];
      bi++;
    }
    if (!identical(cur.last, b)) cur.add(b);
  }
  slices.add(cur);
  while (slices.length <= boundariesM.length) {
    slices.add(<Waypoint>[]);
  }
  return slices;
}

Waypoint _interpolatePoint(Waypoint a, Waypoint b, double f) {
  final ae = a.elevationMetres;
  final be = b.elevationMetres;
  final at = a.timestamp;
  final bt = b.timestamp;
  return Waypoint(
    lat: a.lat + (b.lat - a.lat) * f,
    // Longitude through `lonDeltaDeg`: a plain subtraction is a whole turn out
    // across the antimeridian, which would place the cut point on the far side
    // of the planet and hand both halves a nonsense distance.
    lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * f),
    elevationMetres: (ae != null && be != null) ? ae + (be - ae) * f : null,
    timestamp: (at != null && bt != null)
        ? at.add(Duration(
            milliseconds: (bt.difference(at).inMilliseconds * f).toInt()))
        : null,
  );
}
