import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateElevationGain, fetchElevations, sampleCoordinates } from './elevation';

// Consent gate (audit/third-party-data-flows). In the tsx runner there is
// no `localStorage`, so `elevationConsentGiven()` is fail-closed — Open-Meteo
// must never be reached. We stub `fetch` to detonate if it fires.
test('fetchElevations — without consent, never touches the network', async () => {
	const original = globalThis.fetch;
	let called = false;
	globalThis.fetch = (async () => {
		called = true;
		throw new Error('fetch must not be called without consent');
	}) as typeof fetch;
	try {
		const out = await fetchElevations([
			[8.54, 47.37],
			[8.55, 47.38],
		]);
		assert.deepEqual(out, [0, 0]);
		assert.equal(called, false);
	} finally {
		globalThis.fetch = original;
	}
});

test('fetchElevations — empty input returns [] without a network call', async () => {
	const original = globalThis.fetch;
	globalThis.fetch = (async () => {
		throw new Error('fetch must not be called for empty input');
	}) as typeof fetch;
	try {
		assert.deepEqual(await fetchElevations([]), []);
	} finally {
		globalThis.fetch = original;
	}
});

test('fetchElevations — with recorded consent, calls Open-Meteo', async () => {
	const originalFetch = globalThis.fetch;
	const originalLs = (globalThis as { localStorage?: unknown }).localStorage;
	let requestedUrl = '';
	(globalThis as { localStorage?: unknown }).localStorage = {
		getItem: (k: string) =>
			k === 'cookie_consent' ? JSON.stringify({ choice: 'accepted' }) : null,
	};
	globalThis.fetch = (async (url: string) => {
		requestedUrl = String(url);
		return {
			ok: true,
			json: async () => ({ elevation: [410, 412] }),
		} as unknown as Response;
	}) as typeof fetch;
	try {
		const out = await fetchElevations([
			[8.54, 47.37],
			[8.55, 47.38],
		]);
		assert.deepEqual(out, [410, 412]);
		// Exact-hostname compare, not a substring check — CodeQL
		// js/incomplete-url-substring-sanitization (alert 151), and stricter
		// anyway: a proxy-shaped URL like evil.test/?api.open-meteo.com
		// would have passed includes().
		assert.equal(new URL(requestedUrl).hostname, 'api.open-meteo.com');
	} finally {
		globalThis.fetch = originalFetch;
		if (originalLs === undefined) delete (globalThis as { localStorage?: unknown }).localStorage;
		else (globalThis as { localStorage?: unknown }).localStorage = originalLs;
	}
});

test('calculateElevationGain — accumulates only positive deltas', () => {
	assert.equal(calculateElevationGain([100, 110, 105, 120]), 25);
});

test('calculateElevationGain — flat profile returns 0', () => {
	assert.equal(calculateElevationGain([100, 100, 100, 100]), 0);
});

test('calculateElevationGain — descending profile returns 0', () => {
	assert.equal(calculateElevationGain([200, 150, 100, 50]), 0);
});

test('calculateElevationGain — empty / single-point input returns 0', () => {
	assert.equal(calculateElevationGain([]), 0);
	assert.equal(calculateElevationGain([100]), 0);
});

test('calculateElevationGain — rounds the result', () => {
	// Three +0.4 deltas sum to 1.2 → rounds to 1.
	assert.equal(calculateElevationGain([0, 0.4, 0.8, 1.2]), 1);
});

test('sampleCoordinates — passes through when fewer than maxPoints', () => {
	const coords: [number, number][] = [
		[0, 0],
		[1, 1],
		[2, 2],
	];
	const { sampled, indices } = sampleCoordinates(coords, 100);
	assert.deepEqual(sampled, coords);
	assert.deepEqual(indices, [0, 1, 2]);
});

test('sampleCoordinates — equal-count input passes through', () => {
	const coords: [number, number][] = Array.from({ length: 10 }, (_, i) => [i, i]);
	const { sampled, indices } = sampleCoordinates(coords, 10);
	assert.deepEqual(sampled, coords);
	assert.equal(indices.length, 10);
});

test('sampleCoordinates — produces exactly maxPoints when input is larger', () => {
	const coords: [number, number][] = Array.from({ length: 1000 }, (_, i) => [i, i]);
	const { sampled, indices } = sampleCoordinates(coords, 50);
	assert.equal(sampled.length, 50);
	assert.equal(indices.length, 50);
	// First and last must be the boundaries — the elevation lookup needs
	// them to bracket the whole track.
	assert.deepEqual(sampled[0], coords[0]);
	assert.deepEqual(sampled[49], coords[999]);
	assert.equal(indices[0], 0);
	assert.equal(indices[49], 999);
});

test('sampleCoordinates — indices align with the sampled coordinates', () => {
	const coords: [number, number][] = Array.from({ length: 200 }, (_, i) => [i, i * 2]);
	const { sampled, indices } = sampleCoordinates(coords, 20);
	for (let k = 0; k < sampled.length; k++) {
		assert.deepEqual(sampled[k], coords[indices[k]]);
	}
});

/// Grants consent and stubs fetch for the duration of `body`, restoring both.
async function withConsentAndFetch(
	handler: (url: string) => Promise<Response>,
	body: () => Promise<void>,
): Promise<void> {
	const originalFetch = globalThis.fetch;
	const originalLs = (globalThis as { localStorage?: unknown }).localStorage;
	(globalThis as { localStorage?: unknown }).localStorage = {
		getItem: (k: string) =>
			k === 'cookie_consent' ? JSON.stringify({ choice: 'accepted' }) : null,
	};
	globalThis.fetch = ((url: string) => handler(String(url))) as typeof fetch;
	try {
		await body();
	} finally {
		globalThis.fetch = originalFetch;
		if (originalLs === undefined) delete (globalThis as { localStorage?: unknown }).localStorage;
		else (globalThis as { localStorage?: unknown }).localStorage = originalLs;
	}
}

test('a failed batch zeroes the whole lookup, never splices zeros into real data', async () => {
	// 250 alpine waypoints = 3 batches. The middle one is rate-limited. The old
	// per-batch fallback returned [2000..2099] ++ [0 x 100] ++ [2200..2249]:
	// calculateElevationGain read 2348 m of gain against a true 249 m, the
	// roadbook's `some(e => e !== 0)` all-zeros guard passed, and GPX export
	// wrote <ele>0</ele> for 100 mid-mountain trackpoints.
	const coords: [number, number][] = Array.from(
		{ length: 250 },
		(_, i) => [6.87 + i * 0.0001, 45.9] as [number, number],
	);
	let batch = 0;
	await withConsentAndFetch(
		async () => {
			const n = batch++;
			if (n === 1) return { ok: false, status: 429, json: async () => ({}) } as unknown as Response;
			const start = n === 0 ? 2000 : 2200;
			const len = n === 0 ? 100 : 50;
			return {
				ok: true,
				json: async () => ({ elevation: Array.from({ length: len }, (_, i) => start + i) }),
			} as unknown as Response;
		},
		async () => {
			const out = await fetchElevations(coords);
			assert.equal(out.length, 250);
			assert.ok(
				out.every((e) => e === 0),
				'a partial failure must degrade to all-zeros, not interleave',
			);
			assert.equal(calculateElevationGain(out), 0, 'no phantom climb');
		},
	);
});

test('a thrown fetch on a later batch also zeroes the whole lookup', async () => {
	const coords: [number, number][] = Array.from(
		{ length: 150 },
		(_, i) => [6.87 + i * 0.0001, 45.9] as [number, number],
	);
	let batch = 0;
	await withConsentAndFetch(
		async () => {
			if (batch++ === 0) {
				return {
					ok: true,
					json: async () => ({ elevation: Array.from({ length: 100 }, () => 1500) }),
				} as unknown as Response;
			}
			throw new Error('network down');
		},
		async () => {
			const out = await fetchElevations(coords);
			assert.equal(out.length, 150);
			assert.ok(out.every((e) => e === 0));
		},
	);
});

test('a short elevation array is a failure, not a silent shift', async () => {
	// Accepting a short array would push fewer readings than the batch had, so
	// every later batch's altitudes would land on the wrong coordinates.
	const coords: [number, number][] = Array.from(
		{ length: 150 },
		(_, i) => [6.87 + i * 0.0001, 45.9] as [number, number],
	);
	await withConsentAndFetch(
		async () =>
			({ ok: true, json: async () => ({ elevation: [1, 2, 3] }) }) as unknown as Response,
		async () => {
			const out = await fetchElevations(coords);
			assert.equal(out.length, 150);
			assert.ok(out.every((e) => e === 0));
		},
	);
});

test('every batch succeeding still returns the real profile', async () => {
	// The guard must not turn a healthy multi-batch lookup into zeros.
	const coords: [number, number][] = Array.from(
		{ length: 150 },
		(_, i) => [6.87 + i * 0.0001, 45.9] as [number, number],
	);
	let batch = 0;
	await withConsentAndFetch(
		async () => {
			const len = batch++ === 0 ? 100 : 50;
			return {
				ok: true,
				json: async () => ({ elevation: Array.from({ length: len }, () => 1500) }),
			} as unknown as Response;
		},
		async () => {
			const out = await fetchElevations(coords);
			assert.equal(out.length, 150);
			assert.ok(out.every((e) => e === 1500));
		},
	);
});
