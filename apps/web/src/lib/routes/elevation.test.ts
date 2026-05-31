import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateElevationGain, sampleCoordinates } from './elevation';

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
