import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSitemap, composeEntries, normaliseBase, xmlEscape } from './sitemap';

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
		xmlEscape('https://runonward.com/share/run/abc'),
		'https://runonward.com/share/run/abc',
	);
});

// ---------------- normaliseBase ----------------

test('normaliseBase — strips a single trailing slash', () => {
	assert.equal(normaliseBase('https://runonward.com/'), 'https://runonward.com');
});

test('normaliseBase — strips multiple trailing slashes', () => {
	assert.equal(normaliseBase('https://runonward.com///'), 'https://runonward.com');
});

test('normaliseBase — is a no-op on a clean base', () => {
	assert.equal(normaliseBase('https://runonward.com'), 'https://runonward.com');
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
			loc: 'https://runonward.com/share/route/abc',
			lastmod: '2026-05-11T00:00:00Z',
			changefreq: 'weekly',
			priority: 0.7,
		},
	]);
	assert.ok(xml.includes('<loc>https://runonward.com/share/route/abc</loc>'));
	assert.ok(xml.includes('<lastmod>2026-05-11T00:00:00Z</lastmod>'));
	assert.ok(xml.includes('<changefreq>weekly</changefreq>'));
	assert.ok(xml.includes('<priority>0.7</priority>'));
});

test('buildSitemap — omits optional fields when unset', () => {
	const xml = buildSitemap([{ loc: 'https://runonward.com/' }]);
	assert.ok(xml.includes('<loc>https://runonward.com/</loc>'));
	assert.ok(!xml.includes('<lastmod>'));
	assert.ok(!xml.includes('<changefreq>'));
	assert.ok(!xml.includes('<priority>'));
});

test('buildSitemap — escapes special chars in loc + lastmod', () => {
	const xml = buildSitemap([{ loc: 'https://runonward.com/q?x=1&y=2', lastmod: '<bad>' }]);
	assert.ok(xml.includes('<loc>https://runonward.com/q?x=1&amp;y=2</loc>'));
	assert.ok(xml.includes('<lastmod>&lt;bad&gt;</lastmod>'));
});

test('buildSitemap — priority renders with one decimal place even when whole', () => {
	const xml = buildSitemap([{ loc: 'https://x/', priority: 1 }]);
	assert.ok(xml.includes('<priority>1.0</priority>'));
});

// ---------------- composeEntries ----------------

test('composeEntries — always emits the three top-level surfaces first', () => {
	const entries = composeEntries('https://runonward.com', [], []);
	assert.equal(entries.length, 3);
	assert.equal(entries[0].loc, 'https://runonward.com/');
	assert.equal(entries[1].loc, 'https://runonward.com/feed');
	assert.equal(entries[2].loc, 'https://runonward.com/routes?tab=explore');
	assert.equal(entries[0].priority, 1.0);
});

test('composeEntries — strips trailing slash on the base before concatenating', () => {
	const entries = composeEntries('https://runonward.com/', [{ id: 'r1' }], []);
	const routeEntry = entries.find((e) => e.loc.includes('/share/route/'));
	assert.equal(routeEntry?.loc, 'https://runonward.com/share/route/r1');
});

test('composeEntries — routes and runs become /share/* entries with lastmod when available', () => {
	const entries = composeEntries(
		'https://runonward.com',
		[{ id: 'route-1', updated_at: '2026-05-10T00:00:00Z' }],
		[
			{ id: 'run-1', updated_at: '2026-05-11T00:00:00Z' },
			{ id: 'run-2', updated_at: null, started_at: '2026-05-09T00:00:00Z' },
		],
	);
	assert.equal(entries.length, 6); // 3 top-level + 1 route + 2 runs
	const route1 = entries.find((e) => e.loc === 'https://runonward.com/share/route/route-1');
	assert.equal(route1?.lastmod, '2026-05-10T00:00:00Z');
	const run1 = entries.find((e) => e.loc === 'https://runonward.com/share/run/run-1');
	assert.equal(run1?.lastmod, '2026-05-11T00:00:00Z');
	// run-2 has no updated_at; falls back to started_at.
	const run2 = entries.find((e) => e.loc === 'https://runonward.com/share/run/run-2');
	assert.equal(run2?.lastmod, '2026-05-09T00:00:00Z');
});

test('composeEntries — entries with neither updated_at nor started_at omit lastmod', () => {
	const entries = composeEntries('https://runonward.com', [], [{ id: 'r' }]);
	const run = entries.find((e) => e.loc.includes('/share/run/r'));
	assert.equal(run?.lastmod, undefined);
});

test('composeEntries — every share entry carries a priority and a changefreq', () => {
	const entries = composeEntries('https://runonward.com', [{ id: 'a' }], [{ id: 'b' }]);
	const route = entries.find((e) => e.loc.endsWith('/share/route/a'))!;
	const run = entries.find((e) => e.loc.endsWith('/share/run/b'))!;
	assert.equal(route.changefreq, 'weekly');
	assert.equal(route.priority, 0.7);
	assert.equal(run.changefreq, 'monthly');
	assert.equal(run.priority, 0.6);
});

// ---------------- end-to-end ----------------

test('composeEntries → buildSitemap produces a well-formed XML body the spec accepts', () => {
	const xml = buildSitemap(
		composeEntries(
			'https://runonward.com',
			[{ id: 'route-uuid-1', updated_at: '2026-05-10T00:00:00Z' }],
			[{ id: 'run-uuid-1', started_at: '2026-05-09T00:00:00Z' }],
		),
	);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
	assert.match(xml, /<\/urlset>\s*$/);
	assert.ok(xml.includes('<loc>https://runonward.com/</loc>'));
	assert.ok(xml.includes('<loc>https://runonward.com/share/route/route-uuid-1</loc>'));
	assert.ok(xml.includes('<loc>https://runonward.com/share/run/run-uuid-1</loc>'));
});
