import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	assembleEnglish,
	describeRoute,
	elevationProfile,
	routeShape,
	LOOP_CLOSE_M,
	type RouteDescriptionInput,
} from './route_description';

/**
 * Twin of `apps/mobile_android/test/route_description_test.dart` — keep
 * the cases and count in lockstep.
 */

test('elevationProfile buckets gain-per-km into the four bands', () => {
	// 0 m over 10 km → flat
	assert.equal(elevationProfile(10000, 0).profile, 'flat');
	// 50 m over 10 km = 5 m/km → still flat (below rolling=10)
	assert.equal(elevationProfile(10000, 50).profile, 'flat');
	// 150 m over 10 km = 15 m/km → rolling
	assert.equal(elevationProfile(10000, 150).profile, 'rolling');
	// 400 m over 10 km = 40 m/km → hilly
	assert.equal(elevationProfile(10000, 400).profile, 'hilly');
	// 1000 m over 10 km = 100 m/km → mountainous
	assert.equal(elevationProfile(10000, 1000).profile, 'mountainous');
});

test('elevationProfile thresholds are inclusive lower bounds', () => {
	assert.equal(elevationProfile(1000, 10).profile, 'rolling'); // exactly 10 m/km
	assert.equal(elevationProfile(1000, 30).profile, 'hilly'); // exactly 30 m/km
	assert.equal(elevationProfile(1000, 70).profile, 'mountainous'); // exactly 70 m/km
});

test('elevationProfile guards zero / negative distance', () => {
	assert.deepEqual(elevationProfile(0, 500), { profile: 'flat', gainPerKm: 0 });
	assert.deepEqual(elevationProfile(-10, 500), { profile: 'flat', gainPerKm: 0 });
});

test('routeShape reports a loop when start ≈ end', () => {
	const input: RouteDescriptionInput = {
		name: 'Park loop',
		distanceM: 5000,
		elevationM: 20,
		surface: 'road',
		start: { lat: 51.5, lng: -0.12 },
		end: { lat: 51.5, lng: -0.12 },
	};
	assert.equal(routeShape(input), 'loop');
});

test('routeShape reports point_to_point when endpoints differ', () => {
	const input: RouteDescriptionInput = {
		name: 'Trail run',
		distanceM: 12000,
		elevationM: 300,
		surface: 'trail',
		start: { lat: 51.5, lng: -0.12 },
		end: { lat: 51.6, lng: -0.05 },
	};
	assert.equal(routeShape(input), 'point_to_point');
});

test('routeShape falls back to point_to_point without endpoints', () => {
	assert.equal(
		routeShape({ name: 'x', distanceM: 5000, elevationM: null, surface: null }),
		'point_to_point',
	);
});

test('LOOP_CLOSE_M boundary: a small gap still reads as a loop', () => {
	// ~50 m east of the start (well under LOOP_CLOSE_M=75)
	const start = { lat: 51.5, lng: -0.12 };
	const end = { lat: 51.5, lng: -0.12 + 0.0007 }; // ~48 m at this latitude
	assert.ok(LOOP_CLOSE_M >= 75);
	assert.equal(routeShape({ name: 'x', distanceM: 5000, elevationM: 0, surface: null, start, end }), 'loop');
});

test('describeRoute assembles the structured parts', () => {
	const parts = describeRoute({
		name: 'Riverside 10K',
		distanceM: 10000,
		elevationM: 150,
		surface: 'mixed',
		start: { lat: 51.5, lng: -0.12 },
		end: { lat: 51.5, lng: -0.12 },
	});
	assert.equal(parts.band, '10k');
	assert.equal(parts.surface, 'mixed');
	assert.equal(parts.elevation, 'rolling');
	assert.equal(parts.gainPerKm, 15);
	assert.equal(parts.shape, 'loop');
});

test('describeRoute returns a null band for between-band distances', () => {
	const parts = describeRoute({ name: 'x', distanceM: 15000, elevationM: 0, surface: 'road' });
	assert.equal(parts.band, null);
});

test('describeRoute clamps non-finite / negative inputs to zero', () => {
	const parts = describeRoute({
		name: 'x',
		distanceM: Number.NaN,
		elevationM: -500,
		surface: null,
	});
	assert.equal(parts.distanceM, 0);
	assert.equal(parts.elevationM, 0);
	assert.equal(parts.elevation, 'flat');
});

test('assembleEnglish produces a hilly point-to-point sentence', () => {
	const parts = describeRoute({
		name: 'Summit Trail',
		distanceM: 12000,
		elevationM: 480,
		surface: 'trail',
		start: { lat: 51.5, lng: -0.12 },
		end: { lat: 51.7, lng: 0.0 },
	});
	const text = assembleEnglish(parts, 'Summit Trail');
	assert.match(text, /^Summit Trail is a 12\.0 km trail point-to-point route/);
	assert.match(text, /480 m of climbing \(hilly, about 40 m per km\)\.$/);
});

test('assembleEnglish handles a flat road loop with no climbing', () => {
	const parts = describeRoute({
		name: 'Track',
		distanceM: 5000,
		elevationM: 0,
		surface: 'road',
		start: { lat: 0, lng: 0 },
		end: { lat: 0, lng: 0 },
	});
	const text = assembleEnglish(parts, 'Track');
	assert.equal(text, 'Track is a 5.0 km road loop route with little to no elevation change.');
});
