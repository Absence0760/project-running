import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildEventIcs, toIcsUtc, icsFilename } from './event_ics';

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

test('icsFilename slugs the title and always ends in .ics', () => {
	assert.equal(icsFilename('Saturday Long Run'), 'saturday-long-run.ics');
	assert.equal(icsFilename('  !!!  '), 'event.ics');
	assert.equal(icsFilename('Café 10K — Île'), 'caf-10k-le.ics');
});
