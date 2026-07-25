import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	idleStopwatch,
	isRunning,
	elapsedMs,
	elapsedSeconds,
	startStopwatch,
	stopStopwatch,
	parseDurationInput,
	type StopwatchState,
} from './gym_stopwatch';
import {
	computeRoutineAdherence,
	type PlannedSetRef,
	type ActualSetRef,
} from './gym_adherence';

test('idle stopwatch is not running and has zero elapsed', () => {
	const s = idleStopwatch();
	assert.equal(isRunning(s), false);
	assert.equal(elapsedMs(s, 1000), 0);
	assert.equal(elapsedSeconds(s, 1000), 0);
});

test('elapsed derives from the wall-clock anchor, not from tick counting', () => {
	const started = startStopwatch(idleStopwatch(), 10_000);
	assert.equal(isRunning(started), true);
	// A backgrounded tab loses ticks; recomputing from now - anchor stays correct.
	assert.equal(elapsedMs(started, 30_000), 20_000);
	assert.equal(elapsedSeconds(started, 30_000), 20);
});

test('a clock that goes backwards never yields negative elapsed', () => {
	const started = startStopwatch(idleStopwatch(), 10_000);
	assert.equal(elapsedMs(started, 9_000), 0);
});

test('stop banks the running span; resume adds to it', () => {
	let s: StopwatchState = startStopwatch(idleStopwatch(), 0);
	s = stopStopwatch(s, 20_000);
	assert.equal(isRunning(s), false);
	assert.equal(elapsedSeconds(s, 999_999), 20);
	s = startStopwatch(s, 100_000);
	assert.equal(elapsedSeconds(s, 105_000), 25);
});

test('start is idempotent while running; stop is a no-op while paused', () => {
	const running = startStopwatch(idleStopwatch(), 1_000);
	assert.deepEqual(startStopwatch(running, 5_000), running);
	const paused = stopStopwatch(running, 4_000);
	assert.deepEqual(stopStopwatch(paused, 9_000), paused);
});

test('elapsedSeconds rounds to the nearest second', () => {
	const s = startStopwatch(idleStopwatch(), 0);
	assert.equal(elapsedSeconds(s, 1_400), 1);
	assert.equal(elapsedSeconds(s, 1_600), 2);
});

test('parseDurationInput returns null for untracked input, never a fake target', () => {
	assert.equal(parseDurationInput(''), null);
	assert.equal(parseDurationInput('   '), null);
	assert.equal(parseDurationInput(null), null);
	assert.equal(parseDurationInput(undefined), null);
	assert.equal(parseDurationInput('abc'), null);
	assert.equal(parseDurationInput('-5'), null);
	assert.equal(parseDurationInput('20'), 20);
	assert.equal(parseDurationInput(20), 20);
	assert.equal(parseDurationInput('19.6'), 20);
});

// The bug this fixes: a 60s plank cut short at 20s, tapped Complete, must log the
// real elapsed (20s) as the actual duration and grade as 'partial' — NOT the
// prescribed 60s target that adherence would score as a full 'hit'.
test('cut-short timed hold captured via the stopwatch grades partial, not hit', () => {
	const planned: PlannedSetRef[] = [
		{
			exerciseKey: 'plank',
			stepIndex: 0,
			setIndex: 0,
			setType: 'working',
			targetRepsMin: null,
			targetRepsMax: null,
			targetWeightKg: null,
			targetDurationS: 60,
			targetDistanceM: null,
		},
	];

	// Real capture path: start the hold, cut it short at 20s of wall-clock time.
	let sw = startStopwatch(idleStopwatch(), 0);
	sw = stopStopwatch(sw, 20_000);
	const capturedS = parseDurationInput(String(elapsedSeconds(sw, 20_000)));
	assert.equal(capturedS, 20);

	const actual: ActualSetRef[] = [
		{ exerciseKey: 'plank', stepIndex: 0, setIndex: 0, reps: null, weightKg: null, durationS: capturedS, distanceM: null },
	];
	const adherence = computeRoutineAdherence(planned, actual);
	assert.equal(adherence.sets[0].status, 'partial');
	assert.equal(adherence.verdict, 'abandoned'); // 0 of 1 planned sets hit

	// Guard against regressing to the old bug (logging the target as the actual),
	// which adherence would score as a full hit.
	const buggy = computeRoutineAdherence(planned, [
		{ exerciseKey: 'plank', stepIndex: 0, setIndex: 0, reps: null, weightKg: null, durationS: 60, distanceM: null },
	]);
	assert.equal(buggy.sets[0].status, 'hit');
});

test('a fully-held timed set still grades hit', () => {
	const planned: PlannedSetRef[] = [
		{
			exerciseKey: 'plank',
			stepIndex: 0,
			setIndex: 0,
			setType: 'working',
			targetRepsMin: null,
			targetRepsMax: null,
			targetWeightKg: null,
			targetDurationS: 60,
			targetDistanceM: null,
		},
	];
	let sw = startStopwatch(idleStopwatch(), 0);
	sw = stopStopwatch(sw, 61_000);
	const capturedS = parseDurationInput(String(elapsedSeconds(sw, 61_000)));
	const actual: ActualSetRef[] = [
		{ exerciseKey: 'plank', stepIndex: 0, setIndex: 0, reps: null, weightKg: null, durationS: capturedS, distanceM: null },
	];
	assert.equal(computeRoutineAdherence(planned, actual).sets[0].status, 'hit');
});
