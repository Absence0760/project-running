import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	DEFAULT_BODY_WEIGHT_KG,
	ACTIVITY_KCAL_PER_KG_PER_KM,
	estimateRunCalories,
} from './calories';

// ── Default + weight scaling ─────────────────────────────────

test('estimateRunCalories: no weight → uses DEFAULT_BODY_WEIGHT_KG', () => {
	// 5 km × 70 kg × 1 (run) = 350 kcal
	assert.equal(
		estimateRunCalories({ distanceM: 5_000 }),
		350,
	);
});

test('estimateRunCalories: explicit weight scales output proportionally', () => {
	// Weight doubles → calories double (same distance, same activity).
	const a = estimateRunCalories({ distanceM: 5_000, weightKg: 50 });
	const b = estimateRunCalories({ distanceM: 5_000, weightKg: 100 });
	assert.equal(a, 250);
	assert.equal(b, 500);
	// Ratio is exactly 2 (no rounding artifact at this scale).
	assert.equal(b / a, 2);
});

test('estimateRunCalories: null / zero / negative weight falls back to default', () => {
	const ref = estimateRunCalories({ distanceM: 5_000 });
	assert.equal(estimateRunCalories({ distanceM: 5_000, weightKg: null }), ref);
	assert.equal(estimateRunCalories({ distanceM: 5_000, weightKg: 0 }), ref);
	// A negative weight makes no sense — fall back rather than
	// emitting a negative-calorie value that would crash the UI render.
	assert.equal(estimateRunCalories({ distanceM: 5_000, weightKg: -10 }), ref);
});

// ── Activity coefficient ─────────────────────────────────────

test('estimateRunCalories: activity coefficient scales output', () => {
	const run = estimateRunCalories({
		distanceM: 10_000,
		weightKg: 70,
		activityKcalPerKgPerKm: ACTIVITY_KCAL_PER_KG_PER_KM.run,
	});
	const walk = estimateRunCalories({
		distanceM: 10_000,
		weightKg: 70,
		activityKcalPerKgPerKm: ACTIVITY_KCAL_PER_KG_PER_KM.walk,
	});
	assert.equal(run, 700);
	assert.equal(walk, 350); // half of run per the ladder
});

test('estimateRunCalories — stroller burns above run, not below walk (#51)', () => {
	const stroller = estimateRunCalories({
		distanceM: 10_000,
		weightKg: 70,
		activityKcalPerKgPerKm: ACTIVITY_KCAL_PER_KG_PER_KM.stroller,
	});
	// 1.1 coeff → 770 kcal; previously a stroller run fell back to walk (350).
	assert.equal(stroller, 770);
	assert.equal(ACTIVITY_KCAL_PER_KG_PER_KM.stroller, 1.1);
});

test('estimateRunCalories: null / zero activity coefficient falls back to run', () => {
	const explicit = estimateRunCalories({
		distanceM: 5_000,
		weightKg: 70,
		activityKcalPerKgPerKm: ACTIVITY_KCAL_PER_KG_PER_KM.run,
	});
	assert.equal(
		estimateRunCalories({ distanceM: 5_000, weightKg: 70, activityKcalPerKgPerKm: null }),
		explicit,
	);
	assert.equal(
		estimateRunCalories({ distanceM: 5_000, weightKg: 70, activityKcalPerKgPerKm: 0 }),
		explicit,
	);
});

// ── Gender calibration ───────────────────────────────────────

test('estimateRunCalories: omitting gender returns the unmodified (male-curve) value', () => {
	const noGender = estimateRunCalories({ distanceM: 5_000, weightKg: 70 });
	const explicitMale = estimateRunCalories({
		distanceM: 5_000,
		weightKg: 70,
		gender: 'male',
	});
	const explicitNull = estimateRunCalories({
		distanceM: 5_000,
		weightKg: 70,
		gender: null,
	});
	assert.equal(noGender, 350);
	assert.equal(explicitMale, noGender);
	assert.equal(explicitNull, noGender);
});

test('estimateRunCalories: female calibration is ~5% lower than the male curve', () => {
	const male = estimateRunCalories({ distanceM: 10_000, weightKg: 70 });
	const female = estimateRunCalories({
		distanceM: 10_000,
		weightKg: 70,
		gender: 'female',
	});
	assert.ok(female < male, `female (${female}) must be < male (${male})`);
	const ratio = female / male;
	// 0.95 calibration → ratio in [0.94, 0.96] absorbing integer
	// rounding at this scale (700 vs 665).
	assert.ok(
		ratio > 0.94 && ratio < 0.96,
		`female / male ratio out of expected band: ${ratio}`,
	);
});

test('estimateRunCalories: prefer_not_to_say falls back to the unmodified curve', () => {
	// Same reasoning as the training pace calibration ADR §76 —
	// no validated calibration without a stated sex; better to
	// under-prescribe than mis-prescribe.
	const male = estimateRunCalories({ distanceM: 5_000, weightKg: 70 });
	const pnts = estimateRunCalories({
		distanceM: 5_000,
		weightKg: 70,
		gender: 'prefer_not_to_say',
	});
	assert.equal(pnts, male);
});

// ── Edge cases ────────────────────────────────────────────────

test('estimateRunCalories: zero distance → 0 kcal', () => {
	assert.equal(estimateRunCalories({ distanceM: 0, weightKg: 70 }), 0);
});

test('estimateRunCalories: negative distance is clamped to 0 (not a crash)', () => {
	// Defensive — a buggy upstream that passed a negative shouldn't
	// surface as a "burned -300 kcal" badge.
	assert.equal(estimateRunCalories({ distanceM: -5_000, weightKg: 70 }), 0);
});

test('estimateRunCalories: a non-finite distance contributes nothing', () => {
	// A NaN fails every `> 0` test the way a zero does but survives
	// Math.max, so it used to render as "NaN kcal". The Dart twin answered 0
	// for the same NaN and threw outright for an Infinity, inside a getter
	// read during a widget build.
	for (const d of [NaN, Infinity, -Infinity]) {
		assert.equal(estimateRunCalories({ distanceM: d, weightKg: 70 }), 0, `distance ${d}`);
	}
});

test('estimateRunCalories: a non-finite weight falls back to the default', () => {
	const expected = estimateRunCalories({ distanceM: 5_000 });
	for (const w of [NaN, Infinity, -Infinity]) {
		assert.equal(estimateRunCalories({ distanceM: 5_000, weightKg: w }), expected, `weight ${w}`);
	}
});

test('estimateRunCalories: a non-finite activity coefficient falls back to run', () => {
	const expected = estimateRunCalories({ distanceM: 5_000, weightKg: 70 });
	for (const c of [NaN, Infinity, -Infinity]) {
		assert.equal(
			estimateRunCalories({ distanceM: 5_000, weightKg: 70, activityKcalPerKgPerKm: c }),
			expected,
			`coefficient ${c}`,
		);
	}
});

test('estimateRunCalories: an unrepresentable product is no estimate', () => {
	// Every input finite, the product past the double range.
	assert.equal(
		estimateRunCalories({
			distanceM: 1e300,
			weightKg: 1e300,
			activityKcalPerKgPerKm: 1e300,
		}),
		0,
	);
});

test('estimateRunCalories: always returns a finite integer', () => {
	const inputs = [NaN, Infinity, -Infinity, -1, 0, 1, 5_000, 1e300];
	for (const d of inputs) {
		for (const w of inputs) {
			const v = estimateRunCalories({ distanceM: d, weightKg: w });
			assert.ok(Number.isInteger(v), `distance ${d} weight ${w} gave ${v}`);
			assert.ok(v >= 0, `distance ${d} weight ${w} gave ${v}`);
		}
	}
});

test('estimateRunCalories: DEFAULT_BODY_WEIGHT_KG is 70', () => {
	// Pinned because callers reference the constant; if the value
	// changes the run-detail label copy ("Calories kcal (est)") must
	// stay accurate.
	assert.equal(DEFAULT_BODY_WEIGHT_KG, 70);
});
