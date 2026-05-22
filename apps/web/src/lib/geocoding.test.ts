import { test } from 'node:test';
import assert from 'node:assert/strict';

import { bboxRadius, haversineM } from './geocoding_math';

test('bboxRadius for the state of Virginia bbox returns roughly half its diagonal', () => {
	// Approximate MapTiler bbox for "Virginia, United States".
	const bbox: [number, number, number, number] = [-83.675, 36.541, -75.166, 39.466];
	const center = { lng: -78.6569, lat: 37.4316 };
	const r = bboxRadius(bbox, center);
	// Virginia is ~700km wide and ~300km tall — radius from centroid
	// to a corner should land in the 400-500km band.
	assert.ok(r > 350_000, `expected > 350km, got ${r}`);
	assert.ok(r < 550_000, `expected < 550km, got ${r}`);
});

test('bboxRadius for a city-scale bbox returns roughly the city diagonal', () => {
	// Approximate MapTiler bbox for "Richmond, Virginia".
	const bbox: [number, number, number, number] = [-77.59, 37.45, -77.39, 37.61];
	const center = { lng: -77.49, lat: 37.54 };
	const r = bboxRadius(bbox, center);
	assert.ok(r > 8_000, `expected > 8km, got ${r}`);
	assert.ok(r < 25_000, `expected < 25km, got ${r}`);
});

test('haversineM returns 0 for identical points', () => {
	const p = { lng: -77.0, lat: 38.9 };
	assert.equal(haversineM(p, p), 0);
});

test('haversineM is symmetric', () => {
	const a = { lng: -77.0, lat: 38.9 };
	const b = { lng: -77.1, lat: 38.91 };
	assert.equal(haversineM(a, b).toFixed(2), haversineM(b, a).toFixed(2));
});

test('haversineM ballparks the Washington DC ↔ Richmond distance correctly', () => {
	// DC ≈ (38.90, -77.04), Richmond ≈ (37.54, -77.43) — ~150km apart.
	const dc = { lng: -77.04, lat: 38.90 };
	const richmond = { lng: -77.43, lat: 37.54 };
	const d = haversineM(dc, richmond);
	assert.ok(d > 140_000 && d < 170_000, `expected ~150km, got ${d}`);
});

// ---- searchPlaces (network-mocked) --------------------------------------
//
// `searchPlaces` dispatches on PUBLIC_MAPTILER_KEY (set → MapTiler;
// empty → Nominatim). We can't easily flip the env mid-test from
// node:test (the helper reads it once at module load), so this test
// pins the no-key path that's actually live in the local-Protomaps
// dev stack — and asserts the input-validation + transport-error
// branches that don't depend on which provider was chosen.

import { searchPlacesWithKey } from './geocoding_math';

// Helper: call the env-free dispatcher directly so the tests don't
// depend on SvelteKit's `$env/dynamic/public` runtime. Production
// behavior is identical — `geocoding.searchPlaces` just injects
// `PUBLIC_MAPTILER_KEY` and delegates here.
const searchPlaces = (q: string, limit?: number, signal?: AbortSignal) =>
	searchPlacesWithKey('', q, limit, signal);

test('searchPlaces returns [] for short queries (< 2 chars)', async () => {
	// Short-circuit before any network call.
	assert.deepEqual(await searchPlaces(''), []);
	assert.deepEqual(await searchPlaces('a'), []);
});

test('searchPlaces returns [] when fetch throws (network down)', async () => {
	// Patch global fetch to simulate a network error. The helper
	// must swallow + return [] (never throw) — the search box
	// degrades to "no results" identically to "key missing".
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => {
		throw new Error('network unreachable');
	};
	try {
		const out = await searchPlaces('Richmond');
		assert.deepEqual(out, []);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('searchPlaces returns [] when fetch returns non-OK', async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response('', { status: 503 })) as typeof fetch;
	try {
		const out = await searchPlaces('Richmond');
		assert.deepEqual(out, []);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('searchPlaces (Nominatim path) parses lat/lon strings + skips '
	+ 'malformed rows', async () => {
	// Nominatim returns lat/lon as STRINGS; the helper parseFloats
	// them. Stub a typical response.
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response(JSON.stringify([
			{ display_name: 'Richmond, Virginia', lat: '37.5407', lon: '-77.4360' },
			{ display_name: 'Bad row no lat', lon: '0' },
			{ display_name: 'Bad row NaN', lat: 'not-a-number', lon: '0' },
			{ display_name: 'Charlottesville, VA', lat: '38.029', lon: '-78.4767' },
		]), { status: 200 })) as typeof fetch;
	// We're in the no-MapTiler-key path (the test env has no
	// PUBLIC_MAPTILER_KEY set), so this exercises Nominatim.
	const globalThisAny = globalThis as unknown as { navigator?: { language?: string } };
	if (!globalThisAny.navigator) {
		globalThisAny.navigator = { language: 'en' };
	}
	try {
		const out = await searchPlaces('Virginia');
		assert.equal(out.length, 2,
			'malformed rows must be dropped, not yielded as NaN coords');
		assert.equal(out[0].name, 'Richmond, Virginia');
		assert.ok(Math.abs(out[0].lat - 37.5407) < 1e-6);
		assert.ok(Math.abs(out[0].lng - (-77.4360)) < 1e-6);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('searchPlaces (Nominatim path) handles empty response array', async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response('[]', { status: 200 })) as typeof fetch;
	try {
		const out = await searchPlaces('nowhere-real');
		assert.deepEqual(out, []);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('searchPlaces respects the limit param in the request URL', async () => {
	let capturedUrl = '';
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async (url: string | URL | Request) => {
		capturedUrl = url.toString();
		return new Response('[]', { status: 200 });
	}) as typeof fetch;
	try {
		await searchPlaces('Richmond', 3);
		assert.ok(capturedUrl.includes('limit=3'),
			`expected limit=3 in URL, got: ${capturedUrl}`);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('searchPlaces URL-encodes the query (handles spaces + ampersands)',
	async () => {
		let capturedUrl = '';
		const originalFetch = globalThis.fetch;
		globalThis.fetch = (async (url: string | URL | Request) => {
			capturedUrl = url.toString();
			return new Response('[]', { status: 200 });
		}) as typeof fetch;
		try {
			await searchPlaces('Richmond, VA & nearby');
			// URLSearchParams uses `+` for spaces (form-urlencoded);
			// encodeURIComponent uses `%20`. Both are valid + Nominatim
			// accepts either. The load-bearing assertion is that the
			// raw `&` (which would break the query string) is encoded.
			const parsed = new URL(capturedUrl);
			const q = parsed.searchParams.get('q');
			assert.equal(q, 'Richmond, VA & nearby',
				`q param should decode back to the original: got ${q}`);
		} finally {
			globalThis.fetch = originalFetch;
		}
	});

test('searchPlaces (Nominatim path) includes the `email` contact-channel '
	+ 'param required by their usage policy', async () => {
	// Public Nominatim's usage policy
	// (https://operations.osmfoundation.org/policies/nominatim/)
	// asks for a meaningful contact channel. Browsers won't let us
	// set a custom User-Agent from JS, so the next-best signal is
	// the `email` query param. The May 2026 audit pass surfaced
	// this — without the param, sustained traffic was at risk of
	// silent IP bans.
	let capturedUrl = '';
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async (url: string | URL | Request) => {
		capturedUrl = url.toString();
		return new Response('[]', { status: 200 });
	}) as typeof fetch;
	try {
		await searchPlaces('Richmond');
		const parsed = new URL(capturedUrl);
		assert.equal(parsed.host, 'nominatim.openstreetmap.org',
			'should be on the Nominatim path (no MapTiler key set)');
		assert.ok(parsed.searchParams.get('email'),
			"Nominatim policy requires an `email` contact param");
	} finally {
		globalThis.fetch = originalFetch;
	}
});

// ---- geocodePlace (Nominatim fallback added in the May 2026 audit) ----

import { geocodePlaceWithKey } from './geocoding_math';
// Test the env-free dispatcher directly so we don't need Vite's
// `$env/dynamic/public` runtime.
const geocodePlace = (q: string, signal?: AbortSignal) =>
	geocodePlaceWithKey('', q, signal);

test('geocodePlace returns null for short queries (no provider call)',
	async () => {
		let fetchCalls = 0;
		const originalFetch = globalThis.fetch;
		globalThis.fetch = (async () => {
			fetchCalls++;
			return new Response('[]', { status: 200 });
		}) as typeof fetch;
		try {
			const out = await geocodePlace('');
			assert.equal(out, null);
			const out2 = await geocodePlace('a');
			assert.equal(out2, null);
			assert.equal(fetchCalls, 0, 'no network call for short queries');
		} finally {
			globalThis.fetch = originalFetch;
		}
	});

test('geocodePlace falls back to Nominatim when no MapTiler key, '
	+ 'parses bbox into bbox-derived radius', async () => {
	// Nominatim's boundingbox shape is
	// `[minLat, maxLat, minLng, maxLng]` (strings, lat-first) —
	// different from MapTiler's `[w, s, e, n]` floats. The fallback
	// converts; pin that the conversion math actually produces a
	// reasonable radius.
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response(
			JSON.stringify([
				{
					display_name: 'Virginia, United States',
					lat: '37.4315',
					lon: '-78.6569',
					boundingbox: ['36.5407', '39.4660', '-83.6754', '-75.2422'],
					class: 'boundary',
					type: 'administrative',
				},
			]),
			{ status: 200 },
		)) as typeof fetch;
	try {
		const out = await geocodePlace('Virginia');
		assert.ok(out, 'should return a geocoded place');
		assert.equal(out!.name, 'Virginia, United States');
		assert.ok(Math.abs(out!.center.lat - 37.4315) < 1e-6);
		assert.ok(Math.abs(out!.center.lng - -78.6569) < 1e-6);
		// Virginia centroid → corner is ~400-500km. Pin the right band.
		assert.ok(out!.radiusM > 350_000,
			`expected > 350km radius, got ${out!.radiusM}`);
		assert.ok(out!.radiusM < 550_000,
			`expected < 550km radius, got ${out!.radiusM}`);
		// class=boundary + type=administrative → 'region'.
		assert.equal(out!.placeType, 'region');
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('geocodePlace Nominatim path: no bbox → default 5km radius', async () => {
	// An address-level POI may come back without a boundingbox.
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response(
			JSON.stringify([{ display_name: 'Some address', lat: '37.5', lon: '-77.4' }]),
			{ status: 200 },
		)) as typeof fetch;
	try {
		const out = await geocodePlace('123 Main St');
		assert.ok(out);
		assert.equal(out!.radiusM, 5000);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('geocodePlace returns null when Nominatim returns []', async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response('[]', { status: 200 })) as typeof fetch;
	try {
		assert.equal(await geocodePlace('not-a-real-place-anywhere'), null);
	} finally {
		globalThis.fetch = originalFetch;
	}
});

test('geocodePlace returns null when fetch throws', async () => {
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () => {
		throw new Error('network down');
	};
	try {
		assert.equal(await geocodePlace('Virginia'), null);
	} finally {
		globalThis.fetch = originalFetch;
	}
});
