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

test('formatDuration — a fractional projection rounds to a whole second field', () => {
	// The live cut-off card feeds a projected arrival / margin straight in, and
	// those are not integers. An unrounded remainder used to reach the seconds
	// field verbatim (`1:16:8.399999999999636`).
	assert.equal(formatDuration(4568.4), '1:16:08');
	assert.equal(formatDuration(2631.6000000000004), '43:52');
	assert.equal(formatDuration(59.6), '1:00');
	assert.equal(formatDuration(3599.5), '1:00:00');
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

// ─────────── date-only strings are calendar dates, not instants ───────────
//
// `new Date('2026-11-15')` is UTC midnight per ECMA-262, so rendering it
// through a local-time formatter showed the day before everywhere west of
// Greenwich — a race listed on the 15th read as the 14th across the Americas.
// The runner sets the timezone per case so these hold on any CI host.

function withTz<T>(tz: string, fn: () => T): T {
	const prior = process.env.TZ;
	process.env.TZ = tz;
	try {
		return fn();
	} finally {
		if (prior === undefined) delete process.env.TZ;
		else process.env.TZ = prior;
	}
}

test('a date-only string renders its own calendar day in every timezone', () => {
	// Spanning the full offset range, both signs, including the extremes.
	for (const tz of [
		'Pacific/Midway', // UTC-11
		'America/Los_Angeles',
		'America/New_York',
		'UTC',
		'Europe/Berlin',
		'Asia/Tokyo',
		'Pacific/Kiritimati', // UTC+14
	]) {
		withTz(tz, () => {
			assert.equal(formatDate('2026-11-15', 'en'), 'Nov 15, 2026', tz);
			assert.equal(formatDateShort('2026-11-15', 'en'), 'Nov 15', tz);
		});
	}
});

test('a date-only string on a month and year boundary does not roll backwards', () => {
	withTz('America/New_York', () => {
		assert.equal(formatDate('2026-01-01', 'en'), 'Jan 1, 2026');
		assert.equal(formatDate('2026-03-01', 'en'), 'Mar 1, 2026');
		// A leap day is the case where a backwards roll lands on a date that
		// exists in one year and not the next.
		assert.equal(formatDate('2028-02-29', 'en'), 'Feb 29, 2028');
	});
});

test('a full timestamp keeps its timezone conversion', () => {
	// The other half of the contract, and the one a "simplification" would
	// break: an instant late in the UTC day genuinely belongs to the next
	// calendar day east of Greenwich, and to the same one west of it.
	const lateUtc = '2026-11-15T23:30:00Z';
	withTz('Asia/Tokyo', () => assert.equal(formatDate(lateUtc, 'en'), 'Nov 16, 2026'));
	withTz('America/New_York', () => assert.equal(formatDate(lateUtc, 'en'), 'Nov 15, 2026'));

	// And an instant early in the UTC day belongs to the previous day west of it.
	const earlyUtc = '2026-11-15T02:30:00Z';
	withTz('America/New_York', () => assert.equal(formatDate(earlyUtc, 'en'), 'Nov 14, 2026'));
	withTz('Asia/Tokyo', () => assert.equal(formatDate(earlyUtc, 'en'), 'Nov 15, 2026'));
});

test('a local-midnight timestamp is unchanged by the fix', () => {
	// The two nutrition call sites used to append `T00:00:00` by hand to dodge
	// the UTC parse. That form is a local instant and must keep rendering the
	// same day the bare date now does, so removing the workaround is a no-op.
	for (const tz of ['America/New_York', 'UTC', 'Asia/Tokyo']) {
		withTz(tz, () => {
			assert.equal(formatDate('2026-11-15T00:00:00', 'en'), formatDate('2026-11-15', 'en'), tz);
		});
	}
});

test('formatRelativeTime measures a date-only string from local midnight', () => {
	withTz('America/New_York', () => {
		// Local midnight on the 15th, read 3 hours later, is "3h ago" — not the
		// 8h a UTC-midnight parse would report in this zone.
		const threeHoursIn = Date.parse('2026-11-15T08:00:00Z'); // 03:00 in NY
		assert.equal(formatRelativeTime('2026-11-15', threeHoursIn, 'en'), '3h ago');
	});
});

test('a four-digit year below 100 is not remapped into the 1900s', () => {
	// The (year, month, day) Date constructor treats 0-99 as 1900-1999. Only
	// reachable from malformed input, but the parse must not invent a century.
	withTz('America/New_York', () => {
		assert.match(formatDate('0026-06-15', 'en'), /\b26\b/);
		assert.doesNotMatch(formatDate('0026-06-15', 'en'), /1926/);
	});
});
