import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	NUMERIC_LIMITS,
	NUMERIC_LIMIT_COLUMNS,
	checkNumericLimit,
	numericBoundsIn
} from './numeric_limits.js';
import { BODY_WEIGHT_MAX_KG, BODY_WEIGHT_MIN_KG, kgToDisplay } from '../format/weight.js';

// That each bound EQUALS the CHECK it names is proved by
// `scripts/check_shared_constants.mjs`, which reads the migrations. What is
// left to pin here is the shape of the registry and the grading around it.

test('every limit names the column it is enforced by', () => {
	assert.deepEqual(Object.keys(NUMERIC_LIMITS).sort(), Object.keys(NUMERIC_LIMIT_COLUMNS).sort());
	for (const qualified of Object.values(NUMERIC_LIMIT_COLUMNS)) {
		assert.match(qualified, /^[a-z_]+\.[a-z_]+$/);
	}
});

test('a value inside the bound, and each edge, is ok', () => {
	const limit = NUMERIC_LIMITS.checkpointBodyWeightKg;
	assert.equal(checkNumericLimit(limit, 70), 'ok');
	assert.equal(checkNumericLimit(limit, limit.min), 'ok');
	assert.equal(checkNumericLimit(limit, limit.max), 'ok');
});

test('a value outside the bound says WHICH side it fell off', () => {
	const limit = NUMERIC_LIMITS.checkpointBodyWeightKg;
	assert.equal(checkNumericLimit(limit, 19.99), 'below');
	assert.equal(checkNumericLimit(limit, 400.01), 'above');
});

// The defect this registry exists for: 600 kg, and the same weight typed as
// 1200 lb, both reached the column and came back as a raw 23514.
test('the body-metrics ceiling rejects 600 kg and the pounds that convert past it', () => {
	const limit = NUMERIC_LIMITS.bodyMetricsWeightKg;
	assert.equal(checkNumericLimit(limit, 600), 'above');
	assert.equal(checkNumericLimit(limit, 1200 / 2.2046226218), 'above');
	assert.equal(checkNumericLimit(limit, 90), 'ok');
});

// `min="0"` against a `> 0` CHECK admitted exactly the one value it rejects.
test('zero is below the bound of a column whose CHECK is exclusive', () => {
	assert.equal(checkNumericLimit(NUMERIC_LIMITS.bodyMetricsWeightKg, 0), 'below');
	assert.equal(checkNumericLimit(NUMERIC_LIMITS.profileHeightCm, 0), 'below');
	assert.equal(checkNumericLimit(NUMERIC_LIMITS.gymSetRpe, 0), 'ok');
});

test('a non-finite value is invalid rather than silently in range', () => {
	assert.equal(checkNumericLimit(NUMERIC_LIMITS.gymSetRpe, NaN), 'invalid');
	assert.equal(checkNumericLimit(NUMERIC_LIMITS.gymSetRpe, Infinity), 'invalid');
});

test('a bound restated in another unit rounds inward, so the shown number is itself legal', () => {
	const inLbs = numericBoundsIn(NUMERIC_LIMITS.checkpointBodyWeightKg, (kg) => kgToDisplay(kg, 'lbs'));
	// 20 kg is 44.0924 lbs and 400 kg is 881.849 lbs.
	assert.equal(inLbs.min, 44.1);
	assert.equal(inLbs.max, 881.8);
	const limit = NUMERIC_LIMITS.checkpointBodyWeightKg;
	assert.equal(checkNumericLimit(limit, inLbs.min / 2.2046226218), 'ok');
	assert.equal(checkNumericLimit(limit, inLbs.max / 2.2046226218), 'ok');
});

test('with no conversion the display bound is the bound', () => {
	assert.deepEqual(numericBoundsIn(NUMERIC_LIMITS.routineRestS), { min: 0, max: 3600 });
});

// The narrowing rule: a field may show something tighter than the column, never
// looser. `weight.ts`'s human range is the one narrowing shipped today.
test('the plausible human body-weight range sits inside the column bound', () => {
	const limit = NUMERIC_LIMITS.bodyMetricsWeightKg;
	assert.equal(checkNumericLimit(limit, BODY_WEIGHT_MIN_KG), 'ok');
	assert.equal(checkNumericLimit(limit, BODY_WEIGHT_MAX_KG), 'ok');
	assert.ok(BODY_WEIGHT_MIN_KG >= limit.min);
	assert.ok(BODY_WEIGHT_MAX_KG <= limit.max);
});
