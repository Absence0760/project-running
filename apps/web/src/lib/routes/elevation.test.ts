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
		assert.ok(requestedUrl.includes('api.open-meteo.com'));
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
