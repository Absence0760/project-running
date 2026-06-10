import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	buildRoundTripUrl,
	fetchRoundTrip,
	GraphHopperError,
	parseRoundTrip,
	type Fetcher,
} from './graphhopper';
import { areaEfficiency, enclosedAreaM2, pickBestLoop } from './select';
import { DEFAULT_SEEDS, handleGenerate, parseGenerateRequest, REQUEST_MULTIPLIERS } from './handler';

const BASE = 'http://gh.local';

function squareLoop(cx: number, cy: number, half: number): [number, number][] {
	return [
		[cx - half, cy - half],
		[cx + half, cy - half],
		[cx + half, cy + half],
		[cx - half, cy + half],
		[cx - half, cy - half],
	];
}

/// An out-and-back "loop" that encloses ~zero area — the failure mode the
/// shape-aware selector must reject.
function spurLoop(cx: number, cy: number, len: number): [number, number][] {
	return [
		[cx, cy],
		[cx + len, cy],
		[cx + 2 * len, cy],
		[cx + len, cy],
		[cx, cy],
	];
}

function ghResponse(coords: [number, number][], distanceM: number): Response {
	return new Response(
		JSON.stringify({ paths: [{ distance: distanceM, points: { type: 'LineString', coordinates: coords } }] }),
		{ status: 200, headers: { 'content-type': 'application/json' } },
	);
}

// --- graphhopper.ts ---

test('buildRoundTripUrl carries the round_trip params + foot profile', () => {
	const url = buildRoundTripUrl({ baseUrl: BASE, start: { lat: 40, lng: -74 }, requestDistanceM: 5000.6, seed: 3 });
	const u = new URL(url);
	assert.equal(u.pathname, '/route');
	assert.equal(u.searchParams.get('profile'), 'foot');
	assert.equal(u.searchParams.get('algorithm'), 'round_trip');
	// Requested distance is the RAW target (no inflation): round(5000.6) = 5001.
	assert.equal(u.searchParams.get('round_trip.distance'), '5001');
	assert.equal(u.searchParams.get('round_trip.seed'), '3');
	assert.equal(u.searchParams.get('point'), '40,-74');
	assert.equal(u.searchParams.get('points_encoded'), 'false');
});

test('buildRoundTripUrl asks for exactly requestDistanceM', () => {
	// The handler races a spread of request distances (REQUEST_MULTIPLIERS ×
	// target) and keeps the actual result closest to target; the URL builder just
	// forwards whatever distance it's handed.
	const url = buildRoundTripUrl({ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 10000, seed: 0 });
	const asked = Number(new URL(url).searchParams.get('round_trip.distance'));
	assert.equal(asked, 10000);
});

test('buildRoundTripUrl strips a trailing slash on the base', () => {
	const url = buildRoundTripUrl({ baseUrl: `${BASE}/`, start: { lat: 1, lng: 2 }, requestDistanceM: 1000, seed: 0 });
	assert.ok(url.startsWith(`${BASE}/route?`));
});

test('parseRoundTrip extracts coordinates + distance from the first path', () => {
	const got = parseRoundTrip({ paths: [{ distance: 4990, points: { coordinates: squareLoop(0, 0, 0.01) } }] });
	assert.ok(got);
	assert.equal(got.distanceM, 4990);
	assert.equal(got.coordinates.length, 5);
});

test('parseRoundTrip returns null on empty / missing paths', () => {
	assert.equal(parseRoundTrip({ paths: [] }), null);
	assert.equal(parseRoundTrip({}), null);
	assert.equal(parseRoundTrip(null), null);
	assert.equal(parseRoundTrip({ paths: [{ distance: 1 }] }), null); // no points
});

test('parseRoundTrip drops non-finite coordinate pairs', () => {
	const got = parseRoundTrip({
		paths: [{ distance: 100, points: { coordinates: [[0, 0], ['x', 1], [1, 1]] } }],
	});
	assert.ok(got);
	assert.equal(got.coordinates.length, 2);
});

test('parseRoundTrip defaults distance to 0 when absent', () => {
	const got = parseRoundTrip({ paths: [{ points: { coordinates: squareLoop(0, 0, 0.01) } }] });
	assert.ok(got);
	assert.equal(got.distanceM, 0);
});

test('fetchRoundTrip throws unconfigured when the base URL is empty', async () => {
	await assert.rejects(
		() => fetchRoundTrip({ baseUrl: undefined, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0 }),
		(e: unknown) => e instanceof GraphHopperError && e.kind === 'unconfigured',
	);
});

test('fetchRoundTrip throws upstream on a non-2xx response', async () => {
	const fetcher: Fetcher = async () => new Response('boom', { status: 500 });
	await assert.rejects(
		() => fetchRoundTrip({ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0 }, fetcher),
		(e: unknown) => e instanceof GraphHopperError && e.kind === 'upstream',
	);
});

test('fetchRoundTrip throws no_route on an empty path set', async () => {
	const fetcher: Fetcher = async () =>
		new Response(JSON.stringify({ paths: [] }), { status: 200 });
	await assert.rejects(
		() => fetchRoundTrip({ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0 }, fetcher),
		(e: unknown) => e instanceof GraphHopperError && e.kind === 'no_route',
	);
});

test('fetchRoundTrip returns the parsed candidate on success', async () => {
	const fetcher: Fetcher = async () => ghResponse(squareLoop(0, 0, 0.01), 5005);
	const got = await fetchRoundTrip({ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0 }, fetcher);
	assert.equal(got.distanceM, 5005);
	assert.equal(got.coordinates.length, 5);
});

test('fetchRoundTrip sends the X-Engine-Key header when an apiKey is set', async () => {
	let seen: Record<string, string> | undefined;
	const fetcher: Fetcher = async (_u, init) => {
		seen = init?.headers as Record<string, string> | undefined;
		return ghResponse(squareLoop(0, 0, 0.01), 5000);
	};
	await fetchRoundTrip(
		{ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0, apiKey: 'sekret' },
		fetcher,
	);
	assert.equal(seen?.['X-Engine-Key'], 'sekret');
});

test('fetchRoundTrip omits the X-Engine-Key header when no apiKey is set', async () => {
	let seen: HeadersInit | undefined = { sentinel: 'unset' } as Record<string, string>;
	const fetcher: Fetcher = async (_u, init) => {
		seen = init?.headers;
		return ghResponse(squareLoop(0, 0, 0.01), 5000);
	};
	await fetchRoundTrip({ baseUrl: BASE, start: { lat: 0, lng: 0 }, requestDistanceM: 5000, seed: 0 }, fetcher);
	assert.equal(seen, undefined);
});

// --- select.ts ---

test('enclosedAreaM2 of a square loop matches side² in metres', () => {
	// 0.01° at the equator ≈ 1113.2 m, so a 0.02° square ≈ 2226.4 m side.
	const area = enclosedAreaM2(squareLoop(0, 0, 0.01));
	const side = 0.02 * 111320;
	assert.ok(Math.abs(area - side * side) / (side * side) < 0.001);
});

test('enclosedAreaM2 of an out-and-back spur is ~zero', () => {
	assert.ok(enclosedAreaM2(spurLoop(0, 0, 0.01)) < 1);
});

test('areaEfficiency ranks a square loop well above a spur', () => {
	const sq = { coordinates: squareLoop(0, 0, 0.01), distanceM: 4 * 0.02 * 111320 };
	const sp = { coordinates: spurLoop(0, 0, 0.01), distanceM: 4 * 0.01 * 111320 };
	assert.ok(areaEfficiency(sq) > 0.5);
	assert.ok(areaEfficiency(sp) < 0.01);
});

test('pickBestLoop prefers the rounder loop when distances tie', () => {
	const spur = { coordinates: spurLoop(0, 0, 0.01), distanceM: 5000 };
	const square = { coordinates: squareLoop(0, 0, 0.0056), distanceM: 5000 };
	const best = pickBestLoop([spur, square], 5000);
	assert.equal(best, square);
});

test('pickBestLoop picks the closest-to-target when nothing is in-band', () => {
	// Sparse start: every seed over/undershoots. Closeness must beat shape —
	// a 6.9 km spur beats a perfectly round 9.2 km loop when 5 km was asked
	// (both are outside the ±25% band, so the old "roundest wins" surfaced 9.2).
	const farRound = { coordinates: squareLoop(0, 0, 0.0103), distanceM: 9200 };
	const nearSpur = { coordinates: spurLoop(0, 0, 0.031), distanceM: 6900 };
	const best = pickBestLoop([farRound, nearSpur], 5000);
	assert.equal(best, nearSpur);
});

test('pickBestLoop returns null when no candidate is usable', () => {
	assert.equal(pickBestLoop([], 5000), null);
	assert.equal(pickBestLoop([{ coordinates: [[0, 0]], distanceM: 5000 }], 5000), null);
	assert.equal(pickBestLoop([{ coordinates: squareLoop(0, 0, 0.01), distanceM: 0 }], 5000), null);
});

// --- handler.ts ---

test('parseGenerateRequest rejects malformed bodies', () => {
	assert.equal(parseGenerateRequest(null), null);
	assert.equal(parseGenerateRequest({}), null);
	assert.equal(parseGenerateRequest({ start: { lat: 1 } }), null); // no lng
	assert.equal(parseGenerateRequest({ start: { lat: 1, lng: 2 } }), null); // no target
	assert.equal(parseGenerateRequest({ start: { lat: '1', lng: 2 }, targetDistanceM: 5000 }), null);
	assert.equal(parseGenerateRequest({ start: { lat: 1, lng: 2 }, targetDistanceM: 5000, seeds: 'x' }), null);
});

test('parseGenerateRequest accepts a well-formed body', () => {
	const got = parseGenerateRequest({ start: { lat: 1, lng: 2 }, targetDistanceM: 5000, seeds: 3 });
	assert.deepEqual(got, { start: { lat: 1, lng: 2 }, targetDistanceM: 5000, seeds: 3 });
});

const OK_CFG = { graphhopperUrl: BASE };

test('handleGenerate → 400 on invalid input', async () => {
	assert.equal((await handleGenerate(null, OK_CFG)).status, 400);
	assert.equal((await handleGenerate({ start: { lat: 999, lng: 0 }, targetDistanceM: 5000 }, OK_CFG)).status, 400);
	assert.equal((await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: -5 }, OK_CFG)).status, 400);
	assert.equal((await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5_000_000 }, OK_CFG)).status, 400);
});

test('handleGenerate → 501 when the engine URL is unset', async () => {
	const res = await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, { graphhopperUrl: undefined });
	assert.equal(res.status, 501);
});

test('handleGenerate → 502 when every seed fails upstream', async () => {
	const fetcher: Fetcher = async () => new Response('down', { status: 503 });
	const res = await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, OK_CFG, { fetcher });
	assert.equal(res.status, 502);
});

test('handleGenerate races N seeds and returns the best-shaped loop', async () => {
	let calls = 0;
	const fetcher: Fetcher = async (url) => {
		calls++;
		const seed = new URL(url).searchParams.get('round_trip.seed');
		// Seed 0 returns a degenerate spur; the rest return clean square loops.
		// The selector must pick a square over the spur even though both report
		// the target distance.
		const coords = seed === '0' ? spurLoop(0, 0, 0.01) : squareLoop(0, 0, 0.0056);
		return ghResponse(coords, 5000);
	};
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000, seeds: 4 },
		OK_CFG,
		{ fetcher },
	);
	assert.equal(calls, 4 * REQUEST_MULTIPLIERS.length); // one request per seed per multiplier
	assert.equal(res.status, 200);
	if (res.status === 200) {
		// The spur's first point is [0,0]; a square's bounding box is non-degenerate.
		const xs = res.body.coordinates.map((c) => c[0]);
		assert.ok(Math.min(...xs) < 0); // square spans negative x; spur never does
	}
});

test('handleGenerate defaults to DEFAULT_SEEDS when none requested', async () => {
	let calls = 0;
	const fetcher: Fetcher = async () => {
		calls++;
		return ghResponse(squareLoop(0, 0, 0.0056), 5000);
	};
	const res = await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, OK_CFG, { fetcher });
	assert.equal(res.status, 200);
	assert.equal(DEFAULT_SEEDS, 5); // seeds raced per request multiplier
	assert.equal(calls, DEFAULT_SEEDS * REQUEST_MULTIPLIERS.length); // omitted `seeds` → DEFAULT_SEEDS × multipliers
});

test('handleGenerate tolerates partial seed failures', async () => {
	const fetcher: Fetcher = async (url) => {
		const seed = new URL(url).searchParams.get('round_trip.seed');
		if (seed === '0' || seed === '2') return new Response('x', { status: 500 });
		return ghResponse(squareLoop(0, 0, 0.0056), 5000);
	};
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000, seeds: 4 },
		OK_CFG,
		{ fetcher },
	);
	assert.equal(res.status, 200);
});

test('handleGenerate clamps the seed count to MAX_SEEDS', async () => {
	let calls = 0;
	const fetcher: Fetcher = async () => {
		calls++;
		return ghResponse(squareLoop(0, 0, 0.0056), 5000);
	};
	await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5000, seeds: 99 }, OK_CFG, { fetcher });
	assert.equal(calls, 8 * REQUEST_MULTIPLIERS.length); // clamped to MAX_SEEDS, raced at each multiplier
});

test('handleGenerate races request multipliers and keeps the result closest to target', async () => {
	// Simulate a network that overshoots EVERY round_trip request by 30%. Only the
	// 0.8× multiplier (req 4000 → 5200, +4%) lands in the ±15% band; the raw 1.0×
	// (req 5000 → 6500, +30%) does not. The multi-distance race must surface the
	// ~5200 result, not the raw-request overshoot — the exact failure the user hit.
	const fetcher: Fetcher = async (url) => {
		const reqDist = Number(new URL(url).searchParams.get('round_trip.distance'));
		return ghResponse(squareLoop(0, 0, 0.0056), reqDist * 1.3);
	};
	const res = await handleGenerate({ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, OK_CFG, { fetcher });
	assert.equal(res.status, 200);
	if (res.status === 200) {
		// 0.8 × 5000 × 1.3 = 5200, the sole in-band candidate across the spread.
		assert.ok(
			Math.abs(res.body.distanceM - 5200) < 1,
			`expected the 0.8x result ~5200, got ${res.body.distanceM}`,
		);
	}
});
