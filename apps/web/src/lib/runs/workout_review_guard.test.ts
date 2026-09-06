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

test('every step kind the recorder can emit has a label on this page', () => {
	// `WorkoutStepKind.walk` is what the recorder stamps for the rest step of a
	// walk-run -- the preset the onboarding wizard seeds for a beginner goal --
	// and `stepLabel` had no case for it, so a couch-to-5k runner whose phone
	// showed "Walk 1/7" opened the same run on the web and saw a bare lowercase
	// `walk`, untranslated, in every locale.
	//
	// Anchored to the recorder's own enum rather than to a list kept here: the
	// day a seventh kind is added to `WorkoutStepKind`, this fails.
	const decl = recorder.match(/enum WorkoutStepKind \{([^}]*)\}/);
	assert.ok(decl, 'WorkoutStepKind moved or was renamed');
	const kinds = decl[1]
		.split(',')
		.map((k) => k.trim())
		.filter(Boolean);
	assert.ok(kinds.length >= 6, `expected the full kind vocabulary, got ${kinds.join(',')}`);

	const start = page.indexOf('function stepLabel(');
	assert.ok(start >= 0, 'stepLabel moved');
	const body = page.slice(start, page.indexOf('\n\t}', start));
	for (const kind of kinds) {
		assert.match(
			body,
			new RegExp(`case '${kind}':`),
			`stepLabel has no case for the '${kind}' step the recorder emits`,
		);
	}
});

test('an unrecognised step kind renders a translated word, not its slug', () => {
	// The bag is schemaless and the phone ships independently of this build, so
	// a kind from a newer recorder reaches the default branch. Returning
	// `s.kind` there prints an English identifier into a Japanese UI.
	const start = page.indexOf('function stepLabel(');
	const body = page.slice(start, page.indexOf('\n\t}', start));
	const fallback = body.match(/default:\s*return ([^;]+);/);
	assert.ok(fallback, 'stepLabel must keep a default branch -- `kind` is a string off a jsonb bag');
	assert.doesNotMatch(
		fallback[1],
		/\bs\.kind\b/,
		'the default branch must not render the raw slug',
	);
	assert.match(fallback[1], /^m\('/, 'the default branch must resolve a message key');
});
