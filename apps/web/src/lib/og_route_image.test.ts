import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildMetaLine,
	buildRouteOgSvg,
	truncate,
	xmlEscape,
} from './og_route_image';

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

test('truncate — passes short strings through', () => {
	assert.equal(truncate('hi', 30), 'hi');
});

test('truncate — uses an ellipsis when over the cap', () => {
	const s = 'this string is long enough to be cut off';
	assert.equal(truncate(s, 10), 'this stri…');
});

test('xmlEscape — escapes the five reserved characters', () => {
	assert.equal(xmlEscape(`a<b>&c"d'e`), 'a&lt;b&gt;&amp;c&quot;d&apos;e');
});
