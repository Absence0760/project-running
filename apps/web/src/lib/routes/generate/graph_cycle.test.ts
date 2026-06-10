import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	buildGraphCycleUrl,
	fetchGraphCycle,
	GraphCycleError,
	parseGraphCycle,
} from './graph_cycle';
import { handleGenerate } from './handler';
import type { Fetcher } from './graphhopper';

const GC = 'http://gc.local';
const GH = 'http://gh.local';

function squareLoop(cx: number, cy: number, half: number): [number, number][] {
	return [
		[cx - half, cy - half],
		[cx + half, cy - half],
		[cx + half, cy + half],
		[cx - half, cy + half],
		[cx - half, cy - half],
	];
}

/// A sidecar /cycle response. found=true carries the loop; found=false is the
/// loop-poor signal.
function gcResponse(
	found: boolean,
	coords?: [number, number][],
	distanceM?: number,
	areaEfficiency = 0.6,
): Response {
	const body = found
		? { found: true, coordinates: coords, distanceM, areaEfficiency, largestClean: null }
		: { found: false, largestClean: null };
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { 'content-type': 'application/json' },
	});
}

function ghResponse(coords: [number, number][], distanceM: number): Response {
	return new Response(
		JSON.stringify({ paths: [{ distance: distanceM, points: { coordinates: coords } }] }),
		{ status: 200, headers: { 'content-type': 'application/json' } },
	);
}

/// Route a mocked fetcher by which engine the URL targets.
function byEngine(onCycle: Fetcher, onRoundTrip: Fetcher): Fetcher {
	return (url, init) => (url.includes('/cycle') ? onCycle(url, init) : onRoundTrip(url, init));
}

// --- graph_cycle.ts client ---

test('buildGraphCycleUrl appends /cycle and strips a trailing slash', () => {
	assert.equal(buildGraphCycleUrl(GC), `${GC}/cycle`);
	assert.equal(buildGraphCycleUrl(`${GC}/`), `${GC}/cycle`);
});

test('parseGraphCycle returns the loop when found', () => {
	const got = parseGraphCycle({ found: true, coordinates: squareLoop(0, 0, 0.01), distanceM: 5005 });
	assert.ok(got);
	assert.equal(got.distanceM, 5005);
	assert.equal(got.coordinates.length, 5);
});

test('parseGraphCycle returns null on loop-poor / malformed payloads', () => {
	assert.equal(parseGraphCycle({ found: false, largestClean: null }), null);
	assert.equal(parseGraphCycle({ found: true }), null); // no coordinates
	assert.equal(parseGraphCycle({}), null);
	assert.equal(parseGraphCycle(null), null);
	// found:true but distance ≤ 0 is not a usable loop.
	assert.equal(parseGraphCycle({ found: true, coordinates: squareLoop(0, 0, 0.01), distanceM: 0 }), null);
});

test('parseGraphCycle drops non-finite coordinate pairs', () => {
	const got = parseGraphCycle({
		found: true,
		coordinates: [[0, 0], ['x', 1], [1, 1]],
		distanceM: 100,
	});
	assert.ok(got);
	assert.equal(got.coordinates.length, 2);
});

test('fetchGraphCycle throws unconfigured when the base URL is empty', async () => {
	await assert.rejects(
		() => fetchGraphCycle({ baseUrl: undefined, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }),
		(e: unknown) => e instanceof GraphCycleError && e.kind === 'unconfigured',
	);
});

test('fetchGraphCycle throws upstream on a non-2xx response', async () => {
	const fetcher: Fetcher = async () => new Response('boom', { status: 500 });
	await assert.rejects(
		() => fetchGraphCycle({ baseUrl: GC, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, fetcher),
		(e: unknown) => e instanceof GraphCycleError && e.kind === 'upstream',
	);
});

test('fetchGraphCycle throws upstream when the fetch itself rejects', async () => {
	const fetcher: Fetcher = async () => {
		throw new Error('econnrefused');
	};
	await assert.rejects(
		() => fetchGraphCycle({ baseUrl: GC, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, fetcher),
		(e: unknown) => e instanceof GraphCycleError && e.kind === 'upstream',
	);
});

test('fetchGraphCycle returns null on a loop-poor result', async () => {
	const fetcher: Fetcher = async () => gcResponse(false);
	const got = await fetchGraphCycle({ baseUrl: GC, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, fetcher);
	assert.equal(got, null);
});

test('fetchGraphCycle returns the loop on success', async () => {
	const fetcher: Fetcher = async () => gcResponse(true, squareLoop(0, 0, 0.01), 4980);
	const got = await fetchGraphCycle({ baseUrl: GC, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, fetcher);
	assert.ok(got);
	assert.equal(got.distanceM, 4980);
});

test('fetchGraphCycle POSTs a JSON body with the start + target and the key header', async () => {
	let seenInit: RequestInit | undefined;
	const fetcher: Fetcher = async (_u, init) => {
		seenInit = init;
		return gcResponse(true, squareLoop(0, 0, 0.01), 5000);
	};
	await fetchGraphCycle(
		{ baseUrl: GC, start: { lat: 40, lng: -74 }, targetDistanceM: 5000, apiKey: 'sekret' },
		fetcher,
	);
	assert.equal(seenInit?.method, 'POST');
	const headers = seenInit?.headers as Record<string, string>;
	assert.equal(headers['X-Engine-Key'], 'sekret');
	assert.equal(headers['content-type'], 'application/json');
	const body = JSON.parse(seenInit?.body as string);
	assert.deepEqual(body.start, { lat: 40, lng: -74 });
	assert.equal(body.targetDistanceM, 5000);
});

test('fetchGraphCycle omits the key header when no apiKey is set', async () => {
	let seenInit: RequestInit | undefined;
	const fetcher: Fetcher = async (_u, init) => {
		seenInit = init;
		return gcResponse(true, squareLoop(0, 0, 0.01), 5000);
	};
	await fetchGraphCycle({ baseUrl: GC, start: { lat: 0, lng: 0 }, targetDistanceM: 5000 }, fetcher);
	const headers = seenInit?.headers as Record<string, string>;
	assert.equal(headers['X-Engine-Key'], undefined);
});

// --- handler integration: graph-cycle FIRST, round_trip fallback ---

test('handleGenerate uses graph-cycle first and skips round_trip on a clean loop', async () => {
	let rtCalled = false;
	const fetcher = byEngine(
		async () => gcResponse(true, squareLoop(0, 0, 0.0056), 5050),
		async () => {
			rtCalled = true;
			return ghResponse(squareLoop(0, 0, 0.0056), 5000);
		},
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: GH },
		{ fetcher },
	);
	assert.equal(res.status, 200);
	if (res.status === 200) assert.equal(res.body.distanceM, 5050);
	assert.equal(rtCalled, false, 'round_trip must not run when graph-cycle returns a loop');
});

test('handleGenerate falls back to round_trip when graph-cycle is loop-poor', async () => {
	let rtCalled = false;
	const fetcher = byEngine(
		async () => gcResponse(false),
		async () => {
			rtCalled = true;
			return ghResponse(squareLoop(0, 0, 0.0056), 5000);
		},
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: GH },
		{ fetcher },
	);
	assert.equal(res.status, 200);
	assert.equal(rtCalled, true, 'round_trip must run when graph-cycle is loop-poor');
});

test('handleGenerate falls back to round_trip when the sidecar errors', async () => {
	let rtCalled = false;
	const fetcher = byEngine(
		async () => new Response('down', { status: 503 }),
		async () => {
			rtCalled = true;
			return ghResponse(squareLoop(0, 0, 0.0056), 5000);
		},
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: GH },
		{ fetcher },
	);
	assert.equal(res.status, 200);
	assert.equal(rtCalled, true, 'an unreachable sidecar must fall back, not fail the request');
});

test('handleGenerate → 502 when graph-cycle is loop-poor and no fallback engine is configured', async () => {
	const fetcher: Fetcher = async () => gcResponse(false);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: undefined },
		{ fetcher },
	);
	assert.equal(res.status, 502);
});

test('handleGenerate → 502 when the sidecar THROWS and no fallback engine is configured', async () => {
	// Distinct path from the loop-poor (found:false → null) case above: here the
	// sidecar errors, fetchGraphCycle throws, the catch swallows it, and with no
	// GraphHopper to fall back to the handler must still 502 (not crash).
	const fetcher: Fetcher = async () => new Response('down', { status: 503 });
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: undefined },
		{ fetcher },
	);
	assert.equal(res.status, 502);
});

test('handleGenerate serves graph-cycle alone (no GraphHopper) on a clean loop', async () => {
	const fetcher: Fetcher = async () => gcResponse(true, squareLoop(0, 0, 0.0056), 4990);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphCycleUrl: GC, graphhopperUrl: undefined },
		{ fetcher },
	);
	assert.equal(res.status, 200);
	if (res.status === 200) assert.equal(res.body.distanceM, 4990);
});

test('handleGenerate → 501 when neither engine is configured', async () => {
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphhopperUrl: undefined },
	);
	assert.equal(res.status, 501);
});
