import assert from 'node:assert/strict';
import { test } from 'node:test';

import { generateTurnCues, type TurnCueWaypoint } from './turn_cues';

/**
 * Twin of `apps/mobile_android/test/turn_cues_test.dart` — keep these 10
 * cases in lockstep (same inputs, same expected directions). The math is
 * pure geometry over the polyline (bearing deltas at each interior vertex),
 * so the two platforms must produce identical cue lists.
 *
 * Coordinates are built at a low latitude (~0) where 0.01° lng ≈ 0.01° lat
 * in metres, so an axis-aligned right-angle reads as a clean 90° turn.
 */

// A square corner: east then north → a 90° LEFT turn at the vertex.
const leftCorner: TurnCueWaypoint[] = [
	{ lat: 0, lng: 0 },
	{ lat: 0, lng: 0.02 },
	{ lat: 0.02, lng: 0.02 },
];

// East then south → a 90° RIGHT turn.
const rightCorner: TurnCueWaypoint[] = [
	{ lat: 0, lng: 0 },
	{ lat: 0, lng: 0.02 },
	{ lat: -0.02, lng: 0.02 },
];

test('a straight line produces no cues', () => {
	const wp: TurnCueWaypoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.01 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0, lng: 0.03 },
	];
	assert.deepEqual(generateTurnCues(wp), []);
});

test('empty input produces no cues', () => {
	assert.deepEqual(generateTurnCues([]), []);
});

test('a single-point input produces no cues', () => {
	assert.deepEqual(generateTurnCues([{ lat: 0, lng: 0 }]), []);
});

test('a two-point line has no interior vertex, so no cues', () => {
	assert.deepEqual(
		generateTurnCues([
			{ lat: 0, lng: 0 },
			{ lat: 0, lng: 0.02 },
		]),
		[],
	);
});

test('a 90 degree left turn yields one left cue at the vertex', () => {
	const cues = generateTurnCues(leftCorner);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'left');
	assert.ok(cues[0].positionM > 0);
	assert.equal(cues[0].positionM, cues[0].distanceFromStartM);
});

test('a 90 degree right turn yields one right cue', () => {
	const cues = generateTurnCues(rightCorner);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'right');
});

test('a sub-threshold wiggle is suppressed', () => {
	// ~10° kink, below the default 30° threshold.
	const wp: TurnCueWaypoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0.0035, lng: 0.04 },
	];
	assert.deepEqual(generateTurnCues(wp), []);
});

test('a slight bend just over threshold classifies as slight', () => {
	// ~40° left bend → slight_left (<= 45°).
	const wp: TurnCueWaypoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0.017, lng: 0.04 },
	];
	const cues = generateTurnCues(wp);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'slight_left');
});

test('a near-reversal is detected as a u-turn', () => {
	// Out east, back west → ~180° → uturn.
	const wp: TurnCueWaypoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0.0005, lng: 0 },
	];
	const cues = generateTurnCues(wp);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'uturn');
});

test('coincident vertices at one corner merge into a single cue', () => {
	// A duplicated vertex right at the corner must not double-fire.
	const wp: TurnCueWaypoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0, lng: 0.02 },
		{ lat: 0.02, lng: 0.02 },
	];
	const cues = generateTurnCues(wp);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'left');
});
