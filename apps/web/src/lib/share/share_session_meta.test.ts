import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildSessionShareTitle,
	buildSessionShareDescription,
	buildSessionShareCanonical,
	buildSessionJsonLd,
	buildShareSessionHead,
	sessionEstimatedMinutes,
} from './share_session_meta';
import type { SharedSession, SharedSessionItem } from './share_session_lookup';

function item(over: Partial<SharedSessionItem> = {}): SharedSessionItem {
	return {
		id: 'i-1',
		block_id: 'b-1',
		position: 0,
		movement_name: 'Downward dog',
		kind: 'hold',
		duration_s: 60,
		reps: null,
		per_side: false,
		tempo: null,
		cue: null,
		...over,
	};
}

function p(over: Partial<SharedSession> = {}): SharedSession {
	return {
		id: 'p-1',
		author_id: 'u-1',
		title: 'Morning flow',
		discipline: 'Vinyasa',
		equipment: 'Mat',
		est_duration_min: 30,
		blocks: [{ id: 'b-1', position: 0, name: 'Warm up' }],
		items: [item(), item({ id: 'i-2', position: 1, movement_name: 'Warrior II', per_side: true })],
		...over,
	};
}

test('buildSessionShareTitle — plan title wins, then author, then generic', () => {
	assert.equal(buildSessionShareTitle(p(), 'Dani'), 'Morning flow — Threkir');
	assert.equal(buildSessionShareTitle(p({ title: null }), 'Dani'), 'Session by Dani — Threkir');
	assert.equal(buildSessionShareTitle(p({ title: '  ' }), null), 'Session — Threkir');
	assert.equal(buildSessionShareTitle(null, 'Dani'), 'Session — Threkir');
});

test('buildSessionShareTitle — a pathological title is collapsed and bounded', () => {
	const t = buildSessionShareTitle(p({ title: 'y'.repeat(400) }), null);
	assert.ok(t.length < 100, `title should be bounded, got ${t.length}`);
	assert.ok(t.endsWith('… — Threkir'));
	assert.equal(buildSessionShareTitle(p({ title: 'Morning\t\nflow' }), null), 'Morning flow — Threkir');
});

test('buildSessionShareDescription — discipline · movements · minutes · equipment · author', () => {
	const d = buildSessionShareDescription(p(), 'Dani');
	assert.match(d, /Vinyasa/);
	assert.match(d, /2 movements/);
	assert.match(d, /about 30 min/);
	assert.match(d, /Mat/);
	assert.match(d, /by Dani/);
	assert.match(d, /Follow the sequence on Threkir\./);
});

test('buildSessionShareDescription — singular movement, empty plan, and no plan at all', () => {
	assert.match(
		buildSessionShareDescription(p({ items: [item()], discipline: null, equipment: null }), null),
		/1 movement\b/,
	);
	assert.equal(
		buildSessionShareDescription(
			p({ items: [], discipline: null, equipment: null, est_duration_min: null }),
			null,
		),
		'Follow the sequence on Threkir.',
	);
	assert.equal(
		buildSessionShareDescription(null, 'Dani'),
		'View a public session plan on Threkir.',
	);
});

// tempo + cue are the author's free-text teaching notes. They are fetched (the
// page renders cues in the visible sequence) but must never reach the head,
// where an unfurler hands them to strangers out of context.
test('the meta never surfaces a per-item cue or tempo', () => {
	const withNotes = p({
		items: [item({ cue: 'mind your dodgy left knee', tempo: '4-2-4' })],
	});
	const head = buildShareSessionHead({
		id: 'p-1',
		session: withNotes,
		displayName: 'Dani',
		siteUrl: 'https://threkir.com',
	});
	for (const field of [head.title, head.description, head.jsonLd]) {
		assert.doesNotMatch(field, /dodgy|4-2-4/i);
	}
});

test('sessionEstimatedMinutes — author estimate wins, else the expanded step total', () => {
	assert.equal(sessionEstimatedMinutes(p()), 30);
	// Two 60 s holds, the second per-side (split L/R) = 180 s = 3 min.
	assert.equal(sessionEstimatedMinutes(p({ est_duration_min: null })), 3);
	assert.equal(sessionEstimatedMinutes(p({ est_duration_min: 0 })), 3);
	assert.equal(sessionEstimatedMinutes(null), 0);
});

test('buildSessionShareCanonical — absolute share/session URL, slash-normalised', () => {
	assert.equal(
		buildSessionShareCanonical('https://threkir.com/', 'p-1'),
		'https://threkir.com/share/session/p-1',
	);
	assert.equal(buildSessionShareCanonical(null, 'p-1'), '/share/session/p-1');
});

test('buildSessionJsonLd — WebPage + breadcrumb, no medical type, no image claim', () => {
	const obj = JSON.parse(
		buildSessionJsonLd(p(), { id: 'p-1', base: 'https://threkir.com', displayName: 'Dani' }),
	);
	assert.equal(obj['@type'], 'WebPage');
	assert.equal(obj.name, 'Morning flow');
	assert.equal(obj.url, 'https://threkir.com/share/session/p-1');
	assert.equal(obj.breadcrumb['@type'], 'BreadcrumbList');
	assert.equal(obj.breadcrumb.itemListElement.length, 2);
	assert.equal('primaryImageOfPage' in obj, false);
});

test('buildSessionJsonLd — escapes angle brackets so a title cannot break out of the script tag', () => {
	const json = buildSessionJsonLd(p({ title: '</script><b>x</b>' }), {
		id: 'p-1',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).name, '</script><b>x</b>');
});

test('buildShareSessionHead — canonical, branded OG image, JSON-LD in one shape', () => {
	const head = buildShareSessionHead({
		id: 'p-1',
		session: p(),
		displayName: 'Dani',
		siteUrl: 'https://threkir.com/',
	});
	assert.equal(head.canonical, 'https://threkir.com/share/session/p-1');
	assert.equal(head.ogImageUrl, 'https://threkir.com/og-default.png');
	assert.equal(head.title, 'Morning flow — Threkir');
	assert.equal(JSON.parse(head.jsonLd).url, head.canonical);
});

test('buildShareSessionHead — a private / missing plan still yields a valid head', () => {
	const head = buildShareSessionHead({
		id: 'p-x',
		session: null,
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(head.title, 'Session — Threkir');
	assert.equal(head.canonical, 'https://threkir.com/share/session/p-x');
	assert.doesNotMatch(head.description, /undefined|null/);
	assert.equal(JSON.parse(head.jsonLd)['@type'], 'WebPage');
});
