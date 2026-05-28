import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { relativeAge } from './pr_recency';

const NOW = Date.parse('2026-05-01T12:00:00Z');

test('relativeAge — today / yesterday / days', () => {
	assert.equal(relativeAge('2026-05-01T08:00:00Z', NOW), 'today');
	assert.equal(relativeAge('2026-04-30T08:00:00Z', NOW), 'yesterday');
	assert.equal(relativeAge('2026-04-28T08:00:00Z', NOW), '3 days ago');
});

test('relativeAge — weeks / months / years', () => {
	assert.equal(relativeAge('2026-04-20T12:00:00Z', NOW), 'a week ago');
	assert.equal(relativeAge('2026-04-01T12:00:00Z', NOW), '4 weeks ago');
	assert.equal(relativeAge('2026-02-20T12:00:00Z', NOW), '2 months ago');
	assert.equal(relativeAge('2024-04-15T12:00:00Z', NOW), '2 years ago');
	assert.equal(relativeAge('2025-04-15T12:00:00Z', NOW), 'a year ago');
});

test('relativeAge — invalid date yields empty string', () => {
	assert.equal(relativeAge('not-a-date', NOW), '');
});
