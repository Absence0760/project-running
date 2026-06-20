import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recapPeriodLabel } from './recap_period_label';

test('recapPeriodLabel: year passes through', () => {
	assert.equal(recapPeriodLabel('year', '2026'), '2026');
});

test('recapPeriodLabel: month renders an English month + year', () => {
	assert.equal(recapPeriodLabel('month', '2026-03'), 'March 2026');
	assert.equal(recapPeriodLabel('month', '2026-12'), 'December 2026');
});

test('recapPeriodLabel: malformed month key falls back to the raw key', () => {
	assert.equal(recapPeriodLabel('month', 'nonsense'), 'nonsense');
	assert.equal(recapPeriodLabel('month', '2026-13'), '2026-13');
});
