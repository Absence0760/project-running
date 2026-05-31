import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatRelativeTime } from './time';

const NOW = Date.parse('2026-05-30T12:00:00Z');

test('formatRelativeTime — under a minute is "just now"', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:59:30Z', NOW), 'just now');
	assert.equal(formatRelativeTime('2026-05-30T12:00:00Z', NOW), 'just now');
});

test('formatRelativeTime — minutes', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:59:00Z', NOW), '1m ago');
	assert.equal(formatRelativeTime('2026-05-30T11:30:00Z', NOW), '30m ago');
	assert.equal(formatRelativeTime('2026-05-30T11:01:00Z', NOW), '59m ago');
});

test('formatRelativeTime — hours', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:00:00Z', NOW), '1h ago');
	assert.equal(formatRelativeTime('2026-05-30T09:00:00Z', NOW), '3h ago');
	assert.equal(formatRelativeTime('2026-05-29T13:00:00Z', NOW), '23h ago');
});

test('formatRelativeTime — days under 30', () => {
	assert.equal(formatRelativeTime('2026-05-29T12:00:00Z', NOW), '1d ago');
	assert.equal(formatRelativeTime('2026-05-25T12:00:00Z', NOW), '5d ago');
	assert.equal(formatRelativeTime('2026-05-01T12:00:00Z', NOW), '29d ago');
});

test('formatRelativeTime — 30 days or older falls back to a dated label with the year', () => {
	const out = formatRelativeTime('2026-01-01T12:00:00Z', NOW);
	assert.doesNotMatch(out, /ago|just now/);
	assert.match(out, /2026/);
});
