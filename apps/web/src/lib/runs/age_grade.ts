import {
	AGE_GRADE_DISTANCES,
	AGE_GRADE_AGE_MIN,
	AGE_GRADE_AGE_MAX,
	type AgeGradeDistance,
} from './age_grade_tables';

/**
 * Age grading: scores a race performance against the world-standard time for
 * the runner's exact age and sex, so a 68-year-old's marathon and a 24-year-old's
 * are comparable on one 0–100 % scale. The metric the masters audience lives by.
 *
 * We only had it for parkrun imports (the scraped `metadata.age_grade` string).
 * This computes it for any standard-distance race when the runner's DOB, a
 * standard distance, and a duration are known and no scraped value exists.
 *
 *   agePct = openStandardSec / (durationSec × ageFactor) × 100
 *
 * `openStandardSec` is the open-class (world-standard) time for the distance and
 * sex; `ageFactor` (≤ 1) is the single-year age factor. A runner who matches the
 * age standard scores 100 %; world-record-grade efforts exceed it. Factors +
 * standards come from the embedded USATF-MLDR 2025 tables (`age_grade_tables.ts`).
 *
 * Twin of `apps/mobile_android/lib/age_grade.dart` — keep the algorithm,
 * constants, edge cases, and test count in lockstep.
 */

export type AgeGradeSex = 'male' | 'female';

/**
 * Max relative gap between a run's distance and a standard distance for the run
 * to be age-graded against it. Age grading is defined only at the standard
 * distances; GPS over-reads a certified course by ~1 %, so a small tolerance
 * catches real races without grading a 5.4 km jog as a 5 km. The standard
 * distances are spaced widely enough (nearest pair: 8 km vs 5 mi, 0.6 % apart,
 * disambiguated by nearest-match) that 2 % never produces an ambiguous match.
 */
export const AGE_GRADE_DISTANCE_TOLERANCE = 0.02;

export interface AgeGradeResult {
	/** Age grade as a percentage, e.g. 72.4. Not capped — WR-grade efforts exceed 100. */
	percent: number;
	/** Matched standard distance the grade is computed against. */
	distance: AgeGradeDistance;
	/** Whole-years age used for the factor lookup. */
	age: number;
	/** Age factor (≤ 1) applied. */
	factor: number;
}

/**
 * The standard distance closest to `distanceM`, if within
 * `AGE_GRADE_DISTANCE_TOLERANCE`; otherwise null (not a recognised race
 * distance → no age grade).
 */
export function matchStandardDistance(distanceM: number): AgeGradeDistance | null {
	if (!(distanceM > 0)) return null;
	let best: AgeGradeDistance | null = null;
	let bestRel = Infinity;
	for (const d of AGE_GRADE_DISTANCES) {
		const rel = Math.abs(distanceM - d.distanceM) / d.distanceM;
		if (rel < bestRel) {
			bestRel = rel;
			best = d;
		}
	}
	return best != null && bestRel <= AGE_GRADE_DISTANCE_TOLERANCE ? best : null;
}

/**
 * Whole-years age on a given date — "age on race day", which is what age
 * grading uses (not age today). Both args are ISO strings; only the leading
 * `YYYY-MM-DD` is read, so timezones never shift the result. Null if either is
 * unparseable or the date precedes birth.
 */
export function ageOnDate(dobIso: string, onIso: string): number | null {
	const dob = parseYmd(dobIso);
	const on = parseYmd(onIso);
	if (!dob || !on) return null;
	let age = on.y - dob.y;
	if (on.m < dob.m || (on.m === dob.m && on.d < dob.d)) age--;
	return age >= 0 && age < 200 ? age : null;
}

function parseYmd(iso: string): { y: number; m: number; d: number } | null {
	if (typeof iso !== 'string' || iso.length < 10) return null;
	const y = Number(iso.slice(0, 4));
	const m = Number(iso.slice(5, 7));
	const d = Number(iso.slice(8, 10));
	if (iso[4] !== '-' || iso[7] !== '-') return null;
	if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) return null;
	if (m < 1 || m > 12 || d < 1 || d > 31) return null;
	return { y, m, d };
}

/**
 * Age grade for a known distance + duration + whole-years age + sex, or null
 * when it can't be computed: distance not standard, age outside the table
 * (5..99), or a non-positive duration.
 */
export function computeAgeGrade(opts: {
	distanceM: number;
	durationSec: number;
	age: number;
	sex: AgeGradeSex;
}): AgeGradeResult | null {
	const { distanceM, durationSec, age, sex } = opts;
	if (!(durationSec > 0)) return null;
	if (!Number.isFinite(age) || age < AGE_GRADE_AGE_MIN || age > AGE_GRADE_AGE_MAX) return null;
	if (sex !== 'male' && sex !== 'female') return null;
	const distance = matchStandardDistance(distanceM);
	if (!distance) return null;
	const factor = distance.factors[sex][age - AGE_GRADE_AGE_MIN];
	const openStandard = distance.openStandardSec[sex];
	if (!(factor > 0) || !(openStandard > 0)) return null;
	const percent = (openStandard / (durationSec * factor)) * 100;
	return { percent, distance, age, factor };
}

/**
 * Convenience over `computeAgeGrade` that derives age from the runner's DOB and
 * the run's start date. `sex` is null for unset / non-binary, which yields null
 * (age grading has no standard without a binary sex reference).
 */
export function ageGradeForRun(opts: {
	distanceM: number;
	durationSec: number;
	dobIso: string | null | undefined;
	runStartIso: string | null | undefined;
	sex: AgeGradeSex | null | undefined;
}): AgeGradeResult | null {
	const { distanceM, durationSec, dobIso, runStartIso, sex } = opts;
	if (!dobIso || !runStartIso || (sex !== 'male' && sex !== 'female')) return null;
	const age = ageOnDate(dobIso, runStartIso);
	if (age == null) return null;
	return computeAgeGrade({ distanceM, durationSec, age, sex });
}

/** Display string, e.g. `72.4%`. One decimal is the masters convention. */
export function formatAgeGradePercent(percent: number): string {
	return `${percent.toFixed(1)}%`;
}
