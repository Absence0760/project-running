import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	GUIDED_RUN_LIBRARY,
	cuesDue,
	findGuidedRun,
	isGuidedRunValid,
	type GuidedRun,
} from './guided_runs';

function mkRun(cues: number[]): GuidedRun {
	return {
		id: 'test',
		title: 't',
		subtitle: 's',
		duration_sec: Math.max(...cues, 0) + 10,
		description: 'd',
		cues: cues.map((at) => ({ at_sec: at, text: `cue at ${at}` })),
	};
}

// ─────────── cuesDue ───────────

test('cuesDue: no cues in range → empty', () => {
	const g = mkRun([10, 60, 120]);
	assert.deepEqual(cuesDue(g, 30, 50), []);
});

test('cuesDue: cue at boundary fires on the tick it crosses', () => {
	// Cue at 60 should fire on the (59, 60] tick, NOT the (60, 61] one.
	const g = mkRun([60]);
	assert.equal(cuesDue(g, 59, 60).length, 1);
	assert.equal(cuesDue(g, 60, 61).length, 0);
});

test('cuesDue: multiple cues in the same window all fire', () => {
	const g = mkRun([10, 11, 12]);
	const out = cuesDue(g, 9, 12);
	assert.equal(out.length, 3);
	assert.deepEqual(
		out.map((c) => c.at_sec),
		[10, 11, 12],
	);
});

test('cuesDue: prev === now → empty (idempotent on a repeated tick)', () => {
	const g = mkRun([60]);
	assert.deepEqual(cuesDue(g, 60, 60), []);
});

test('cuesDue: now < prev (clock went backwards somehow) → empty', () => {
	const g = mkRun([60]);
	assert.deepEqual(cuesDue(g, 120, 60), []);
});

test('cuesDue: cue at 0 fires when prev is -1 (first tick)', () => {
	// Mobile recorder seeds prev=-1 on the very first tick so cue at
	// at_sec=0 lands cleanly.
	const g = mkRun([0]);
	assert.equal(cuesDue(g, -1, 0).length, 1);
});

// ─────────── isGuidedRunValid ───────────

test('isGuidedRunValid: well-formed run passes', () => {
	const g = mkRun([0, 60, 300]);
	assert.equal(isGuidedRunValid(g), true);
});

test('isGuidedRunValid: out-of-order cues fail', () => {
	const g: GuidedRun = {
		id: 'x',
		title: 'x',
		subtitle: 'x',
		duration_sec: 600,
		description: 'x',
		cues: [
			{ at_sec: 60, text: 'a' },
			{ at_sec: 30, text: 'b' },
		],
	};
	assert.equal(isGuidedRunValid(g), false);
});

test('isGuidedRunValid: cue beyond duration fails', () => {
	const g: GuidedRun = {
		id: 'x',
		title: 'x',
		subtitle: 'x',
		duration_sec: 60,
		description: 'x',
		cues: [{ at_sec: 120, text: 'late' }],
	};
	assert.equal(isGuidedRunValid(g), false);
});

test('isGuidedRunValid: blank cue text fails', () => {
	const g: GuidedRun = {
		id: 'x',
		title: 'x',
		subtitle: 'x',
		duration_sec: 60,
		description: 'x',
		cues: [{ at_sec: 30, text: '   ' }],
	};
	assert.equal(isGuidedRunValid(g), false);
});

// ─────────── library ───────────

test('GUIDED_RUN_LIBRARY: every entry is valid', () => {
	assert.ok(GUIDED_RUN_LIBRARY.length >= 3);
	for (const g of GUIDED_RUN_LIBRARY) {
		assert.ok(isGuidedRunValid(g), `${g.id} is malformed`);
	}
});

test('GUIDED_RUN_LIBRARY: ids are unique', () => {
	const ids = GUIDED_RUN_LIBRARY.map((g) => g.id);
	const set = new Set(ids);
	assert.equal(set.size, ids.length);
});

test('findGuidedRun: returns null for unknown id', () => {
	assert.equal(findGuidedRun('nope'), null);
});

test('findGuidedRun: returns the run for a known id', () => {
	const id = GUIDED_RUN_LIBRARY[0].id;
	assert.notEqual(findGuidedRun(id), null);
	assert.equal(findGuidedRun(id)!.id, id);
});

test('GUIDED_RUN_LIBRARY: durations are sensible (5-90 min)', () => {
	for (const g of GUIDED_RUN_LIBRARY) {
		assert.ok(g.duration_sec >= 5 * 60, `${g.id} too short`);
		assert.ok(g.duration_sec <= 90 * 60, `${g.id} too long`);
	}
});

test('GUIDED_RUN_LIBRARY: every run has a kickoff cue at or near 0', () => {
	for (const g of GUIDED_RUN_LIBRARY) {
		assert.ok(
			g.cues.length > 0 && g.cues[0].at_sec <= 5,
			`${g.id} missing a kickoff cue in the first 5s`,
		);
	}
});

test('GUIDED_RUN_LIBRARY: every run has a finish cue at exactly duration', () => {
	for (const g of GUIDED_RUN_LIBRARY) {
		const last = g.cues[g.cues.length - 1];
		assert.equal(last.at_sec, g.duration_sec, `${g.id} missing a finish cue at duration`);
	}
});
