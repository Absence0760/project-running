import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildRouteShareDescription,
	buildRouteShareTitle,
	buildRunShareDescription,
	buildRunShareTitle,
	formatDateStable,
	formatKmStable,
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

test('formatDateStable — UTC en-GB shape', () => {
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
	assert.equal(buildRunShareTitle(null), 'Run — Run Onward');
});

test('buildRunShareTitle — full meta produces a deterministic title', () => {
	assert.equal(
		buildRunShareTitle({ distance_m: 5000, started_at: '2026-05-11T00:00:00Z' }),
		'5.0 km run on 11 May 2026 — Run Onward',
	);
});

test('buildRunShareTitle — distance-only run omits date', () => {
	assert.equal(buildRunShareTitle({ distance_m: 10000 }), '10.0 km run — Run Onward');
});

test('buildRunShareTitle — date-only run omits distance', () => {
	assert.equal(
		buildRunShareTitle({ started_at: '2026-05-11T00:00:00Z' }),
		'Run on 11 May 2026 — Run Onward',
	);
});

// ---------------- buildRunShareDescription ----------------

test('buildRunShareDescription — meta is appended before the lead', () => {
	const desc = buildRunShareDescription({
		distance_m: 5000,
		started_at: '2026-05-11T00:00:00Z',
	});
	assert.ok(desc.startsWith('5.0 km on 11 May 2026.'));
	assert.ok(desc.includes('Map, splits, and elevation on Run Onward.'));
});

test('buildRunShareDescription — null run keeps generic copy', () => {
	assert.equal(
		buildRunShareDescription(null),
		'View a public run on Run Onward — map, splits, elevation, kudos.',
	);
});

// ---------------- buildRouteShareTitle ----------------

test('buildRouteShareTitle — uses the route name when present', () => {
	assert.equal(
		buildRouteShareTitle({ name: 'Hampstead Heath loop' }),
		'Hampstead Heath loop — Run Onward',
	);
});

test('buildRouteShareTitle — missing name falls back to generic', () => {
	assert.equal(buildRouteShareTitle({ distance_m: 5000 }), 'Route — Run Onward');
	assert.equal(buildRouteShareTitle(null), 'Route — Run Onward');
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
	assert.equal(buildRouteShareDescription(null), 'A public route on Run Onward.');
});
