import assert from 'node:assert/strict';
import { test } from 'node:test';

import { gearWear, GEAR_WEAR_DUE_FRACTION } from './gear_wear';

test('gearWear: no target → untracked, null fraction', () => {
	assert.deepEqual(gearWear(500_000, null), { status: 'untracked', fraction: null });
	assert.deepEqual(gearWear(500_000, 0), { status: 'untracked', fraction: null });
	assert.deepEqual(gearWear(500_000, undefined), { status: 'untracked', fraction: null });
});

test('gearWear: well within target → ok', () => {
	const w = gearWear(300_000, 800_000); // 37.5%
	assert.equal(w.status, 'ok');
	assert.ok(Math.abs((w.fraction ?? 0) - 0.375) < 1e-9);
});

test('gearWear: at the due threshold → due', () => {
	const w = gearWear(GEAR_WEAR_DUE_FRACTION * 800_000, 800_000);
	assert.equal(w.status, 'due');
});

test('gearWear: just below the due threshold → ok', () => {
	const w = gearWear((GEAR_WEAR_DUE_FRACTION - 0.01) * 800_000, 800_000);
	assert.equal(w.status, 'ok');
});

test('gearWear: at target → worn', () => {
	assert.equal(gearWear(800_000, 800_000).status, 'worn');
});

test('gearWear: over target → worn, fraction > 1 (uncapped)', () => {
	const w = gearWear(960_000, 800_000); // 120%
	assert.equal(w.status, 'worn');
	assert.ok(Math.abs((w.fraction ?? 0) - 1.2) < 1e-9);
});

test('gearWear: zero / negative / non-finite total clamps to 0 → ok', () => {
	assert.equal(gearWear(0, 800_000).status, 'ok');
	assert.equal(gearWear(-100, 800_000).status, 'ok');
	assert.equal(gearWear(Number.NaN, 800_000).status, 'ok');
});

test('gearWear: non-finite / negative target → untracked', () => {
	assert.equal(gearWear(500_000, Number.NaN).status, 'untracked');
	assert.equal(gearWear(500_000, -10).status, 'untracked');
});
