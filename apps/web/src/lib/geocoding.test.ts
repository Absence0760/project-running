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
			assert.ok(
				capturedUrl.includes(encodeURIComponent('Richmond, VA & nearby')),
				`expected URL-encoded query in URL, got: ${capturedUrl}`,
			);
		} finally {
			globalThis.fetch = originalFetch;
		}
	});
