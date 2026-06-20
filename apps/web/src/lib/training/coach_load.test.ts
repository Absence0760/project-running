import { test } from 'node:test';
import assert from 'node:assert/strict';
import { acwr, injuryRiskBand, loadTrend } from './coach_load';

// ─────────────────────── acwr ───────────────────────

test('acwr: ratio is acute / chronic', () => {
	assert.equal(acwr(100, 80), 1.25);
});

test('acwr: zero chronic base returns 0 (no division)', () => {
	assert.equal(acwr(50, 0), 0);
});

test('acwr: non-finite inputs return 0', () => {
	assert.equal(acwr(NaN, 80), 0);
	assert.equal(acwr(100, NaN), 0);
});

// ─────────────────────── injuryRiskBand (band edges) ───────────────────────

test('injuryRiskBand: zero chronic base is insufficient, not low', () => {
	assert.equal(injuryRiskBand(40, 0), 'insufficient');
});

test('injuryRiskBand: just below 0.8 is low', () => {
	// 0.79 ratio: acute 79, chronic 100
	assert.equal(injuryRiskBand(79, 100), 'low');
});

test('injuryRiskBand: exactly 0.8 is optimal (low is < 0.8)', () => {
	assert.equal(injuryRiskBand(80, 100), 'optimal');
});

test('injuryRiskBand: 1.0 is optimal', () => {
	assert.equal(injuryRiskBand(100, 100), 'optimal');
});

test('injuryRiskBand: exactly 1.3 is elevated (optimal is < 1.3)', () => {
	assert.equal(injuryRiskBand(130, 100), 'elevated');
});

test('injuryRiskBand: just below 1.5 is elevated', () => {
	assert.equal(injuryRiskBand(149, 100), 'elevated');
});

test('injuryRiskBand: exactly 1.5 is high', () => {
	assert.equal(injuryRiskBand(150, 100), 'high');
});

test('injuryRiskBand: a big spike is high', () => {
	assert.equal(injuryRiskBand(220, 100), 'high');
});

// ─────────────────────── loadTrend ───────────────────────

test('loadTrend: >15% above chronic is ramping', () => {
	assert.equal(loadTrend(120, 100), 'ramping');
});

test('loadTrend: >15% below chronic is tapering', () => {
	assert.equal(loadTrend(80, 100), 'tapering');
});

test('loadTrend: within the deadband is steady', () => {
	assert.equal(loadTrend(100, 100), 'steady');
});

test('loadTrend: no chronic base is steady (one week is not a trend)', () => {
	assert.equal(loadTrend(50, 0), 'steady');
});
