import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	AGE_GRADE_DISTANCE_TOLERANCE,
	matchStandardDistance,
	ageOnDate,
	computeAgeGrade,
	ageGradeForRun,
	formatAgeGradePercent,
} from './age_grade';

/// Mirror of `apps/mobile_android/test/age_grade_test.dart`. Keep in lockstep —
/// the age-grade % shown on web run detail and on mobile run detail both derive
/// from these tables + this formula. Expected numerics are anchored to the
/// embedded USATF-MLDR 2025 factors (male 5k std 12:49 = 769 s; M25 = 1.0,
/// M60 10k = 0.8136; female 5k std 13:54 = 834 s, F35 = 0.9793).

test('matchStandardDistance: exact distances map to their standard', () => {
	assert.equal(matchStandardDistance(5000)?.key, '5k');
	assert.equal(matchStandardDistance(10000)?.key, '10k');
	assert.equal(matchStandardDistance(42195)?.key, '42k');
	// 8000 m is 0.6 % from the 5-mile standard but exact for 8 km — nearest wins.
	assert.equal(matchStandardDistance(8000)?.key, '8k');
});

test('matchStandardDistance: GPS over-read within tolerance still matches', () => {
	assert.equal(matchStandardDistance(5050)?.key, '5k'); // +1.0 %
	assert.equal(matchStandardDistance(21300)?.key, 'hm'); // half-marathon +1.0 %
});

test('matchStandardDistance: distances outside tolerance return null', () => {
	assert.equal(matchStandardDistance(5400), null); // +8 %, between 5k and 6k
	assert.equal(matchStandardDistance(7000), null); // between 6k and 8k, 12 %+ off
	assert.equal(matchStandardDistance(0), null);
	assert.equal(matchStandardDistance(-100), null);
});

test('matchStandardDistance: marathon GPS over-read maps to the marathon', () => {
	assert.equal(matchStandardDistance(42400)?.key, '42k'); // +0.5 %
});

test('ageOnDate: subtracts a year when the birthday has not yet occurred', () => {
	// Born 1980-07-15. On a race 2026-06-04 the birthday has not happened → 45.
	assert.equal(ageOnDate('1980-07-15', '2026-06-04T09:00:00Z'), 45);
	// On a race 2026-08-01 it has → 46.
	assert.equal(ageOnDate('1980-07-15', '2026-08-01T09:00:00Z'), 46);
	// Exactly on the birthday → counts.
	assert.equal(ageOnDate('1980-07-15', '2026-07-15T09:00:00Z'), 46);
});

test('ageOnDate: malformed input returns null', () => {
	assert.equal(ageOnDate('not-a-date', '2026-06-04'), null);
	assert.equal(ageOnDate('1980-07-15', 'nope'), null);
	assert.equal(ageOnDate('1980/07/15', '2026-06-04'), null);
});

test('computeAgeGrade: peak-age performance at the open standard scores 100 %', () => {
	// Male 25 sits in the 1.0-factor band; running the open 5k standard = 100 %.
	const r = computeAgeGrade({ distanceM: 5000, durationSec: 769, age: 25, sex: 'male' });
	assert.ok(r);
	assert.equal(r.distance.key, '5k');
	assert.equal(r.factor, 1);
	assert.ok(Math.abs(r.percent - 100) < 1e-9);
});

test('computeAgeGrade: double the standard time halves the percentage', () => {
	const r = computeAgeGrade({ distanceM: 5000, durationSec: 1538, age: 25, sex: 'male' });
	assert.ok(r);
	assert.ok(Math.abs(r.percent - 50) < 1e-9);
});

test('computeAgeGrade: masters male 10k matches the hand-computed grade', () => {
	// M60 10k factor 0.8136, std 1584 s; 40:00 → 1584/(2400·0.8136)·100.
	const r = computeAgeGrade({ distanceM: 10000, durationSec: 2400, age: 60, sex: 'male' });
	assert.ok(r);
	assert.equal(r.factor, 0.8136);
	assert.ok(Math.abs(r.percent - 81.121) < 0.01);
});

test('computeAgeGrade: masters female 5k matches the hand-computed grade', () => {
	// F35 5k factor 0.9793, std 834 s; 20:00 → 834/(1200·0.9793)·100.
	const r = computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 35, sex: 'female' });
	assert.ok(r);
	assert.equal(r.factor, 0.9793);
	assert.ok(Math.abs(r.percent - 70.969) < 0.01);
});

test('computeAgeGrade: returns null outside its domain', () => {
	assert.equal(computeAgeGrade({ distanceM: 5400, durationSec: 1200, age: 40, sex: 'male' }), null);
	assert.equal(computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 4, sex: 'male' }), null);
	assert.equal(computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 100, sex: 'male' }), null);
	assert.equal(computeAgeGrade({ distanceM: 5000, durationSec: 0, age: 40, sex: 'male' }), null);
	// @ts-expect-error non-binary / unset sex has no standard
	assert.equal(computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 40, sex: 'nonbinary' }), null);
});

test('ageGradeForRun: end-to-end from DOB + run start, null when sex unknown', () => {
	const r = ageGradeForRun({
		distanceM: 5000,
		durationSec: 769,
		dobIso: '2000-01-01',
		runStartIso: '2026-06-04T09:00:00Z', // age 26, still 1.0 band
		sex: 'male',
	});
	assert.ok(r);
	assert.ok(Math.abs(r.percent - 100) < 1e-9);
	assert.equal(formatAgeGradePercent(r.percent), '100.0%');
	assert.equal(
		ageGradeForRun({ distanceM: 5000, durationSec: 769, dobIso: '2000-01-01', runStartIso: '2026-06-04', sex: null }),
		null,
	);
	assert.equal(
		ageGradeForRun({ distanceM: 5000, durationSec: 769, dobIso: null, runStartIso: '2026-06-04', sex: 'male' }),
		null,
	);
	assert.ok(AGE_GRADE_DISTANCE_TOLERANCE > 0);
});
