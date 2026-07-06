import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildEventShareTitle,
	buildEventShareDescription,
	buildEventShareCanonical,
	buildEventJsonLd,
} from './share_event_meta';
import type { SharedEvent } from './share_event_lookup';

function ev(over: Partial<SharedEvent> = {}): SharedEvent {
	return {
		id: 'e-1',
		club_id: 'c-1',
		title: 'Saturday Parkrun',
		description: 'Weekly 5k around the park.',
		starts_at: '2026-05-16T08:00:00Z',
		duration_min: 60,
		distance_m: 5000,
		category: 'run',
		discipline: null,
		club_name: 'Hampstead Runners',
		club_slug: 'hampstead-runners',
		club_location: 'London, UK',
		...over,
	};
}

// ---------------- title / description ----------------

test('buildEventShareTitle — appends the site suffix', () => {
	assert.equal(buildEventShareTitle(ev()), 'Saturday Parkrun — Threkir');
});

test('buildEventShareTitle — null event keeps the generic fallback', () => {
	assert.equal(buildEventShareTitle(null), 'Event — Threkir');
});

test('buildEventShareDescription — leads with date · distance · host', () => {
	const d = buildEventShareDescription(ev());
	assert.match(d, /16 May 2026/);
	assert.match(d, /5\.0 km/);
	assert.match(d, /hosted by Hampstead Runners/);
	assert.match(d, /in London, UK/);
});

test('buildEventShareDescription — null event falls back', () => {
	assert.equal(buildEventShareDescription(null), 'A public event on Threkir.');
});

// ---------------- canonical ----------------

test('buildEventShareCanonical — absolute share/event URL, slash-normalised', () => {
	assert.equal(
		buildEventShareCanonical('https://threkir.com/', 'e-1'),
		'https://threkir.com/share/event/e-1'
	);
	assert.equal(buildEventShareCanonical(null, 'e-1'), '/share/event/e-1');
});

// ---------------- JSON-LD ----------------

test('buildEventJsonLd — run category maps to SportsEvent with start/end + organizer + coarse location', () => {
	const obj = JSON.parse(buildEventJsonLd(ev(), { id: 'e-1', base: 'https://threkir.com' }));
	assert.equal(obj['@type'], 'SportsEvent');
	assert.equal(obj.name, 'Saturday Parkrun');
	assert.equal(obj.url, 'https://threkir.com/share/event/e-1');
	assert.equal(obj.startDate, '2026-05-16T08:00:00Z');
	// 60 min after start.
	assert.equal(obj.endDate, '2026-05-16T09:00:00.000Z');
	assert.equal(obj.eventAttendanceMode, 'https://schema.org/OfflineEventAttendanceMode');
	assert.equal(obj.organizer['@type'], 'Organization');
	assert.equal(obj.organizer.name, 'Hampstead Runners');
	assert.equal(obj.organizer.url, 'https://threkir.com/clubs/hampstead-runners');
	// Coarse club location only — never the precise meet coordinate.
	assert.equal(obj.location['@type'], 'Place');
	assert.equal(obj.location.name, 'London, UK');
	assert.equal('geo' in obj, false);
});

test('buildEventJsonLd — class category maps to the generic Event type', () => {
	const obj = JSON.parse(
		buildEventJsonLd(ev({ category: 'class' }), { id: 'e-1', base: 'https://threkir.com' })
	);
	assert.equal(obj['@type'], 'Event');
});

test('buildEventJsonLd — no duration omits endDate', () => {
	const obj = JSON.parse(
		buildEventJsonLd(ev({ duration_min: null }), { id: 'e-1', base: 'https://threkir.com' })
	);
	assert.equal('endDate' in obj, false);
	assert.equal(obj.startDate, '2026-05-16T08:00:00Z');
});

test('buildEventJsonLd — escapes angle brackets so a title cannot break out of the script tag', () => {
	const json = buildEventJsonLd(ev({ title: '</script><img src=x onerror=alert(1)>' }), {
		id: 'e-1',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).name, '</script><img src=x onerror=alert(1)>');
});
