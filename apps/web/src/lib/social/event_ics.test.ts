import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildEventIcs,
	buildEventSeriesIcs,
	buildRrule,
	toIcsUtc,
	icsFilename
} from './event_ics';
import type { Event } from '../types';

const BASE = {
	uid: 'event-abc-2026-07-11T18:00:00Z@threkir.com',
	title: 'Saturday Long Run',
	startIso: '2026-07-11T18:00:00.000Z',
	nowMs: Date.parse('2026-07-01T00:00:00.000Z')
};

test('toIcsUtc formats an ISO instant as a UTC iCalendar date-time', () => {
	assert.equal(toIcsUtc('2026-07-11T18:05:09.000Z'), '20260711T180509Z');
});

test('toIcsUtc converts a non-UTC offset to the UTC instant', () => {
	assert.equal(toIcsUtc('2026-07-11T20:00:00+02:00'), '20260711T180000Z');
});

test('toIcsUtc returns null for an unparseable string', () => {
	assert.equal(toIcsUtc('not-a-date'), null);
});

test('buildEventIcs wraps one VEVENT in a VCALENDAR with CRLF endings', () => {
	const ics = buildEventIcs(BASE);
	assert.ok(ics);
	assert.ok(ics!.startsWith('BEGIN:VCALENDAR\r\n'));
	assert.ok(ics!.trimEnd().endsWith('END:VCALENDAR'));
	assert.equal((ics!.match(/BEGIN:VEVENT/g) ?? []).length, 1);
	assert.match(ics!, /\r\n/);
	assert.doesNotMatch(ics!, /[^\r]\n/); // every LF is preceded by CR
});

test('buildEventIcs emits required properties', () => {
	const ics = buildEventIcs(BASE)!;
	assert.match(ics, /VERSION:2\.0/);
	assert.match(ics, /UID:event-abc-2026-07-11T18:00:00Z@threkir\.com/);
	assert.match(ics, /DTSTART:20260711T180000Z/);
	assert.match(ics, /DTSTAMP:20260701T000000Z/);
	assert.match(ics, /SUMMARY:Saturday Long Run/);
});

test('buildEventIcs derives DTEND from durationMin', () => {
	const ics = buildEventIcs({ ...BASE, durationMin: 90 })!;
	assert.match(ics, /DTEND:20260711T193000Z/);
});

test('buildEventIcs omits DTEND when duration is absent or non-positive', () => {
	assert.doesNotMatch(buildEventIcs(BASE)!, /DTEND/);
	assert.doesNotMatch(buildEventIcs({ ...BASE, durationMin: 0 })!, /DTEND/);
	assert.doesNotMatch(buildEventIcs({ ...BASE, durationMin: null })!, /DTEND/);
});

test('buildEventIcs escapes TEXT special characters per RFC 5545', () => {
	const ics = buildEventIcs({
		...BASE,
		title: 'Run; then brunch, maybe',
		description: 'Line one\nLine two\\end'
	})!;
	assert.match(ics, /SUMMARY:Run\\; then brunch\\, maybe/);
	assert.match(ics, /DESCRIPTION:Line one\\nLine two\\\\end/);
});

test('buildEventIcs includes optional LOCATION and URL only when set', () => {
	const withExtras = buildEventIcs({
		...BASE,
		location: 'Central Park',
		url: 'https://threkir.com/share/event/abc'
	})!;
	assert.match(withExtras, /LOCATION:Central Park/);
	assert.match(withExtras, /URL:https:\/\/threkir\.com\/share\/event\/abc/);

	const bare = buildEventIcs(BASE)!;
	assert.doesNotMatch(bare, /LOCATION:/);
	assert.doesNotMatch(bare, /URL:/);
});

test('buildEventIcs folds a long line to <=75 octets with space continuations', () => {
	const longTitle = 'A'.repeat(200);
	const ics = buildEventIcs({ ...BASE, title: longTitle })!;
	for (const line of ics.split('\r\n')) {
		assert.ok(
			Buffer.byteLength(line, 'utf8') <= 75,
			`line exceeds 75 octets: ${line.length}`
		);
	}
	// A folded continuation line begins with a single space.
	assert.match(ics, /\r\n [A]/);
});

test('buildEventIcs returns null for an invalid start instant', () => {
	assert.equal(buildEventIcs({ ...BASE, startIso: 'garbage' }), null);
});

test('buildRrule states a weekly series with its BYDAY set', () => {
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'] }), 'FREQ=WEEKLY;BYDAY=SA');
});

test('buildRrule normalises BYDAY into Monday-first order', () => {
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['TH', 'TU'] }),
		'FREQ=WEEKLY;BYDAY=TU,TH'
	);
});

test('buildRrule expresses biweekly as a two-week interval', () => {
	assert.equal(
		buildRrule({ freq: 'biweekly', byday: ['TU', 'TH'] }),
		'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH'
	);
});

test('buildRrule emits BYMONTHDAY for a monthly series', () => {
	assert.equal(
		buildRrule({ freq: 'monthly', monthDay: 15 }),
		'FREQ=MONTHLY;BYMONTHDAY=15'
	);
});

test('buildRrule refuses a monthly series past the 28th — BYMONTHDAY cannot clamp', () => {
	for (const monthDay of [29, 30, 31]) {
		assert.equal(buildRrule({ freq: 'monthly', monthDay }), null);
	}
	assert.equal(buildRrule({ freq: 'monthly', monthDay: 28 }), 'FREQ=MONTHLY;BYMONTHDAY=28');
	assert.equal(buildRrule({ freq: 'monthly', monthDay: null }), null);
	assert.equal(buildRrule({ freq: 'monthly', monthDay: 0 }), null);
});

test('buildRrule emits UNTIL as a UTC instant', () => {
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['SA'], untilIso: '2026-09-05T20:00:00+02:00' }),
		'FREQ=WEEKLY;UNTIL=20260905T180000Z;BYDAY=SA'
	);
});

test('buildRrule never emits UNTIL and COUNT together (RFC 5545 §3.3.10)', () => {
	const rule = buildRrule({
		freq: 'weekly',
		byday: ['SA'],
		untilIso: '2026-09-05T18:00:00Z',
		count: 4
	})!;
	assert.match(rule, /COUNT=4/);
	assert.doesNotMatch(rule, /UNTIL=/);
});

test('buildRrule fails closed on a bound it cannot state', () => {
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], count: 0 }), null);
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], count: 2.5 }), null);
	assert.equal(buildRrule({ freq: 'weekly', byday: ['SA'], untilIso: 'garbage' }), null);
	assert.equal(
		buildRrule({ freq: 'weekly', byday: ['XX' as unknown as 'MO'] }),
		null
	);
});

test('buildEventIcs emits RRULE and EXDATE for a series', () => {
	const ics = buildEventIcs({
		...BASE,
		recurrence: { freq: 'weekly', byday: ['SA'] },
		exdatesIso: ['2026-07-25T18:00:00.000Z', '2026-07-18T18:00:00.000Z']
	})!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
	// Sorted + deduped so the same series always serialises identically.
	assert.match(ics, /EXDATE:20260718T180000Z,20260725T180000Z/);
	assert.equal((ics.match(/BEGIN:VEVENT/g) ?? []).length, 1);
});

test('buildEventIcs drops unparseable and duplicate EXDATE values', () => {
	const ics = buildEventIcs({
		...BASE,
		recurrence: { freq: 'weekly', byday: ['SA'] },
		exdatesIso: ['2026-07-18T18:00:00.000Z', '2026-07-18T18:00:00Z', 'nonsense']
	})!;
	assert.match(ics, /EXDATE:20260718T180000Z\r\n/);
});

test('buildEventIcs ignores EXDATE for a single occurrence', () => {
	const ics = buildEventIcs({ ...BASE, exdatesIso: ['2026-07-18T18:00:00.000Z'] })!;
	assert.doesNotMatch(ics, /EXDATE/);
	assert.doesNotMatch(ics, /RRULE/);
});

test('buildEventIcs fails the whole build when the recurrence is unrepresentable', () => {
	assert.equal(
		buildEventIcs({ ...BASE, recurrence: { freq: 'monthly', monthDay: 31 } }),
		null
	);
});

// `timezone` is what makes recurrence expansion read + stamp in UTC (see
// recurrence.ts), which is also the clock the .ics is written in — so these
// fixtures are deterministic regardless of the machine's zone.
function ev(partial: Partial<Event>): Event {
	return {
		id: 'evt-1',
		title: 'Saturday Long Run',
		timezone: 'UTC',
		duration_min: 90,
		description: null,
		meet_label: null,
		recurrence_byday: null,
		recurrence_until: null,
		recurrence_count: null,
		...partial
	} as unknown as Event;
}

const SERIES_OPTS = { nowMs: Date.parse('2026-07-01T00:00:00.000Z') };

test('buildEventSeriesIcs returns null for a one-off event', () => {
	assert.equal(
		buildEventSeriesIcs(ev({ starts_at: '2026-07-11T18:00:00Z' }), SERIES_OPTS),
		null
	);
});

test('buildEventSeriesIcs anchors DTSTART on the series and carries the RRULE', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			meet_label: 'Clubhouse steps'
		}),
		{ ...SERIES_OPTS, url: 'https://threkir.com/share/event/evt-1' }
	)!;
	assert.match(ics, /DTSTART:20260711T180000Z/);
	assert.match(ics, /DTEND:20260711T193000Z/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
	assert.match(ics, /LOCATION:Clubhouse steps/);
	// A distinct UID from the per-occurrence export, so importing the series
	// does not overwrite (or get overwritten by) a single occurrence.
	assert.match(ics, /UID:event-evt-1-series@threkir\.com/);
});

test('buildEventSeriesIcs starts at the first real occurrence, not starts_at', () => {
	// Tuesday start, Saturday series: RFC 5545 requires DTSTART to be a member
	// of the recurrence set, and the club page never shows the Tuesday.
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-07T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /DTSTART:20260711T180000Z/);
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
});

test('buildEventSeriesIcs reads BYDAY off the expansion when no weekdays are stored', () => {
	const ics = buildEventSeriesIcs(
		ev({ starts_at: '2026-07-11T18:00:00Z', recurrence_freq: 'weekly' }),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;BYDAY=SA/);
});

test('buildEventSeriesIcs keeps every weekday of a multi-day series', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-07T18:00:00Z',
			recurrence_freq: 'biweekly',
			recurrence_byday: ['TU', 'TH']
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH/);
});

test('buildEventSeriesIcs carries a count-bounded series through as COUNT', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_count: 6
		}),
		SERIES_OPTS
	)!;
	assert.match(ics, /RRULE:FREQ=WEEKLY;COUNT=6;BYDAY=SA/);
});

test('buildEventSeriesIcs resolves an until+count series to whichever binds first', () => {
	// Jul 11 / 18 / 25 / Aug 1 fit inside the until-bound, so the count of 10
	// never binds and the RRULE must stop at four rather than run on.
	const untilBinds = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_until: '2026-08-01T23:59:00Z',
			recurrence_count: 10
		}),
		SERIES_OPTS
	)!;
	assert.match(untilBinds, /RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=SA/);

	const countBinds = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA'],
			recurrence_until: '2026-12-31T23:59:00Z',
			recurrence_count: 2
		}),
		SERIES_OPTS
	)!;
	assert.match(countBinds, /RRULE:FREQ=WEEKLY;COUNT=2;BYDAY=SA/);
});

test('buildEventSeriesIcs subtracts cancelled occurrences via EXDATE', () => {
	const ics = buildEventSeriesIcs(
		ev({
			starts_at: '2026-07-11T18:00:00Z',
			recurrence_freq: 'weekly',
			recurrence_byday: ['SA']
		}),
		{ ...SERIES_OPTS, cancelledIso: ['2026-07-18T18:00:00+00:00'] }
	)!;
	assert.match(ics, /EXDATE:20260718T180000Z/);
});

test('buildEventSeriesIcs withholds a monthly series it cannot state faithfully', () => {
	assert.equal(
		buildEventSeriesIcs(
			ev({ starts_at: '2026-03-31T09:00:00Z', recurrence_freq: 'monthly' }),
			SERIES_OPTS
		),
		null
	);
	const midMonth = buildEventSeriesIcs(
		ev({ starts_at: '2026-03-15T09:00:00Z', recurrence_freq: 'monthly' }),
		SERIES_OPTS
	)!;
	assert.match(midMonth, /RRULE:FREQ=MONTHLY;BYMONTHDAY=15/);
	assert.match(midMonth, /DTSTART:20260315T090000Z/);
});

test('buildEventSeriesIcs returns null for a series with no occurrences at all', () => {
	assert.equal(
		buildEventSeriesIcs(
			ev({
				starts_at: '2026-07-11T18:00:00Z',
				recurrence_freq: 'weekly',
				recurrence_byday: ['SA'],
				recurrence_until: '2026-07-01T00:00:00Z'
			}),
			SERIES_OPTS
		),
		null
	);
});

test('icsFilename slugs the title and always ends in .ics', () => {
	assert.equal(icsFilename('Saturday Long Run'), 'saturday-long-run.ics');
	assert.equal(icsFilename('  !!!  '), 'event.ics');
	assert.equal(icsFilename('Café 10K — Île'), 'caf-10k-le.ics');
});
