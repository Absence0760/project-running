import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tanakaMaxHr, zoneCutoffsFromMaxHr, defaultZoneCutoffs } from './hr_zones';

test('tanakaMaxHr applies 208 − 0.7×age, rounded', () => {
	assert.equal(tanakaMaxHr(20), 194); // 208 − 14
	assert.equal(tanakaMaxHr(36), 183); // 182.8 → 183
	assert.equal(tanakaMaxHr(60), 166); // 208 − 42
});

test('zoneCutoffsFromMaxHr is 60/70/80/90/100 % rounded', () => {
	assert.deepEqual(zoneCutoffsFromMaxHr(190), [114, 133, 152, 171, 190]);
	assert.deepEqual(zoneCutoffsFromMaxHr(200), [120, 140, 160, 180, 200]);
});

test('defaultZoneCutoffs prefers an explicit max-HR override', () => {
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: 200, ageYears: 60 }), [
		120, 140, 160, 180, 200,
	]);
});

test('defaultZoneCutoffs derives from age (Tanaka) when no override', () => {
	// age 60 → Tanaka 166 → lower ceiling than the legacy 190.
	assert.deepEqual(defaultZoneCutoffs({ ageYears: 60 }), zoneCutoffsFromMaxHr(166));
	// A masters runner's top zone is well below the old 190 default.
	assert.ok(defaultZoneCutoffs({ ageYears: 60 })[4] < 190);
});

test('defaultZoneCutoffs falls back to the legacy 190 ladder', () => {
	assert.deepEqual(defaultZoneCutoffs({}), [114, 133, 152, 171, 190]);
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: null, ageYears: null }), [
		114, 133, 152, 171, 190,
	]);
});

test('defaultZoneCutoffs ignores out-of-range inputs', () => {
	// implausible max HR (sensor-bag garbage) → fall through to age
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: 40, ageYears: 30 }), zoneCutoffsFromMaxHr(tanakaMaxHr(30)));
	// implausible age → fall through to legacy default
	assert.deepEqual(defaultZoneCutoffs({ ageYears: 200 }), [114, 133, 152, 171, 190]);
});
