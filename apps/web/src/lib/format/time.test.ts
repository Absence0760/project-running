import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	formatRelativeTime,
	formatDuration,
	formatDate,
	formatDateShort,
	setActiveFormatLocale,
} from './time';

const NOW = Date.parse('2026-05-30T12:00:00Z');

// `en` is passed explicitly so the assertions are deterministic regardless
// of the test runner's default ICU locale. `narrow` + numeric:'always'
// reproduces the prior compact form; the sub-minute case reads "now".
test('formatRelativeTime — under a minute reads "now"', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:59:30Z', NOW, 'en'), 'now');
	assert.equal(formatRelativeTime('2026-05-30T12:00:00Z', NOW, 'en'), 'now');
});

test('formatRelativeTime — minutes', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:59:00Z', NOW, 'en'), '1m ago');
	assert.equal(formatRelativeTime('2026-05-30T11:30:00Z', NOW, 'en'), '30m ago');
	assert.equal(formatRelativeTime('2026-05-30T11:01:00Z', NOW, 'en'), '59m ago');
});

test('formatRelativeTime — hours', () => {
	assert.equal(formatRelativeTime('2026-05-30T11:00:00Z', NOW, 'en'), '1h ago');
	assert.equal(formatRelativeTime('2026-05-30T09:00:00Z', NOW, 'en'), '3h ago');
	assert.equal(formatRelativeTime('2026-05-29T13:00:00Z', NOW, 'en'), '23h ago');
});

test('formatRelativeTime — days under 30 keep the "Nd ago" shape (not "yesterday")', () => {
	assert.equal(formatRelativeTime('2026-05-29T12:00:00Z', NOW, 'en'), '1d ago');
	assert.equal(formatRelativeTime('2026-05-25T12:00:00Z', NOW, 'en'), '5d ago');
	assert.equal(formatRelativeTime('2026-05-01T12:00:00Z', NOW, 'en'), '29d ago');
});

test('formatRelativeTime — 30 days or older falls back to a dated label with the year', () => {
	const out = formatRelativeTime('2026-01-01T12:00:00Z', NOW, 'en');
	assert.doesNotMatch(out, /ago|now/);
	assert.match(out, /2026/);
});

test('formatRelativeTime — localises to the given locale (W-7)', () => {
	assert.equal(formatRelativeTime('2026-05-30T12:00:00Z', NOW, 'de'), 'jetzt');
	assert.match(formatRelativeTime('2026-05-30T11:55:00Z', NOW, 'de'), /vor 5/);
	assert.match(formatRelativeTime('2026-05-30T09:00:00Z', NOW, 'de'), /vor 3/);
	// 30-day fallback honours the locale too (German month name).
	assert.match(formatRelativeTime('2026-01-01T12:00:00Z', NOW, 'de'), /2026/);
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

test('formatDate/formatDateShort follow the active format locale set by the runtime (W-12)', () => {
	const iso = '2026-03-14T08:00:00Z';
	try {
		setActiveFormatLocale('de');
		assert.match(formatDate(iso), /Mär/, 'German short month');
		assert.match(formatDateShort(iso), /Mär/);
		// relative-time's 30-day fallback follows it too
		assert.match(formatRelativeTime(iso, Date.parse('2026-06-01T00:00:00Z')), /Mär/);
		setActiveFormatLocale('en');
		assert.match(formatDate(iso), /Mar/);
		// an explicit locale argument still overrides the active default
		assert.match(formatDate(iso, 'de'), /Mär/);
	} finally {
		setActiveFormatLocale(undefined); // reset so other tests see the host default
	}
});
