import assert from 'node:assert/strict';
import { test } from 'node:test';

import { generateTurnCues, type TurnCueWaypoint } from './turn_cues';

/**
 * Twin of `apps/mobile_android/test/turn_cues_test.dart` — keep these 14
 * cases in lockstep (same inputs, same expected directions). The math is
 * pure geometry over the polyline (bearing deltas at each interior vertex),
 * so the two platforms must produce identical cue lists.
 *
 * Coordinates are built at a low latitude (~0) where 0.01° lng ≈ 0.01° lat
 * in metres, so an axis-aligned right-angle reads as a clean 90° turn.
 */

const M_PER_DEG = 111_320;

/**
 * A course that runs `cornerAtM` metres due north, turns `turnDeg` to the
 * left over `cornerLengthM` metres, then runs `tailM` metres on the new
 * heading — every leg sampled at `spacingM`. The densely-sampled corner is
 * what a saved route or an imported GPX actually looks like.
 */
function corneringCourse(opts: {
	spacingM: number;
	cornerAtM: number;
	tailM: number;
	turnDeg: number;
	cornerLengthM?: number;
}): TurnCueWaypoint[] {
	const { spacingM, cornerAtM, tailM, turnDeg } = opts;
	const cornerLengthM = opts.cornerLengthM ?? 0;
	const pts: TurnCueWaypoint[] = [];
	let north = -cornerAtM;
	let east = 0;
	let headingDeg = 0;
	pts.push({ lat: north / M_PER_DEG, lng: east / M_PER_DEG });
	const steps = Math.round(cornerLengthM / spacingM);
	const legs: number[] = [];
	for (let d = spacingM; d <= cornerAtM; d += spacingM) legs.push(0);
	for (let s = 0; s < steps; s++) legs.push(turnDeg / steps);
	if (steps === 0) legs.push(turnDeg);
	for (let d = spacingM; d <= tailM; d += spacingM) legs.push(0);
	for (const bend of legs) {
		headingDeg -= bend;
		const rad = (headingDeg * Math.PI) / 180;
		north += spacingM * Math.cos(rad);
		east += spacingM * Math.sin(rad);
		pts.push({ lat: north / M_PER_DEG, lng: east / M_PER_DEG });
	}
	return pts;
}

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

/**
 * The round-1/round-2 bug: a single 90° corner at 100 m sampled every 10 m
 * used to collapse onto a segment drawn ACROSS the corner, so the one turn
 * was announced twice (slight_left at 80 m AND slight_left at 100 m) — both
 * under-classified, the first 20 m early, and "turns remaining" reading 2.
 */
test('a densely sampled 90 degree corner fires exactly one left cue at the corner', () => {
	const cues = generateTurnCues(
		corneringCourse({ spacingM: 10, cornerAtM: 100, tailM: 100, turnDeg: 90 }),
	);
	// "Turns remaining" on a one-corner course is 1, not 2.
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'left');
	assert.ok(Math.abs(cues[0].positionM - 100) < 1);
	assert.equal(cues[0].positionM, cues[0].distanceFromStartM);
});

test('a densely sampled 40 degree bend still fires its slight cue', () => {
	// Split across the collapsed segment this was two sub-threshold 20° halves
	// and vanished entirely.
	const cues = generateTurnCues(
		corneringCourse({ spacingM: 10, cornerAtM: 100, tailM: 100, turnDeg: 40 }),
	);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'slight_left');
	assert.ok(Math.abs(cues[0].positionM - 100) < 1);
});

test('a corner rounded over several vertices fires one cue at its full angle', () => {
	// 90° spread over three 30° vertices 5 m apart: one corner, not three
	// sub-threshold fragments and not a 30° slight.
	const cues = generateTurnCues(
		corneringCourse({
			spacingM: 5,
			cornerAtM: 100,
			tailM: 100,
			turnDeg: 90,
			cornerLengthM: 15,
		}),
	);
	assert.equal(cues.length, 1);
	assert.equal(cues[0].direction, 'left');
	assert.ok(cues[0].positionM > 100 && cues[0].positionM < 115);
});

test('a densely sampled straight line with a 90 degree corner reports the corner once at any sampling', () => {
	// The old collapse's answer depended on where the corner fell relative to
	// the 15 m merge window, so a different spacing produced a different (and
	// differently wrong) cue list for the same course.
	// 120 m is a whole number of every spacing, so the corner sits at the same
	// distance in all five courses.
	for (const spacingM of [4, 6, 8, 10, 12]) {
		const cues = generateTurnCues(
			corneringCourse({ spacingM, cornerAtM: 120, tailM: 120, turnDeg: 90 }),
		);
		assert.equal(cues.length, 1, `spacing ${spacingM}`);
		assert.equal(cues[0].direction, 'left', `spacing ${spacingM}`);
		assert.ok(
			Math.abs(cues[0].positionM - 120) < 1,
			`spacing ${spacingM}: ${cues[0].positionM}`,
		);
	}
});
