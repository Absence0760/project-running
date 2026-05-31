// Unit tests for the pure helpers exported from RouteTrackPreview.
// Static-map URL construction has to round-trip the polyline through
// MapTiler's `path=` parameter and downsample very long routes; pin
// the contract so a tweak to the encoding doesn't silently break
// every route preview.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

// We need to import the helpers from the Svelte module. Svelte 5
// compiles the `<script context="module">` (or `<script module>`)
// block into a re-exportable module, and `tsx --test` will route
// through svelte-package's resolver. For test purposes we point at
// the same .svelte file — the named exports are visible.
import { buildStaticMapUrl, downsampleForPreview } from './routes/static_map';

const KEY = 'test-key-123';

test('downsampleForPreview returns input unchanged when len <= target', () => {
	const pts = [
		{ lat: 1, lng: 1 },
		{ lat: 2, lng: 2 },
		{ lat: 3, lng: 3 },
	];
	const out = downsampleForPreview(pts, 60);
	assert.equal(out.length, 3);
	assert.deepEqual(out, pts);
});

test('downsampleForPreview reduces a long polyline to ~target points', () => {
	const pts = Array.from({ length: 1000 }, (_, i) => ({
		lat: 0.001 * i,
		lng: 0.001 * i,
	}));
	const out = downsampleForPreview(pts, 60);
	assert.equal(out.length, 60);
	// First + last preserved so the visible endpoints stay anchored.
	assert.equal(out[0].lat, pts[0].lat);
	assert.equal(out[out.length - 1].lat, pts[pts.length - 1].lat);
});

test('buildStaticMapUrl returns null when key missing', () => {
	const out = buildStaticMapUrl(
		[
			{ lat: 1, lng: 2 },
			{ lat: 3, lng: 4 },
		],
		{ w: 220, h: 140, style: 'streets-v2', key: '' },
	);
	assert.equal(out, null, 'must return null when no key — caller falls back to SVG');
});

test('buildStaticMapUrl returns null when fewer than 2 points', () => {
	const out = buildStaticMapUrl([{ lat: 1, lng: 2 }], {
		w: 220,
		h: 140,
		style: 'streets-v2',
		key: KEY,
	});
	assert.equal(out, null, 'single-waypoint routes have no polyline to draw');
});

test('buildStaticMapUrl includes the key, dimensions, style, and path', () => {
	const out = buildStaticMapUrl(
		[
			{ lat: 51.5074, lng: -0.1276 },
			{ lat: 51.5085, lng: -0.1284 },
		],
		{ w: 220, h: 140, style: 'streets-v2', key: KEY },
	)!;
	assert.ok(out.startsWith('https://api.maptiler.com/maps/streets-v2/static/auto/'));
	assert.match(out, /\/220x140@2x\.png/);
	assert.match(out, new RegExp(`key=${KEY}`));
	// Path includes a transparent fill (so closed loops don't render
	// as a black polygon), the brand stroke (URL-encoded #), width,
	// and coordinates.
	assert.match(out, /fill:%23ffffff00\|/);
	assert.match(out, /stroke:%23F2A07B\|width:4\|/);
	assert.match(out, /-0\.12760,51\.50740/);
	assert.match(out, /-0\.12840,51\.50850/);
});
