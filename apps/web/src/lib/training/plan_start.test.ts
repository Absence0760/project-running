import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { nextSundayIso, isSundayIso } from './plan_start';

test('nextSundayIso is a no-op on a Sunday', () => {
	// 2026-06-07 is a Sunday.
	assert.equal(nextSundayIso('2026-06-07'), '2026-06-07');
	assert.equal(isSundayIso('2026-06-07'), true);
});

test('nextSundayIso snaps a midweek date forward to the next Sunday', () => {
	// 2026-06-03 is a Wednesday → 2026-06-07.
	assert.equal(nextSundayIso('2026-06-03'), '2026-06-07');
	assert.equal(isSundayIso('2026-06-03'), false);
});

test('nextSundayIso snaps a Saturday forward one day', () => {
	// 2026-06-06 is a Saturday → 2026-06-07.
	assert.equal(nextSundayIso('2026-06-06'), '2026-06-07');
});

test('nextSundayIso crosses a month boundary', () => {
	// 2026-06-30 is a Tuesday → 2026-07-05 (Sunday).
	assert.equal(nextSundayIso('2026-06-30'), '2026-07-05');
});
