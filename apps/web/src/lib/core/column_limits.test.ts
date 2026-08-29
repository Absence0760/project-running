import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	COLUMN_LIMITS,
	lengthLimit,
	valueLimit,
	withinValueLimit,
	type ColumnLimitKey
} from './column_limits.js';

test('every key names a table and a column', () => {
	// The key IS the locator the migration-replaying guard resolves, so a key
	// that is not `<table>.<column>` is a bound nothing can check.
	for (const key of Object.keys(COLUMN_LIMITS)) {
		assert.match(key, /^[a-z_]+\.[a-z_]+$/, key);
	}
});

test('every value limit is a non-empty inclusive range', () => {
	for (const [key, limit] of Object.entries(COLUMN_LIMITS)) {
		if (limit.kind !== 'value') continue;
		assert.ok(Number.isFinite(limit.min) && Number.isFinite(limit.max), key);
		assert.ok(limit.min < limit.max, `${key}: min must be below max`);
	}
});

test('every length limit is a positive integer', () => {
	for (const [key, limit] of Object.entries(COLUMN_LIMITS)) {
		if (limit.kind !== 'length') continue;
		assert.ok(Number.isInteger(limit.max) && limit.max > 0, key);
	}
});

test('valueLimit and lengthLimit refuse the other kind', () => {
	assert.throws(() => lengthLimit('body_metrics.weight_kg'));
	assert.throws(() => valueLimit('club_posts.body'));
});

test('withinValueLimit is inclusive at both ends', () => {
	const { min, max } = valueLimit('body_metrics.weight_kg');
	assert.equal(withinValueLimit('body_metrics.weight_kg', min), true);
	assert.equal(withinValueLimit('body_metrics.weight_kg', max), true);
	assert.equal(withinValueLimit('body_metrics.weight_kg', min - 0.01), false);
	assert.equal(withinValueLimit('body_metrics.weight_kg', max + 0.01), false);
});

test('withinValueLimit: a non-finite value is outside every range', () => {
	for (const key of Object.keys(COLUMN_LIMITS) as ColumnLimitKey[]) {
		if (COLUMN_LIMITS[key].kind !== 'value') continue;
		assert.equal(withinValueLimit(key, NaN), false, key);
		assert.equal(withinValueLimit(key, Infinity), false, key);
		assert.equal(withinValueLimit(key, -Infinity), false, key);
	}
});
