import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/grade_adjusted_pace.dart';
import '../lib/route_simplify.dart' show kElevationGainMinDeltaM;

/// Mirror of `apps/web/src/lib/runs/grade_adjusted_pace.test.ts`. Keep in
/// lockstep — the GAP figure shown on mobile run detail and on web run detail
/// (and the on-watch Connect IQ field) all derive from this Minetti model.

/// Build a straight east-west track at a constant horizontal speed and a
/// constant grade. [gradePct] is rise/run as a percentage.
List<Waypoint> gradedTrack({
  required int points,
  required double stepM,
  required double stepS,
  required double gradePct,
  double eleStart = 100,
  bool withEle = true,
  bool withTs = true,
}) {
  const lat = 40.0;
  final t0 = DateTime.utc(2026, 1, 1);
  final degPerM = 1 / (111320 * cos(lat * pi / 180));
  final out = <Waypoint>[];
  var ele = eleStart;
  for (var i = 0; i < points; i++) {
    out.add(Waypoint(
      lat: lat,
      lng: -100 + i * stepM * degPerM,
      elevationMetres: withEle ? ele : null,
      timestamp: withTs ? t0.add(Duration(milliseconds: (i * stepS * 1000).round())) : null,
    ));
    ele += (gradePct / 100) * stepM;
  }
  return out;
}

/// The GAP reference track: a clean, noise-free 6% climb switchbacking
/// +/-8 m every 150 m, walked at 5 m every 3 s for 3 km — the 30-minute
/// power-hike-paced staircase decisions § 992 measured the window's cost on,
/// and the profile that binds its UPPER end. Points sit on a line of constant
/// latitude, where the haversine collapses exactly to R * dLambda, so
/// [kGapReferenceHorizStepM] is a closed form rather than a second copy of the
/// module's own distance function.
///
/// Frozen on three rails — this file, `grade_adjusted_pace.test.ts` and the
/// firmware's `grade_adjusted_pace.rs` — and compared between them by
/// `scripts/check_watch_wire_vectors.mjs`, which reads all eight constants out
/// of each. A fixture that drifts on one rail makes its golden meaningless
/// rather than wrong, which is the failure nothing would otherwise report
/// (decisions § 641).
const int kGapReferencePoints = 601;
const double kGapReferenceStepM = 5.0;
const int kGapReferenceStepS = 3;
const double kGapReferenceBaseGrade = 0.06;
const double kGapReferenceAmplitudeM = 8.0;
const double kGapReferencePeriodM = 150.0;
const int kGapReferenceSPerKm = 311;
const double kGapReferenceMaxCost = 0.03;

const double kGapReferenceHorizStepM =
    6371000 * ((kGapReferenceStepM / 111320) * pi) / 180;

List<Waypoint> gapReferenceTrack({double amplitudeM = kGapReferenceAmplitudeM}) {
  final t0 = DateTime.utc(2026, 1, 1);
  final out = <Waypoint>[];
  for (var i = 0; i < kGapReferencePoints; i++) {
    final x = i * kGapReferenceStepM;
    out.add(Waypoint(
      lat: 0,
      lng: x / 111320,
      elevationMetres: 100 +
          kGapReferenceBaseGrade * x +
          amplitudeM * sin(2 * pi * x / kGapReferencePeriodM),
      timestamp: t0.add(Duration(seconds: i * kGapReferenceStepS)),
    ));
  }
  return out;
}

/// The same walk with no window at all: every point pair graded on its own
/// rise over its own run. This is what the runner actually spent, and what a
/// window can only approximate — a window wider than the terrain averages the
/// climbs and the drops together and hands back a flatter course than the one
/// underfoot.
double gapReferenceTruthSecPerKm(List<Waypoint> track) {
  var adjDistM = 0.0;
  for (var i = 1; i < track.length; i++) {
    final rise =
        (track[i].elevationMetres ?? 0) - (track[i - 1].elevationMetres ?? 0);
    adjDistM +=
        kGapReferenceHorizStepM * gradeFactor(rise / kGapReferenceHorizStepM);
  }
  final timeS = (track.length - 1) * kGapReferenceStepS;
  return timeS / (adjDistM / 1000);
}

void main() {
  group('Minetti model', () {
    test('cost at flat is the cached flat constant', () {
      expect(minettiCostAtGrade(0), minettiFlatCost);
      expect(gradeFactor(0), 1);
    });

    test('uphill costs more than flat, downhill (gentle) costs less', () {
      expect(gradeFactor(0.1), greaterThan(1));
      expect(gradeFactor(-0.1), lessThan(1));
    });

    test('grade is clamped to Minetti valid range', () {
      expect(gradeFactor(0.9), gradeFactor(maxGrade));
      expect(gradeFactor(-0.9), gradeFactor(-maxGrade));
    });
  });

  group('gradeAdjustedPaceSecPerKm', () {
    test('flat run: GAP equals raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 0);
      expect(gradeAdjustedPaceSecPerKm(track), 200);
    });

    test('uphill run: GAP is faster than raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10);
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, lessThan(200));
    });

    test('descent run: GAP is slower than raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: -10);
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, greaterThan(200));
    });

    test('no elevation data: GAP is null', () {
      final track =
          gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10, withEle: false);
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });

    test('no timestamps: GAP is null', () {
      final track =
          gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10, withTs: false);
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });

    test('too few points: GAP is null', () {
      expect(gradeAdjustedPaceSecPerKm([]), isNull);
      expect(
        gradeAdjustedPaceSecPerKm([
          Waypoint(lat: 40, lng: -100, elevationMetres: 100, timestamp: DateTime.utc(2026)),
        ]),
        isNull,
      );
    });

    test('mixed track with some missing elevation still computes', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10);
      // Null out elevation on a mid-run cluster — those segments fall back to
      // factor 1, but the run as a whole still has grade signal.
      for (var i = 20; i < 25; i++) {
        track[i] = Waypoint(lat: track[i].lat, lng: track[i].lng, timestamp: track[i].timestamp);
      }
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, lessThan(200));
    });

    test('the grade window is longer than the noise floor the gain path discards', () {
      // The finding this window's value exists to answer, stated as the
      // relationship rather than as the number: the largest altitude change
      // `computeElevationGain` throws away as noise, taken over the shortest
      // run a grade is measured across, must not read as a wall.
      //
      // At the 5 m this shipped with, 3 m of noise was a 0.60 grade — past
      // maxGrade, so it clamped, and the factor was 5.396. A rise nothing else
      // in the app is willing to call climb reported an effort-pace 5.4x
      // faster than raw. Nothing gates the rise and nothing can: a threshold
      // big enough to suppress that noise suppresses every real grade below
      // `threshold / window` with it.
      final noiseFloorGrade = kElevationGainMinDeltaM / minSegmentM;
      expect(
        noiseFloorGrade,
        lessThan(maxGrade),
        reason: 'a window of $minSegmentM m makes the $kElevationGainMinDeltaM m '
            'noise floor a $noiseFloorGrade grade, past the steepest the Minetti '
            'fit is defined at',
      );
      expect(
        gradeFactor(noiseFloorGrade),
        lessThan(2.1),
        reason: 'the noise floor alone must not more than double the reported effort',
      );
    });

    test('the reference geometry measures the horizontal step the module does',
        () {
      // Ties the closed form above to the module's own haversine: with no
      // oscillation and no base grade every factor is exactly 1, so the
      // reported GAP is the raw pace that step implies. Without this the truth
      // below would be graded against a distance nothing had checked.
      final flat = gapReferenceTrack(amplitudeM: 0)
          .map((p) => Waypoint(
              lat: p.lat,
              lng: p.lng,
              elevationMetres: 100,
              timestamp: p.timestamp))
          .toList();
      final timeS = (kGapReferencePoints - 1) * kGapReferenceStepS;
      final horizM = kGapReferenceHorizStepM * (kGapReferencePoints - 1);
      expect(gradeAdjustedPaceSecPerKm(flat), (timeS / (horizM / 1000)).round());
    });

    test('the grade window is short enough to keep the reference track', () {
      // The other end of the bracket. The noise-floor test above states the
      // FLOOR — it admits nothing under 19.40 m — and would pass at 200 m, a
      // window long enough to erase the terrain outright. This states the
      // CEILING, as decisions § 992 stated it: on the most oscillating
      // realistic profile measured, the window may not cost more than 3%
      // against the truth.
      //
      // Measured on this fixture, reported against truth 302.611 s/km:
      //   5 m -> 304 (-0.46%)   15 m -> 308 (-1.78%)   20 m -> 311 (-2.77%)
      //   25 m -> 316 (-4.42%)  30 m -> 322 (-6.41%)   200 m -> 426 (-40.78%)
      // so the pair of tests together admits only [19.40 m, 24.97 m]. The 5 m
      // point spacing is what makes the ceiling 24.97 rather than 25: the walk
      // closes a segment on the first pair that clears the window, so what is
      // really bounded is the EFFECTIVE segment, which is the honest bound.
      final track = gapReferenceTrack();
      final truth = gapReferenceTruthSecPerKm(track);
      final reported = gradeAdjustedPaceSecPerKm(track);
      expect(reported, isNotNull);
      final cost = (reported! - truth).abs() / truth;
      expect(
        cost,
        lessThan(kGapReferenceMaxCost),
        reason: 'a $minSegmentM m window reports $reported s/km against a true '
            '${truth.toStringAsFixed(3)} s/km on the reference switchback — '
            '${(cost * 100).toStringAsFixed(2)}% of the climb averaged away',
      );
      expect(
        reported,
        kGapReferenceSPerKm,
        reason: 'the reference track no longer grades to its frozen value: the '
            'window, the fixture or the Minetti fit moved. Re-measure the cost '
            'against truth before updating this number, and update the web and '
            'firmware rails with it',
      );
    });

    test('a track shorter than one window yields no grade-adjusted pace', () {
      // Proof that the walk reads the constant rather than a literal: four
      // quarter-window steps carry elevation and a duration, and still never
      // complete a segment, so there is no grade anyone can vouch for and the
      // helper says so instead of grading the jitter.
      final track =
          gradedTrack(points: 4, stepM: minSegmentM / 4, stepS: 1, gradePct: 10);
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });
  });

  group('non-finite inputs', () {
    test('a non-finite coordinate never throws out of a getter', () {
      // The signature is `int?`. `segHoriz` goes NaN on a bad fix,
      // `NaN < minSegmentM` is false so the walk enters the body, and the old
      // `adjDistM <= 0` guard is false for NaN — so `.round()` was called on a
      // non-finite double, which is an UnsupportedError, raised from inside a
      // widget build. The web twin returned NaN out of a `number | null`.
      final track = [
        Waypoint(
          lat: 51.5,
          lng: -0.1,
          elevationMetres: 10,
          timestamp: DateTime.utc(2026, 1, 1),
        ),
        Waypoint(
          lat: double.nan,
          lng: -0.1,
          elevationMetres: 20,
          timestamp: DateTime.utc(2026, 1, 1, 0, 5),
        ),
        Waypoint(
          lat: 51.5,
          lng: -0.09,
          elevationMetres: 30,
          timestamp: DateTime.utc(2026, 1, 1, 0, 10),
        ),
      ];
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap == null || gap.isFinite, isTrue);
    });

    test('one bad fix does not erase the GAP of the run around it', () {
      // The durable half. A single unusable segment is skipped the way a
      // segment with no timestamps already is, rather than poisoning the
      // accumulator and discarding every good segment in a three-hour ultra.
      final good = gradedTrack(
        points: 41,
        stepM: minSegmentM * 1.5,
        stepS: 12,
        gradePct: 5,
      );
      final clean = gradeAdjustedPaceSecPerKm(good);
      expect(clean, isNotNull);

      final spoiled = List<Waypoint>.from(good);
      spoiled[20] = Waypoint(
        lat: double.infinity,
        lng: good[20].lng,
        elevationMetres: good[20].elevationMetres,
        timestamp: good[20].timestamp,
      );
      final withBadFix = gradeAdjustedPaceSecPerKm(spoiled);
      expect(withBadFix, isNotNull,
          reason: 'one bad fix must not erase the whole run');
      expect(
        (withBadFix! - clean!).abs() < clean * 0.1,
        isTrue,
        reason: 'a single skipped segment should barely move GAP: '
            '\$clean -> \$withBadFix',
      );
    });

    test('a non-finite altitude is not a measured grade', () {
      // The other way in: `be - ae` is NaN, `gradeFactor` clamps neither bound
      // of a NaN, and the Minetti fit of NaN is NaN. The segment is skipped,
      // so it also does not count as having SEEN elevation.
      final base = gradedTrack(
        points: 3,
        stepM: minSegmentM * 1.5,
        stepS: 12,
        gradePct: 0,
      );
      final track = [
        for (final w in base)
          Waypoint(
            lat: w.lat,
            lng: w.lng,
            elevationMetres: double.nan,
            timestamp: w.timestamp,
          ),
      ];
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });
  });
}
