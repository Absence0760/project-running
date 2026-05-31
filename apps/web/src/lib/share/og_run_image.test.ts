import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRunOgSvg, buildSubline, xmlEscape } from './og_run_image';

// ---------------- buildRunOgSvg ----------------

test('buildRunOgSvg — emits a 1200x630 svg root', () => {
	const svg = buildRunOgSvg({});
	assert.match(svg, /<svg [^>]*viewBox="0 0 1200 630"/);
	assert.match(svg, /width="1200" height="630"/);
	assert.match(svg.trimEnd(), /<\/svg>$/);
});

test('buildRunOgSvg — renders the brand strap', () => {
	const svg = buildRunOgSvg({});
	assert.ok(svg.includes('Threkir'));
});

test('buildRunOgSvg — distance becomes the hero numeral', () => {
	const svg = buildRunOgSvg({ distance_m: 5000 });
	assert.ok(svg.includes('5.0 km'));
});

test('buildRunOgSvg — falls back to "Run" when distance is null', () => {
	const svg = buildRunOgSvg({});
	// The hero text element should carry the fallback string.
	assert.match(svg, /text-anchor="middle"[^>]*>Run</);
});

test('buildRunOgSvg — sub-line carries runner + date', () => {
	const svg = buildRunOgSvg({
		distance_m: 5000,
		started_at: '2026-05-11T00:00:00Z',
		displayName: 'Jared Howard',
	});
	assert.ok(svg.includes('by Jared Howard on 11 May 2026'));
});

test('buildRunOgSvg — source tag rendered when present', () => {
	const svg = buildRunOgSvg({ distance_m: 5000, source: 'strava' });
	assert.ok(svg.includes('strava'));
});

test('buildRunOgSvg — null source omits the bottom-right tag', () => {
	const svg = buildRunOgSvg({ distance_m: 5000 });
	// Only two text elements expected (brand strap + hero); no source.
	const sourceTags = (svg.match(/text-anchor="end"/g) ?? []).length;
	assert.equal(sourceTags, 0);
});

test('buildRunOgSvg — escapes display name + source', () => {
	const svg = buildRunOgSvg({
		distance_m: 5000,
		displayName: 'A&B',
		source: '<x>',
	});
	assert.ok(svg.includes('by A&amp;B'));
	assert.ok(svg.includes('&lt;x&gt;'));
});

// ---------------- buildSubline ----------------

test('buildSubline — by NAME on DATE when both present', () => {
	assert.equal(
		buildSubline({
			displayName: 'Jared',
			started_at: '2026-05-11T00:00:00Z',
		}),
		'by Jared on 11 May 2026',
	);
});

test('buildSubline — by NAME alone when no date', () => {
	assert.equal(buildSubline({ displayName: 'Jared' }), 'by Jared');
});

test('buildSubline — date alone when no display name', () => {
	assert.equal(
		buildSubline({ started_at: '2026-05-11T00:00:00Z' }),
		'11 May 2026',
	);
});

test('buildSubline — empty string when both absent', () => {
	assert.equal(buildSubline({}), '');
});

test('buildSubline — whitespace-only display name is treated as absent', () => {
	assert.equal(
		buildSubline({
			displayName: '   ',
			started_at: '2026-05-11T00:00:00Z',
		}),
		'11 May 2026',
	);
});

// ---------------- xmlEscape ----------------

test('xmlEscape — escapes the five reserved characters', () => {
	assert.equal(xmlEscape(`a<b>&c"d'e`), 'a&lt;b&gt;&amp;c&quot;d&apos;e');
});
