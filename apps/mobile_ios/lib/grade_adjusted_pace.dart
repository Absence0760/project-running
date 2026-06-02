import 'package:core_models/core_models.dart';

import 'run_stats.dart' show haversineMetres;

/// Grade-adjusted pace (GAP): the flat-ground pace that would cost the same
/// metabolic effort as the run actually recorded over hilly terrain. Raw
/// average pace lies on hills — a 6:00/km grind up a 10% wall reads slow and a
/// screaming descent reads fast — so trail and ultra runners want the
/// effort-equivalent number instead.
///
/// Energy-cost model: Minetti et al. 2002, "Energy cost of walking and running
/// at extreme uphill and downhill slopes" (J Appl Physiol 93:1039). C(i) is the
/// metabolic cost of running at gradient i (rise/run, fractional); the GAP
/// factor is C(i)/C(0) — how much harder this grade is than flat. Equivalent
/// flat distance for a segment is its horizontal distance times that factor.
///
/// Twin of `apps/web/src/lib/runs/grade_adjusted_pace.ts` — keep the
/// algorithm, constants, edge cases, and test count in lockstep. Ported from
/// the on-watch Connect IQ field at
/// `apps/watch_garmin/source/GradeAdjustedPaceView.mc`.

/// Flat-ground running cost C(0) from the polynomial below.
const double minettiFlatCost = 3.6;

/// Minetti's fit is only valid between roughly -45% and +45% grade; clamp to
/// that so a momentary GPS-altitude spike can't manufacture an absurd factor.
const double maxGrade = 0.45;

/// Minimum horizontal travel before a grade sample is trusted. GPS altitude is
/// jittery point-to-point, so grade is measured over a segment, mirroring the
/// watch field. 5 m matches `GradeAdjustedPaceView.mc`.
const double minSegmentM = 5.0;

/// Minetti 2002 5th-order fit: C(i) in J/kg/m, i fractional gradient.
double minettiCostAtGrade(double i) {
  final i2 = i * i;
  final i3 = i2 * i;
  final i4 = i3 * i;
  final i5 = i4 * i;
  return 155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6;
}

/// Cost multiplier relative to flat ground at a given fractional grade, with
/// the grade clamped to Minetti's valid range. 1.0 on the flat, > 1 uphill,
/// < 1 on gentle descents (running downhill is cheap until ~-20%).
double gradeFactor(double grade) {
  var g = grade;
  if (g > maxGrade) g = maxGrade;
  if (g < -maxGrade) g = -maxGrade;
  return minettiCostAtGrade(g) / minettiFlatCost;
}

/// Overall grade-adjusted pace for a run, in seconds per kilometre. Returns
/// null when GAP can't be computed or carries no information:
///  - fewer than two track points,
///  - no timestamps (can't derive segment durations),
///  - no elevation data at all (GAP would equal raw pace).
///
/// Walks the track accumulating horizontal distance until a segment is at
/// least [minSegmentM] long, then applies that segment's grade factor to its
/// horizontal distance to get equivalent-flat distance. GAP = total time over
/// total equivalent-flat distance.
int? gradeAdjustedPaceSecPerKm(List<Waypoint> track) {
  if (track.length < 2) return null;

  var anchor = 0;
  var segHoriz = 0.0;
  var adjDistM = 0.0;
  var timeS = 0.0;
  var sawEle = false;

  for (var i = 1; i < track.length; i++) {
    segHoriz +=
        haversineMetres(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
    if (segHoriz < minSegmentM) continue;

    final a = track[anchor];
    final b = track[i];
    final at = a.timestamp;
    final bt = b.timestamp;
    final dtMs = (at != null && bt != null) ? bt.difference(at).inMilliseconds : -1;
    if (dtMs > 0) {
      var factor = 1.0;
      final ae = a.elevationMetres;
      final be = b.elevationMetres;
      if (ae != null && be != null) {
        sawEle = true;
        factor = gradeFactor((be - ae) / segHoriz);
      }
      adjDistM += segHoriz * factor;
      timeS += dtMs / 1000;
    }
    // Advance the anchor whether or not the segment was usable — a chunk
    // without timestamps shouldn't wedge the walk forever.
    anchor = i;
    segHoriz = 0.0;
  }

  if (!sawEle || adjDistM <= 0 || timeS <= 0) return null;
  return (timeS / (adjDistM / 1000)).round();
}
