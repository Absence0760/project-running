import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildRouteJsonLd,
	buildRouteShareCanonical,
	buildRouteShareDescription,
	buildRouteShareTitle,
	buildRunJsonLd,
	buildRunShareCanonical,
	buildRunShareDescription,
	buildRunShareTitle,
	cleanShareTitle,
	formatDateStable,
	formatKmStable,
	normaliseSiteUrl,
} from './share_meta';

// ---------------- formatKmStable ----------------

test('formatKmStable — short distance rounds to whole metres', () => {
	assert.equal(formatKmStable(500), '500 m');
	assert.equal(formatKmStable(999), '999 m');
});

test('formatKmStable — short km uses one decimal', () => {
	assert.equal(formatKmStable(5000), '5.0 km');
	assert.equal(formatKmStable(10456), '10.5 km');
});

test('formatKmStable — marathon+ uses two decimals for precision', () => {
	assert.equal(formatKmStable(42195), '42.20 km');
	assert.equal(formatKmStable(21097.5), '21.10 km');
});

test('formatKmStable — null/negative/non-finite returns empty', () => {
	assert.equal(formatKmStable(null), '');
	assert.equal(formatKmStable(undefined), '');
	assert.equal(formatKmStable(-100), '');
	assert.equal(formatKmStable(Number.NaN), '');
});

// ---------------- formatDateStable ----------------

test('formatDateStable — UTC day-month-year shape', () => {
	assert.equal(formatDateStable('2026-05-11T00:00:00Z'), '11 May 2026');
});

test('formatDateStable — pinned to UTC even when input has a local offset', () => {
	// 2026-05-11T22:00:00-04:00 is 2026-05-12T02:00:00Z in UTC.
	assert.equal(formatDateStable('2026-05-11T22:00:00-04:00'), '12 May 2026');
});

test('formatDateStable — null / malformed returns empty', () => {
	assert.equal(formatDateStable(null), '');
	assert.equal(formatDateStable(undefined), '');
	assert.equal(formatDateStable(''), '');
	assert.equal(formatDateStable('not a date'), '');
});

// ---------------- buildRunShareTitle ----------------

test('buildRunShareTitle — null run keeps the generic fallback', () => {
	assert.equal(buildRunShareTitle(null), 'Run — Threkir');
});

test('buildRunShareTitle — full meta produces a deterministic title', () => {
	assert.equal(
		buildRunShareTitle({ distance_m: 5000, started_at: '2026-05-11T00:00:00Z' }),
		'5.0 km run on 11 May 2026 — Threkir',
	);
});

test('buildRunShareTitle — distance-only run omits date', () => {
	assert.equal(buildRunShareTitle({ distance_m: 10000 }), '10.0 km run — Threkir');
});

test('buildRunShareTitle — date-only run omits distance', () => {
	assert.equal(
		buildRunShareTitle({ started_at: '2026-05-11T00:00:00Z' }),
		'Run on 11 May 2026 — Threkir',
	);
});

test('buildRunShareTitle — display_name folds into the title when provided', () => {
	assert.equal(
		buildRunShareTitle(
			{ distance_m: 5000, started_at: '2026-05-11T00:00:00Z' },
			'Jared',
		),
		'5.0 km run by Jared on 11 May 2026 — Threkir',
	);
});

test('buildRunShareTitle — display_name with distance only', () => {
	assert.equal(
		buildRunShareTitle({ distance_m: 10000 }, 'Alex'),
		'10.0 km run by Alex — Threkir',
	);
});

test('buildRunShareTitle — null display_name falls back to anonymous shape', () => {
	assert.equal(
		buildRunShareTitle({ distance_m: 5000, started_at: '2026-05-11T00:00:00Z' }, null),
		'5.0 km run on 11 May 2026 — Threkir',
	);
});

test('buildRunShareTitle — display_name with no run meta still attributes', () => {
	assert.equal(buildRunShareTitle({}, 'Morgan'), 'Run by Morgan — Threkir');
});

// ---------------- buildRunShareDescription ----------------

test('buildRunShareDescription — meta is appended before the lead', () => {
	const desc = buildRunShareDescription({
		distance_m: 5000,
		started_at: '2026-05-11T00:00:00Z',
	});
	assert.ok(desc.startsWith('5.0 km on 11 May 2026.'));
	assert.ok(desc.includes('Map, splits, and elevation on Threkir.'));
});

test('buildRunShareDescription — display_name appears next to the distance', () => {
	const desc = buildRunShareDescription(
		{ distance_m: 5000, started_at: '2026-05-11T00:00:00Z' },
		'Jared',
	);
	assert.ok(desc.startsWith('5.0 km by Jared on 11 May 2026.'));
});

test('buildRunShareDescription — null run keeps generic copy', () => {
	assert.equal(
		buildRunShareDescription(null),
		'View a public run on Threkir — map, splits, elevation, kudos.',
	);
});

// ---------------- buildRouteShareTitle ----------------

test('buildRouteShareTitle — uses the route name when present', () => {
	assert.equal(
		buildRouteShareTitle({ name: 'Hampstead Heath loop' }),
		'Hampstead Heath loop — Threkir',
	);
});

test('buildRouteShareTitle — missing name falls back to generic', () => {
	assert.equal(buildRouteShareTitle({ distance_m: 5000 }), 'Route — Threkir');
	assert.equal(buildRouteShareTitle(null), 'Route — Threkir');
});

// ---------------- buildRouteShareDescription ----------------

test('buildRouteShareDescription — km + surface combine', () => {
	assert.equal(
		buildRouteShareDescription({ distance_m: 10000, surface: 'road' }),
		'10.0 km road route.',
	);
});

test('buildRouteShareDescription — elevation is appended when present', () => {
	assert.equal(
		buildRouteShareDescription({
			distance_m: 10000,
			surface: 'trail',
			elevation_m: 250,
		}),
		'10.0 km trail route with 250 m elevation.',
	);
});

test('buildRouteShareDescription — null returns the generic fallback', () => {
	assert.equal(buildRouteShareDescription(null), 'A public route on Threkir.');
});

test('cleanShareTitle collapses whitespace, trims, and truncates long captions', () => {
	assert.equal(cleanShareTitle('  8 miles  with   the gang '), '8 miles with the gang');
	assert.equal(cleanShareTitle(''), '');
	assert.equal(cleanShareTitle('   '), '');
	assert.equal(cleanShareTitle(null), '');
	assert.equal(cleanShareTitle(42), '');
	const long = 'x'.repeat(200);
	const out = cleanShareTitle(long);
	assert.ok(out.length <= 80, `expected truncation, got ${out.length}`);
	assert.ok(out.endsWith('…'));
});

test('buildRunShareTitle prefers the runner caption over the distance/date formula', () => {
	const withTitle = buildRunShareTitle(
		{ distance_m: 8000, started_at: '2026-05-28T07:00:00Z', title: '8 miles with the Wednesday gang' },
		'Alex'
	);
	assert.equal(withTitle, '8 miles with the Wednesday gang — Threkir');
});

test('buildRunShareTitle falls back to the formula when no caption is set', () => {
	const noTitle = buildRunShareTitle(
		{ distance_m: 5000, started_at: '2026-05-28T07:00:00Z', title: '   ' },
		'Alex'
	);
	assert.equal(noTitle, '5.0 km run by Alex on 28 May 2026 — Threkir');
});

// ---------------- normaliseSiteUrl ----------------

test('normaliseSiteUrl strips trailing slashes and tolerates null', () => {
	assert.equal(normaliseSiteUrl('https://threkir.com/'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl('https://threkir.com///'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl('https://threkir.com'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl(null), '');
	assert.equal(normaliseSiteUrl(undefined), '');
});

// ---------------- buildRouteShareCanonical ----------------

test('buildRouteShareCanonical joins base + id single-slashed', () => {
	assert.equal(
		buildRouteShareCanonical('https://threkir.com', 'abc-123'),
		'https://threkir.com/share/route/abc-123'
	);
	assert.equal(
		buildRouteShareCanonical('https://threkir.com/', 'abc-123'),
		'https://threkir.com/share/route/abc-123'
	);
});

test('buildRouteShareCanonical with no base yields a root-relative path', () => {
	assert.equal(buildRouteShareCanonical(null, 'abc-123'), '/share/route/abc-123');
});

// ---------------- buildRouteJsonLd ----------------

test('buildRouteJsonLd emits a WebPage + breadcrumb graph with absolute URLs', () => {
	const json = buildRouteJsonLd(
		{ name: 'Hampstead Heath loop', distance_m: 10000, surface: 'trail' },
		{ id: 'r-1', base: 'https://threkir.com' }
	);
	const obj = JSON.parse(json);
	assert.equal(obj['@context'], 'https://schema.org');
	assert.equal(obj['@type'], 'WebPage');
	assert.equal(obj.name, 'Hampstead Heath loop');
	assert.equal(obj.url, 'https://threkir.com/share/route/r-1');
	assert.equal(obj.description, '10.0 km trail route.');
	assert.equal(obj.primaryImageOfPage.url, 'https://threkir.com/og/route/r-1.png');
	assert.equal(obj.breadcrumb['@type'], 'BreadcrumbList');
	const crumbs = obj.breadcrumb.itemListElement;
	assert.equal(crumbs.length, 3);
	assert.equal(crumbs[0].item, 'https://threkir.com/');
	assert.equal(crumbs[1].item, 'https://threkir.com/routes?tab=explore');
	assert.equal(crumbs[2].name, 'Hampstead Heath loop');
	// The current page (last crumb) has no `item` per Google guidance.
	assert.equal(crumbs[2].item, undefined);
});

test('buildRouteJsonLd falls back to a generic name when the route is null', () => {
	const obj = JSON.parse(buildRouteJsonLd(null, { id: 'r-2', base: 'https://threkir.com' }));
	assert.equal(obj.name, 'Route');
	assert.equal(obj.description, 'A public route on Threkir.');
});

test('buildRouteJsonLd escapes angle brackets so a route name cannot break out of the script tag', () => {
	const json = buildRouteJsonLd(
		{ name: '</script><img src=x onerror=alert(1)>', distance_m: 5000, surface: 'road' },
		{ id: 'r-3', base: 'https://threkir.com' }
	);
	// The raw serialized string must not contain a literal `<` or `>` —
	// they're escaped to their \u00xx forms so the injected
	// <script type="application/ld+json"> can't be terminated early.
	assert.ok(!json.includes('<'), 'expected no literal < in the JSON-LD string');
	assert.ok(!json.includes('>'), 'expected no literal > in the JSON-LD string');
	// It still round-trips to the original name once parsed.
	assert.equal(JSON.parse(json).name, '</script><img src=x onerror=alert(1)>');
});

// ---------------- buildRunShareCanonical ----------------

test('buildRunShareCanonical — absolute share/run URL', () => {
	assert.equal(
		buildRunShareCanonical('https://threkir.com', 'run-1'),
		'https://threkir.com/share/run/run-1'
	);
});

test('buildRunShareCanonical — trailing slash on base is normalised', () => {
	assert.equal(
		buildRunShareCanonical('https://threkir.com/', 'run-1'),
		'https://threkir.com/share/run/run-1'
	);
});

test('buildRunShareCanonical — null base yields a root-relative path', () => {
	assert.equal(buildRunShareCanonical(null, 'run-1'), '/share/run/run-1');
});

// ---------------- buildRunJsonLd ----------------

test('buildRunJsonLd — WebPage + breadcrumb, canonical + og image, no geo', () => {
	const obj = JSON.parse(
		buildRunJsonLd(
			{ distance_m: 10_000, started_at: '2026-05-11T07:00:00Z' },
			{ id: 'run-1', base: 'https://threkir.com', displayName: 'Jane' }
		)
	);
	assert.equal(obj['@type'], 'WebPage');
	assert.equal(obj.url, 'https://threkir.com/share/run/run-1');
	assert.equal(obj.primaryImageOfPage.url, 'https://threkir.com/og/run/run-1.png');
	// Name carries the distance/date phrase WITHOUT the " — Threkir"
	// site suffix (that belongs on <title>, not the schema name).
	assert.equal(obj.name, '10.0 km run by Jane on 11 May 2026');
	assert.equal(obj.name.includes('Threkir'), false);
	const crumbs = obj.breadcrumb.itemListElement;
	assert.equal(crumbs.length, 2);
	assert.equal(crumbs[0].item, 'https://threkir.com/');
	assert.equal(crumbs[1].name, '10.0 km run by Jane on 11 May 2026');
	assert.equal(crumbs[1].item, undefined);
	// No location must leak — the track is privacy-clipped server-side.
	assert.equal('geo' in obj, false);
});

test('buildRunJsonLd — a run caption becomes the schema name', () => {
	const obj = JSON.parse(
		buildRunJsonLd(
			{ distance_m: 10_000, started_at: '2026-05-11T07:00:00Z', title: 'Sunrise long run' },
			{ id: 'run-1', base: 'https://threkir.com', displayName: 'Jane' }
		)
	);
	assert.equal(obj.name, 'Sunrise long run');
});

test('buildRunJsonLd — null run falls back to a generic name', () => {
	const obj = JSON.parse(buildRunJsonLd(null, { id: 'run-2', base: 'https://threkir.com' }));
	assert.equal(obj.name, 'Run');
});

test('buildRunJsonLd — escapes angle brackets so a caption cannot break out of the script tag', () => {
	const json = buildRunJsonLd(
		{ distance_m: 5000, title: '</script><img src=x onerror=alert(1)>' },
		{ id: 'run-3', base: 'https://threkir.com' }
	);
	assert.ok(!json.includes('<'), 'expected no literal < in the JSON-LD string');
	assert.ok(!json.includes('>'), 'expected no literal > in the JSON-LD string');
	assert.equal(JSON.parse(json).name, '</script><img src=x onerror=alert(1)>');
});
