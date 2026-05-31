import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatRelativeTime, formatDuration, formatDate, formatDateShort } from './time';

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

test('formatDuration — under an hour is M:SS', () => {
	assert.equal(formatDuration(0), '0:00');
	assert.equal(formatDuration(5), '0:05');
	assert.equal(formatDuration(65), '1:05');
	assert.equal(formatDuration(599), '9:59');
});

test('formatDuration — an hour or more is H:MM:SS', () => {
	assert.equal(formatDuration(3600), '1:00:00');
	assert.equal(formatDuration(3661), '1:01:01');
	assert.equal(formatDuration(36000 + 59 * 60 + 59), '10:59:59');
});

test('formatDate / formatDateShort — render the date, short omits the year', () => {
	const iso = '2026-03-14T08:00:00Z';
	assert.match(formatDate(iso), /2026/);
	assert.doesNotMatch(formatDateShort(iso), /2026/);
});
