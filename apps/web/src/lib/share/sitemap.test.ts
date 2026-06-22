import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildRunCountByRouteId,
	buildSitemap,
	changefreqForRunCount,
	composeEntries,
	learnEntries,
	normaliseBase,
	priorityForRunCount,
	xmlEscape,
} from './sitemap';

// ---------------- xmlEscape ----------------

test('xmlEscape — escapes the five reserved characters', () => {
	assert.equal(xmlEscape(`a<b>c&d"e'f`), 'a&lt;b&gt;c&amp;d&quot;e&apos;f');
});

test('xmlEscape — passes through plain text + uuids untouched', () => {
	assert.equal(
		xmlEscape('550e8400-e29b-41d4-a716-446655440000'),
		'550e8400-e29b-41d4-a716-446655440000',
	);
	assert.equal(
		xmlEscape('https://threkir.com/share/run/abc'),
		'https://threkir.com/share/run/abc',
	);
});

// ---------------- normaliseBase ----------------

test('normaliseBase — strips a single trailing slash', () => {
	assert.equal(normaliseBase('https://threkir.com/'), 'https://threkir.com');
});

test('normaliseBase — strips multiple trailing slashes', () => {
	assert.equal(normaliseBase('https://threkir.com///'), 'https://threkir.com');
});

test('normaliseBase — is a no-op on a clean base', () => {
	assert.equal(normaliseBase('https://threkir.com'), 'https://threkir.com');
});

// ---------------- buildSitemap ----------------

test('buildSitemap — emits a valid xml declaration + urlset wrapper', () => {
	const xml = buildSitemap([]);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
	assert.match(xml.trimEnd(), /<\/urlset>$/);
});

test('buildSitemap — one entry round-trips through loc + lastmod + changefreq + priority', () => {
	const xml = buildSitemap([
		{
			loc: 'https://threkir.com/share/route/abc',
			lastmod: '2026-05-11T00:00:00Z',
			changefreq: 'weekly',
			priority: 0.7,
		},
	]);
	assert.ok(xml.includes('<loc>https://threkir.com/share/route/abc</loc>'));
	assert.ok(xml.includes('<lastmod>2026-05-11T00:00:00Z</lastmod>'));
	assert.ok(xml.includes('<changefreq>weekly</changefreq>'));
	assert.ok(xml.includes('<priority>0.7</priority>'));
});

test('buildSitemap — omits optional fields when unset', () => {
	const xml = buildSitemap([{ loc: 'https://threkir.com/' }]);
	assert.ok(xml.includes('<loc>https://threkir.com/</loc>'));
	assert.ok(!xml.includes('<lastmod>'));
	assert.ok(!xml.includes('<changefreq>'));
	assert.ok(!xml.includes('<priority>'));
});

test('buildSitemap — escapes special chars in loc + lastmod', () => {
	const xml = buildSitemap([{ loc: 'https://threkir.com/q?x=1&y=2', lastmod: '<bad>' }]);
	assert.ok(xml.includes('<loc>https://threkir.com/q?x=1&amp;y=2</loc>'));
	assert.ok(xml.includes('<lastmod>&lt;bad&gt;</lastmod>'));
});

test('buildSitemap — priority renders with one decimal place even when whole', () => {
	const xml = buildSitemap([{ loc: 'https://x/', priority: 1 }]);
	assert.ok(xml.includes('<priority>1.0</priority>'));
});

// ---------------- composeEntries ----------------

test('composeEntries — always emits the three top-level surfaces first', () => {
	const entries = composeEntries('https://threkir.com', [], []);
	assert.equal(entries.length, 3);
	assert.equal(entries[0].loc, 'https://threkir.com/');
	assert.equal(entries[1].loc, 'https://threkir.com/feed');
	assert.equal(entries[2].loc, 'https://threkir.com/routes?tab=explore');
	assert.equal(entries[0].priority, 1.0);
});

test('composeEntries — strips trailing slash on the base before concatenating', () => {
	const entries = composeEntries('https://threkir.com/', [{ id: 'r1' }], []);
	const routeEntry = entries.find((e) => e.loc.includes('/share/route/'));
	assert.equal(routeEntry?.loc, 'https://threkir.com/share/route/r1');
});

test('composeEntries — routes and runs become /share/* entries with lastmod when available', () => {
	const entries = composeEntries(
		'https://threkir.com',
		[{ id: 'route-1', updated_at: '2026-05-10T00:00:00Z' }],
		[
			{ id: 'run-1', updated_at: '2026-05-11T00:00:00Z' },
			{ id: 'run-2', updated_at: null, started_at: '2026-05-09T00:00:00Z' },
		],
	);
	assert.equal(entries.length, 6); // 3 top-level + 1 route + 2 runs
	const route1 = entries.find((e) => e.loc === 'https://threkir.com/share/route/route-1');
	assert.equal(route1?.lastmod, '2026-05-10T00:00:00Z');
	const run1 = entries.find((e) => e.loc === 'https://threkir.com/share/run/run-1');
	assert.equal(run1?.lastmod, '2026-05-11T00:00:00Z');
	// run-2 has no updated_at; falls back to started_at.
	const run2 = entries.find((e) => e.loc === 'https://threkir.com/share/run/run-2');
	assert.equal(run2?.lastmod, '2026-05-09T00:00:00Z');
});

test('composeEntries — entries with neither updated_at nor started_at omit lastmod', () => {
	const entries = composeEntries('https://threkir.com', [], [{ id: 'r' }]);
	const run = entries.find((e) => e.loc.includes('/share/run/r'));
	assert.equal(run?.lastmod, undefined);
});

test('composeEntries — every share entry carries a priority and a changefreq', () => {
	const entries = composeEntries('https://threkir.com', [{ id: 'a' }], [{ id: 'b' }]);
	const route = entries.find((e) => e.loc.endsWith('/share/route/a'))!;
	const run = entries.find((e) => e.loc.endsWith('/share/run/b'))!;
	// Route with no popularity → cold base values.
	assert.equal(route.changefreq, 'monthly');
	assert.equal(route.priority, 0.7);
	assert.equal(run.changefreq, 'monthly');
	assert.equal(run.priority, 0.6);
});

// ---------------- end-to-end ----------------

// ---------------- priorityForRunCount + changefreqForRunCount ----------------

test('priorityForRunCount — bucket boundaries', () => {
	assert.equal(priorityForRunCount(0), 0.7);
	assert.equal(priorityForRunCount(4), 0.7);
	assert.equal(priorityForRunCount(5), 0.8);
	assert.equal(priorityForRunCount(19), 0.8);
	assert.equal(priorityForRunCount(20), 0.9);
	assert.equal(priorityForRunCount(49), 0.9);
	assert.equal(priorityForRunCount(50), 1.0);
	assert.equal(priorityForRunCount(1000), 1.0);
});

test('changefreqForRunCount — bucket boundaries', () => {
	assert.equal(changefreqForRunCount(0), 'monthly');
	assert.equal(changefreqForRunCount(4), 'monthly');
	assert.equal(changefreqForRunCount(5), 'weekly');
	assert.equal(changefreqForRunCount(19), 'weekly');
	assert.equal(changefreqForRunCount(20), 'daily');
});

// ---------------- buildRunCountByRouteId ----------------

test('buildRunCountByRouteId — tallies repeated ids', () => {
	const m = buildRunCountByRouteId([
		{ route_id: 'a' },
		{ route_id: 'a' },
		{ route_id: 'b' },
		{ route_id: 'a' },
	]);
	assert.equal(m.get('a'), 3);
	assert.equal(m.get('b'), 1);
	assert.equal(m.size, 2);
});

test('buildRunCountByRouteId — ignores null + undefined route_ids', () => {
	const m = buildRunCountByRouteId([
		{ route_id: null },
		{ route_id: undefined },
		{ route_id: 'real' },
		{},
	]);
	assert.equal(m.size, 1);
	assert.equal(m.get('real'), 1);
});

test('buildRunCountByRouteId — empty input returns empty map', () => {
	const m = buildRunCountByRouteId([]);
	assert.equal(m.size, 0);
});

// ---------------- composeEntries popularity ----------------

test('composeEntries — popular route bumps priority + changefreq', () => {
	const popularity = new Map<string, number>([
		['hot', 25], // → daily / 0.9
		['warm', 7], // → weekly / 0.8
	]);
	const entries = composeEntries(
		'https://x',
		[{ id: 'hot' }, { id: 'warm' }, { id: 'cold' }],
		[],
		popularity,
	);
	const hot = entries.find((e) => e.loc.endsWith('/share/route/hot'))!;
	const warm = entries.find((e) => e.loc.endsWith('/share/route/warm'))!;
	const cold = entries.find((e) => e.loc.endsWith('/share/route/cold'))!;
	assert.equal(hot.priority, 0.9);
	assert.equal(hot.changefreq, 'daily');
	assert.equal(warm.priority, 0.8);
	assert.equal(warm.changefreq, 'weekly');
	assert.equal(cold.priority, 0.7);
	assert.equal(cold.changefreq, 'monthly');
});

test('composeEntries — popularity map omitted → all routes use base values', () => {
	const entries = composeEntries('https://x', [{ id: 'a' }, { id: 'b' }], []);
	const a = entries.find((e) => e.loc.endsWith('/share/route/a'))!;
	assert.equal(a.priority, 0.7);
	assert.equal(a.changefreq, 'monthly');
});

// ---------------- end-to-end ----------------

test('composeEntries → buildSitemap produces a well-formed XML body the spec accepts', () => {
	const xml = buildSitemap(
		composeEntries(
			'https://threkir.com',
			[{ id: 'route-uuid-1', updated_at: '2026-05-10T00:00:00Z' }],
			[{ id: 'run-uuid-1', started_at: '2026-05-09T00:00:00Z' }],
		),
	);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
	assert.match(xml, /<\/urlset>\s*$/);
	assert.ok(xml.includes('<loc>https://threkir.com/</loc>'));
	assert.ok(xml.includes('<loc>https://threkir.com/share/route/route-uuid-1</loc>'));
	assert.ok(xml.includes('<loc>https://threkir.com/share/run/run-uuid-1</loc>'));
});

// ---------------- learnEntries ----------------

test('learnEntries — emits the hub, each category, and each guide', () => {
	const entries = learnEntries(
		'https://threkir.com/',
		[
			{ slug: 'road-running-101', updated: '2026-06-15' },
			{ slug: 'couch-to-5k', updated: '2026-06-15' },
		],
		['getting-started', 'gear'],
	);
	const locs = new Set(entries.map((e) => e.loc));
	assert.ok(locs.has('https://threkir.com/learn'));
	assert.ok(locs.has('https://threkir.com/learn/category/getting-started'));
	assert.ok(locs.has('https://threkir.com/learn/category/gear'));
	assert.ok(locs.has('https://threkir.com/learn/road-running-101'));
	assert.ok(locs.has('https://threkir.com/learn/couch-to-5k'));
});

test('learnEntries — hub/category/guide carry the documented priorities + lastmod', () => {
	const entries = learnEntries(
		'https://threkir.com',
		[{ slug: 'road-running-101', updated: '2026-06-15' }],
		['getting-started'],
	);
	const hub = entries.find((e) => e.loc.endsWith('/learn'));
	const category = entries.find((e) => e.loc.endsWith('/category/getting-started'));
	const guide = entries.find((e) => e.loc.endsWith('/road-running-101'));
	assert.equal(hub?.priority, 0.8);
	assert.equal(category?.priority, 0.6);
	assert.equal(guide?.priority, 0.7);
	assert.equal(guide?.lastmod, '2026-06-15');
	assert.equal(guide?.changefreq, 'monthly');
});

test('learnEntries → buildSitemap emits the guide lastmod', () => {
	const xml = buildSitemap(
		learnEntries('https://threkir.com', [{ slug: 'road-running-101', updated: '2026-06-15' }], [
			'getting-started',
		]),
	);
	assert.ok(xml.includes('<loc>https://threkir.com/learn/road-running-101</loc>'));
	assert.ok(xml.includes('<lastmod>2026-06-15</lastmod>'));
});
