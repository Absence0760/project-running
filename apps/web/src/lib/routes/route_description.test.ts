import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	assembleEnglish,
	describeRoute,
	elevationProfile,
	localisedTemplate,
	routeShape,
	LOOP_CLOSE_M,
	type RouteDescriptionInput,
} from './route_description';

/**
 * The `describeRoute` / `elevationProfile` / `routeShape` /
 * `assembleEnglish` cases are the twin of
 * `apps/mobile_android/test/route_description_test.dart` — keep those 12
 * in lockstep. The `localisedTemplate` cases below are web-only (the
 * mobile UI renders its own localised string from the same parts) and
 * are not part of the twin count.
 */

/// A fake i18n + unit layer for localisedTemplate: the translator echoes
/// the key (so assertions pin which keys + slots are used) and the
/// formatter renders metres in the chosen unit (so we can assert the
/// builder is unit-aware rather than baking km).
function fakeI18n(unit: 'km' | 'mi' = 'km') {
	return {
		t: (key: string, params?: Record<string, string | number>) =>
			params ? `${key}{${JSON.stringify(params)}}` : key,
		formatDistance: (m: number) =>
			unit === 'mi' ? `${(m / 1609.344).toFixed(2)}mi` : `${m}m`,
	};
}

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

// ── localisedTemplate (web-only; not part of the twin count) ──

test('localisedTemplate emits a climb clause for an elevated route', () => {
	const parts = describeRoute({
		name: 'Summit',
		distanceM: 12000,
		elevationM: 480,
		surface: 'trail',
		start: { lat: 51.5, lng: -0.12 },
		end: { lat: 51.7, lng: 0.0 },
	});
	const out = localisedTemplate(parts, 'Summit', fakeI18n());
	assert.match(out, /routeDetail\.descSentence/);
	assert.match(out, /routeDetail\.descClimb/);
	assert.doesNotMatch(out, /routeDetail\.descFlat/);
	assert.match(out, /routeDetail\.descShapePointToPoint/);
	assert.match(out, /routeDetail\.descSurfaceTrail/);
	assert.match(out, /routeDetail\.descElevHilly/);
	assert.match(out, /12000m/); // distance through formatDistance
	assert.match(out, /480m/); // gain through formatDistance
});

test('localisedTemplate emits the flat clause when there is no climbing', () => {
	const parts = describeRoute({
		name: 'Track',
		distanceM: 5000,
		elevationM: 0,
		surface: 'road',
		start: { lat: 0, lng: 0 },
		end: { lat: 0, lng: 0 },
	});
	const out = localisedTemplate(parts, 'Track', fakeI18n());
	assert.match(out, /routeDetail\.descFlat/);
	assert.doesNotMatch(out, /routeDetail\.descClimb/);
	assert.match(out, /routeDetail\.descShapeLoop/);
	assert.match(out, /routeDetail\.descSurfaceRoad/);
});

test('localisedTemplate renders distance in the viewer unit (mi)', () => {
	const parts = describeRoute({
		name: 'x',
		distanceM: 10000,
		elevationM: 0,
		surface: null,
		start: { lat: 0, lng: 0 },
		end: { lat: 0, lng: 0 },
	});
	const out = localisedTemplate(parts, 'x', fakeI18n('mi'));
	assert.match(out, /6\.21mi/); // 10000 m → 6.21 mi
});

test('localisedTemplate omits the surface word when surface is null', () => {
	const parts = describeRoute({
		name: 'x',
		distanceM: 5000,
		elevationM: 0,
		surface: null,
		start: { lat: 0, lng: 0 },
		end: { lat: 0, lng: 0 },
	});
	const out = localisedTemplate(parts, 'x', fakeI18n());
	assert.doesNotMatch(out, /routeDetail\.descSurface/);
});
