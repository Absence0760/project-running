// Source guards over the structured-workout review table on /runs/[id].
//
// The table reads `runs.metadata.workout_step_results`, which the phone
// recorder writes. Nothing typechecks across that seam — the bag is schemaless
// and the reader declares its own interface — so the two rails are pinned here
// by reading both sources. Both defects this closes were one arithmetic step
// each, and both made the web page contradict the phone about the same run.
//
// Runs with cwd = apps/web (the `test:unit` script), like data.test.ts.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';

const page = stripComments(
	readFileSync(resolve('src/routes/runs/[id]/+page.svelte'), 'utf-8'),
);
const recorder = readFileSync(
	resolve('../../packages/run_recorder/lib/src/workout_runner.dart'),
	'utf-8',
);

test('the recovery step number is read as written, not re-derived', () => {
	// The recorder emits one recovery BETWEEN consecutive reps and stamps the
	// REDUCED total on it (`repTotal: count - 1`). The page subtracted one
	// again, so a 6x400 rendered "Recovery 1/4" … "Recovery 5/4" — a fraction
	// that cannot exist — and a 2-rep workout rendered "Recovery 1/0". The
	// phone's own review shows "Recovery 1/5" off the same rows.
	assert.match(
		recorder,
		/kind: isWalkRun \? WorkoutStepKind\.walk : WorkoutStepKind\.recovery,[\s\S]{0,400}?repTotal: count - 1,/,
		'the recorder no longer stamps the reduced total on a recovery step — re-derive this guard',
	);
	const call = page
		.split('\n')
		.find((l) => l.includes("m('runDetail.stepRecoveryNumbered'"));
	assert.ok(call, 'the recovery label call moved');
	assert.match(
		call,
		/total: s\.rep_total\s*[,}]/,
		'the recovery total must be passed through — the value is already the recovery count',
	);
});

test('pace adherence is graded against the workout\'s own tolerance', () => {
	// `plan_workouts.target_pace_tolerance_sec` is a 0-60 s/km field in the web
	// Workout editor; the recorder resolves it and stamps `tolerance_sec_per_km`
	// on every step result, and the phone's review reads it. This page held a
	// literal 10, so a step a coach authored at 25 s/km graded green on the
	// phone and amber here — the same run, two verdicts, in the same product.
	assert.match(
		recorder,
		/'tolerance_sec_per_km': step\.toleranceSecPerKm,/,
		'the recorder no longer stamps the per-step tolerance — re-derive this guard',
	);
	const start = page.indexOf('function paceDeltaClass(');
	assert.ok(start >= 0, 'paceDeltaClass moved');
	const body = page.slice(start, page.indexOf('\n\t}', start));
	assert.match(
		body,
		/s\.tolerance_sec_per_km/,
		'the grading band must read the stamped tolerance, not a literal',
	);
	assert.doesNotMatch(
		body,
		/const tol = \d+;/,
		'a literal tolerance is the defect — the fallback belongs behind the stamped read',
	);
});
