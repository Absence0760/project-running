import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toGpx, toRunGpx, toKml } from './gpx';

const COORDS_3: [number, number][] = [
	[8.54, 47.37],
	[8.541, 47.371],
	[8.542, 47.372],
];
const ELEVS_3 = [400, 410, 420];

test('toGpx — has GPX 1.1 namespace + creator', () => {
	const xml = toGpx('Morning loop', COORDS_3, ELEVS_3);
	assert.match(xml, /<gpx version="1.1" creator="Threkir"/);
	assert.match(xml, /xmlns="http:\/\/www\.topografix\.com\/GPX\/1\/1"/);
});

test('toGpx — emits one trkpt per coordinate', () => {
	const xml = toGpx('Loop', COORDS_3, ELEVS_3);
	const matches = xml.match(/<trkpt /g) ?? [];
	assert.equal(matches.length, 3);
});

test('toGpx — coordinates are written as lat/lon attributes in the right slots', () => {
	const xml = toGpx('Loop', [[8.54, 47.37]], [400]);
	// `[lng, lat]` in input maps to `lat=lat lon=lng` on the trkpt.
	assert.match(xml, /<trkpt lat="47\.37" lon="8\.54">/);
	assert.match(xml, /<ele>400<\/ele>/);
});

test('toGpx — missing elevation falls back to 0', () => {
	const xml = toGpx('Loop', [[8.54, 47.37]], []);
	assert.match(xml, /<ele>0<\/ele>/);
});

test('toGpx — escapes XML metacharacters in the name', () => {
	const xml = toGpx('Tom & Jerry <fast>', [[0, 0]], [0]);
	assert.ok(!xml.includes('<fast>'), 'angle brackets in name must be escaped');
	assert.ok(xml.includes('Tom &amp; Jerry &lt;fast&gt;'));
});

test('toGpx — empty coordinates produces a well-formed but empty trkseg', () => {
	const xml = toGpx('Empty', [], []);
	assert.match(xml, /<trkseg>/);
	assert.match(xml, /<\/trkseg>/);
	assert.equal((xml.match(/<trkpt /g) ?? []).length, 0);
});

test('toRunGpx — emits per-point time when present', () => {
	const xml = toRunGpx('Run', '2026-04-01T07:00:00Z', [
		{ lat: 47.37, lng: 8.54, ele: 400, ts: '2026-04-01T07:00:00Z' },
		{ lat: 47.371, lng: 8.541, ele: 405, ts: '2026-04-01T07:00:10Z' },
	]);
	assert.match(xml, /<time>2026-04-01T07:00:00Z<\/time>/);
	assert.match(xml, /<time>2026-04-01T07:00:10Z<\/time>/);
});

test('toRunGpx — omits ele when null and time when missing', () => {
	const xml = toRunGpx('Run', '2026-04-01T07:00:00Z', [
		{ lat: 47.37, lng: 8.54, ele: null, ts: null },
	]);
	assert.ok(!xml.includes('<ele>'), 'no <ele> when ele is null');
	// The header still has its own <time> in metadata; the per-trkpt
	// shouldn't carry one when ts is null. Count the occurrences inside
	// the trkpt block.
	const trkpt = xml.match(/<trkpt[^>]*>.*?<\/trkpt>/s)?.[0] ?? '';
	assert.ok(!trkpt.includes('<time>'), 'no per-point <time> when ts is null');
});

test('toRunGpx — header time uses the provided startedAtIso', () => {
	const xml = toRunGpx('Run', '2025-12-31T23:59:59Z', [{ lat: 0, lng: 0 }]);
	// The metadata <time> should reflect the run start, not the local
	// generation timestamp.
	assert.match(xml, /<metadata>\s*<name>Run<\/name>\s*<time>2025-12-31T23:59:59Z<\/time>/);
});

test('toRunGpx — escapes the name', () => {
	const xml = toRunGpx('5K "PB"', '2026-04-01T00:00:00Z', [{ lat: 0, lng: 0 }]);
	assert.ok(xml.includes('5K &quot;PB&quot;'));
});

test('toKml — emits a coordinates string in lng,lat,ele order', () => {
	const xml = toKml('Loop', COORDS_3, ELEVS_3);
	assert.match(xml, /<kml xmlns="http:\/\/www\.opengis\.net\/kml\/2\.2">/);
	assert.match(xml, /8\.54,47\.37,400/);
	assert.match(xml, /8\.541,47\.371,410/);
	assert.match(xml, /8\.542,47\.372,420/);
});

test('toKml — missing elevation entries default to 0', () => {
	const xml = toKml('Loop', [[8.54, 47.37]], []);
	assert.match(xml, /8\.54,47\.37,0/);
});

test('toKml — escapes the name in both the Document and the Placemark', () => {
	const xml = toKml('A & B', [[0, 0]], [0]);
	const occurrences = (xml.match(/A &amp; B/g) ?? []).length;
	assert.ok(occurrences >= 2, 'name escaped in both Document and Placemark');
});
