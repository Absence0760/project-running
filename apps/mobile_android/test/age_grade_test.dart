import 'package:flutter_test/flutter_test.dart';

import '../lib/age_grade.dart';

/// Mirror of `apps/web/src/lib/runs/age_grade.test.ts`. Keep in lockstep — the
/// age-grade % shown on mobile run detail and on web run detail both derive
/// from these tables + this formula. Expected numerics are anchored to the
/// embedded USATF-MLDR 2025 factors (male 5k std 12:49 = 769 s; M25 = 1.0,
/// M60 10k = 0.8136; female 5k std 13:54 = 834 s, F35 = 0.9793).

void main() {
  test('matchStandardDistance: exact distances map to their standard', () {
    expect(matchStandardDistance(5000)?.key, '5k');
    expect(matchStandardDistance(10000)?.key, '10k');
    expect(matchStandardDistance(42195)?.key, '42k');
    // 8000 m is 0.6 % from the 5-mile standard but exact for 8 km — nearest wins.
    expect(matchStandardDistance(8000)?.key, '8k');
  });

  test('matchStandardDistance: GPS over-read within tolerance still matches', () {
    expect(matchStandardDistance(5050)?.key, '5k'); // +1.0 %
    expect(matchStandardDistance(21300)?.key, 'hm'); // half-marathon +1.0 %
  });

  test('matchStandardDistance: distances outside tolerance return null', () {
    expect(matchStandardDistance(5400), null); // +8 %, between 5k and 6k
    expect(matchStandardDistance(7000), null); // between 6k and 8k, 12 %+ off
    expect(matchStandardDistance(0), null);
    expect(matchStandardDistance(-100), null);
  });

  test('matchStandardDistance: marathon GPS over-read maps to the marathon', () {
    expect(matchStandardDistance(42400)?.key, '42k'); // +0.5 %
  });

  test('ageOnDate: subtracts a year when the birthday has not yet occurred', () {
    // Born 1980-07-15. On a race 2026-06-04 the birthday has not happened → 45.
    expect(ageOnDate('1980-07-15', '2026-06-04T09:00:00Z'), 45);
    // On a race 2026-08-01 it has → 46.
    expect(ageOnDate('1980-07-15', '2026-08-01T09:00:00Z'), 46);
    // Exactly on the birthday → counts.
    expect(ageOnDate('1980-07-15', '2026-07-15T09:00:00Z'), 46);
  });

  test('ageOnDate: malformed input returns null', () {
    expect(ageOnDate('not-a-date', '2026-06-04'), null);
    expect(ageOnDate('1980-07-15', 'nope'), null);
    expect(ageOnDate('1980/07/15', '2026-06-04'), null);
  });

  test('computeAgeGrade: peak-age performance at the open standard scores 100 %', () {
    // Male 25 sits in the 1.0-factor band; running the open 5k standard = 100 %.
    final r = computeAgeGrade(distanceM: 5000, durationSec: 769, age: 25, sex: 'male');
    expect(r, isNotNull);
    expect(r!.distance.key, '5k');
    expect(r.factor, 1.0);
    expect((r.percent - 100).abs() < 1e-9, true);
  });

  test('computeAgeGrade: double the standard time halves the percentage', () {
    final r = computeAgeGrade(distanceM: 5000, durationSec: 1538, age: 25, sex: 'male');
    expect(r, isNotNull);
    expect((r!.percent - 50).abs() < 1e-9, true);
  });

  test('computeAgeGrade: masters male 10k matches the hand-computed grade', () {
    // M60 10k factor 0.8136, std 1584 s; 40:00 → 1584/(2400·0.8136)·100.
    final r = computeAgeGrade(distanceM: 10000, durationSec: 2400, age: 60, sex: 'male');
    expect(r, isNotNull);
    expect(r!.factor, 0.8136);
    expect((r.percent - 81.121).abs() < 0.01, true);
  });

  test('computeAgeGrade: masters female 5k matches the hand-computed grade', () {
    // F35 5k factor 0.9793, std 834 s; 20:00 → 834/(1200·0.9793)·100.
    final r = computeAgeGrade(distanceM: 5000, durationSec: 1200, age: 35, sex: 'female');
    expect(r, isNotNull);
    expect(r!.factor, 0.9793);
    expect((r.percent - 70.969).abs() < 0.01, true);
  });

  test('computeAgeGrade: returns null outside its domain', () {
    expect(computeAgeGrade(distanceM: 5400, durationSec: 1200, age: 40, sex: 'male'), null);
    expect(computeAgeGrade(distanceM: 5000, durationSec: 1200, age: 4, sex: 'male'), null);
    expect(computeAgeGrade(distanceM: 5000, durationSec: 1200, age: 100, sex: 'male'), null);
    expect(computeAgeGrade(distanceM: 5000, durationSec: 0, age: 40, sex: 'male'), null);
    // non-binary / unset sex has no standard
    expect(computeAgeGrade(distanceM: 5000, durationSec: 1200, age: 40, sex: 'nonbinary'), null);
  });

  test('ageGradeForRun: end-to-end from DOB + run start, null when sex unknown', () {
    final r = ageGradeForRun(
      distanceM: 5000,
      durationSec: 769,
      dobIso: '2000-01-01',
      runStartIso: '2026-06-04T09:00:00Z', // age 26, still 1.0 band
      sex: 'male',
    );
    expect(r, isNotNull);
    expect((r!.percent - 100).abs() < 1e-9, true);
    expect(formatAgeGradePercent(r.percent), '100.0%');
    expect(
      ageGradeForRun(distanceM: 5000, durationSec: 769, dobIso: '2000-01-01', runStartIso: '2026-06-04', sex: null),
      null,
    );
    expect(
      ageGradeForRun(distanceM: 5000, durationSec: 769, dobIso: null, runStartIso: '2026-06-04', sex: 'male'),
      null,
    );
    expect(ageGradeDistanceTolerance > 0, true);
  });
}
