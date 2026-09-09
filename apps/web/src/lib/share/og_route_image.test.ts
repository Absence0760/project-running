import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildMetaLine,
	buildRouteOgSvg,
} from './og_route_image';
import { escapeHtml } from '../util/html_escape';
import { estimateSvgTextWidthPx } from './svg_text_width';

const sampleTrack = [
	{ lat: 51.5, lng: -0.1 },
	{ lat: 51.51, lng: -0.1 },
	{ lat: 51.51, lng: -0.09 },
	{ lat: 51.5, lng: -0.09 },
	{ lat: 51.5, lng: -0.1 },
];

test('buildRouteOgSvg — emits a 1200x630 svg root', () => {
	const svg = buildRouteOgSvg({ name: 'Test', track: sampleTrack });
	assert.match(svg, /<svg [^>]*viewBox="0 0 1200 630"/);
	assert.match(svg, /width="1200" height="630"/);
	assert.match(svg.trimEnd(), /<\/svg>$/);
});

test('buildRouteOgSvg — renders the brand strap + route name', () => {
	const svg = buildRouteOgSvg({ name: 'Hampstead Heath loop', track: sampleTrack });
	assert.ok(svg.includes('Threkir'));
	assert.ok(svg.includes('Hampstead Heath loop'));
});

test('buildRouteOgSvg — includes the polyline path and the start/end caps', () => {
	const svg = buildRouteOgSvg({ name: 'X', track: sampleTrack });
	assert.match(svg, /<path d="M[\d., ]+L[\d., L]+"/);
	// Two <circle> elements — green start + red end.
	assert.match(svg, /fill="#16a34a"/);
	assert.match(svg, /fill="#dc2626"/);
});

test('buildRouteOgSvg — track with <2 points falls back to title-only', () => {
	const svg = buildRouteOgSvg({ name: 'Empty', track: [] });
	assert.ok(svg.includes('Empty'));
	assert.ok(!svg.includes('<path'));
	assert.ok(!svg.includes('fill="#16a34a"'));
});

test('buildRouteOgSvg — distance + surface render in the meta line', () => {
	const svg = buildRouteOgSvg({
		name: 'X',
		distance_m: 10000,
		surface: 'road',
		track: sampleTrack,
	});
	assert.ok(svg.includes('10.0 km · road'));
});

test('buildRouteOgSvg — null name falls back to "Untitled route"', () => {
	const svg = buildRouteOgSvg({ name: null, track: sampleTrack });
	assert.ok(svg.includes('Untitled route'));
});

test('buildRouteOgSvg — escapes special characters in name + meta', () => {
	const svg = buildRouteOgSvg({
		name: 'A&B<C>',
		surface: '"trail"',
		distance_m: 5000,
		track: sampleTrack,
	});
	assert.ok(svg.includes('A&amp;B&lt;C&gt;'));
});

test('buildMetaLine — km only when surface absent', () => {
	assert.equal(buildMetaLine(5000, null), '5.0 km');
});

test('buildMetaLine — surface only when distance absent', () => {
	assert.equal(buildMetaLine(null, 'road'), 'road');
});

test('buildMetaLine — empty when both absent', () => {
	assert.equal(buildMetaLine(null, null), '');
});

test('buildMetaLine — marathon uses two-decimal km', () => {
	assert.equal(buildMetaLine(42195, 'road'), '42.20 km · road');
});

/// The title as it reaches the rasteriser.
function titleOf(svg: string): string {
	return /font-size="56"[^>]*>([^<]*)</.exec(svg)?.[1] ?? '';
}

/// The card's title box: W 1200 less two 40 px pads.
const TITLE_BOX_PX = 1120;

test('buildRouteOgSvg — a long route name is clipped to the card, ellipsis included', () => {
	const name = 'a route name far longer than the title line can hold';
	const title = titleOf(buildRouteOgSvg({ name, track: sampleTrack }));
	assert.ok(title.endsWith('…'));
	assert.ok(name.startsWith(title.slice(0, -1)));
	assert.ok(estimateSvgTextWidthPx(title, 56) <= TITLE_BOX_PX);
});

test('buildRouteOgSvg — the title budget is the box, not a cluster count', () => {
	// Both names are 30 clusters, which the old budget passed unclipped; one of
	// them painted 1645 px into a 1120 px box and the other 1142. A budget in
	// clusters cannot bound a box in pixels, so neither survives whole now and
	// the wider one is cut harder.
	const capitals = titleOf(buildRouteOgSvg({ name: 'M'.repeat(30), track: sampleTrack }));
	const lower = titleOf(buildRouteOgSvg({ name: 'n'.repeat(30), track: sampleTrack }));
	for (const title of [capitals, lower]) {
		assert.ok(title.endsWith('…'), `${JSON.stringify(title)} was not clipped at all`);
		assert.ok(estimateSvgTextWidthPx(title, 56) <= TITLE_BOX_PX);
	}
	assert.ok(
		capitals.length < lower.length,
		`capitals kept ${capitals.length} against lowercase's ${lower.length}`
	);
});

test('escapeHtml — escapes the five reserved characters', () => {
	assert.equal(escapeHtml(`a<b>&c"d'e`), 'a&lt;b&gt;&amp;c&quot;d&#39;e');
});

test('buildRouteOgSvg — a route name cut mid-emoji does not reach the rasteriser broken', () => {
	const svg = buildRouteOgSvg({
		name: `${'a'.repeat(28)}\u{1F3C3} and more of the name`,
		track: sampleTrack,
	});
	assert.equal(Buffer.from(svg, 'utf8').toString('utf8'), svg);
	assert.doesNotMatch(svg, /[\uD800-\uDBFF](?![\uDC00-\uDFFF])/);
});
