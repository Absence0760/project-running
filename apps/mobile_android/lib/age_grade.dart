import 'age_grade_tables.dart';

/// Age grading: scores a race performance against the world-standard time for
/// the runner's exact age and sex, so a 68-year-old's marathon and a
/// 24-year-old's are comparable on one 0–100 % scale. The metric the masters
/// audience lives by.
///
/// We only had it for parkrun imports (the scraped `metadata.age_grade`
/// string). This computes it for any standard-distance race when the runner's
/// DOB, a standard distance, and a duration are known and no scraped value
/// exists.
///
///   agePct = openStandardSec / (durationSec × ageFactor) × 100
///
/// `openStandardSec` is the open-class (world-standard) time for the distance
/// and sex; `ageFactor` (≤ 1) is the single-year age factor. A runner who
/// matches the age standard scores 100 %; world-record-grade efforts exceed it.
/// Factors + standards come from the embedded USATF-MLDR 2025 tables
/// (`age_grade_tables.dart`).
///
/// Twin of `apps/web/src/lib/runs/age_grade.ts` — keep the algorithm,
/// constants, edge cases, and test count in lockstep.

/// Max relative gap between a run's distance and a standard distance for the
/// run to be age-graded against it. Age grading is defined only at the standard
/// distances; GPS over-reads a certified course by ~1 %, so a small tolerance
/// catches real races without grading a 5.4 km jog as a 5 km. The standard
/// distances are spaced widely enough (nearest pair: 8 km vs 5 mi, 0.6 % apart,
/// disambiguated by nearest-match) that 2 % never produces an ambiguous match.
const double ageGradeDistanceTolerance = 0.02;

class AgeGradeResult {
  /// Age grade as a percentage, e.g. 72.4. Not capped — WR-grade efforts
  /// exceed 100.
  final double percent;

  /// Matched standard distance the grade is computed against.
  final AgeGradeDistance distance;

  /// Whole-years age used for the factor lookup.
  final int age;

  /// Age factor (≤ 1) applied.
  final double factor;

  const AgeGradeResult({
    required this.percent,
    required this.distance,
    required this.age,
    required this.factor,
  });
}

/// The standard distance closest to [distanceM], if within
/// [ageGradeDistanceTolerance]; otherwise null (not a recognised race distance
/// → no age grade).
AgeGradeDistance? matchStandardDistance(double distanceM) {
  if (!(distanceM > 0)) return null;
  AgeGradeDistance? best;
  double bestRel = double.infinity;
  for (final d in ageGradeDistances) {
    final rel = (distanceM - d.distanceM).abs() / d.distanceM;
    if (rel < bestRel) {
      bestRel = rel;
      best = d;
    }
  }
  return best != null && bestRel <= ageGradeDistanceTolerance ? best : null;
}

/// Whole-years age on a given date — "age on race day", which is what age
/// grading uses (not age today). Both args are ISO strings; only the leading
/// `YYYY-MM-DD` is read, so timezones never shift the result. Null if either is
/// unparseable or the date precedes birth.
int? ageOnDate(String dobIso, String onIso) {
  final dob = _parseYmd(dobIso);
  final on = _parseYmd(onIso);
  if (dob == null || on == null) return null;
  var age = on[0] - dob[0];
  if (on[1] < dob[1] || (on[1] == dob[1] && on[2] < dob[2])) age--;
  return age >= 0 && age < 200 ? age : null;
}

List<int>? _parseYmd(String iso) {
  if (iso.length < 10) return null;
  if (iso[4] != '-' || iso[7] != '-') return null;
  final y = int.tryParse(iso.substring(0, 4));
  final m = int.tryParse(iso.substring(5, 7));
  final d = int.tryParse(iso.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return [y, m, d];
}

/// Age grade for a known distance + duration + whole-years age + sex, or null
/// when it can't be computed: distance not standard, age outside the table
/// (5..99), or a non-positive duration. [sex] is 'male' or 'female'.
AgeGradeResult? computeAgeGrade({
  required double distanceM,
  required double durationSec,
  required int age,
  required String sex,
}) {
  if (!(durationSec > 0)) return null;
  if (age < ageGradeAgeMin || age > ageGradeAgeMax) return null;
  if (sex != 'male' && sex != 'female') return null;
  final distance = matchStandardDistance(distanceM);
  if (distance == null) return null;
  final factors = sex == 'male' ? distance.maleFactors : distance.femaleFactors;
  final factor = factors[age - ageGradeAgeMin];
  final openStandard =
      sex == 'male' ? distance.openStandardSecMale : distance.openStandardSecFemale;
  if (!(factor > 0) || !(openStandard > 0)) return null;
  final percent = (openStandard / (durationSec * factor)) * 100;
  return AgeGradeResult(percent: percent, distance: distance, age: age, factor: factor);
}

/// Convenience over [computeAgeGrade] that derives age from the runner's DOB
/// and the run's start date. [sex] is null for unset / non-binary, which yields
/// null (age grading has no standard without a binary sex reference).
AgeGradeResult? ageGradeForRun({
  required double distanceM,
  required double durationSec,
  required String? dobIso,
  required String? runStartIso,
  required String? sex,
}) {
  if (dobIso == null || runStartIso == null || (sex != 'male' && sex != 'female')) {
    return null;
  }
  final age = ageOnDate(dobIso, runStartIso);
  if (age == null) return null;
  return computeAgeGrade(distanceM: distanceM, durationSec: durationSec, age: age, sex: sex!);
}

/// Display string, e.g. `72.4%`. One decimal is the masters convention.
String formatAgeGradePercent(double percent) => '${percent.toStringAsFixed(1)}%';
