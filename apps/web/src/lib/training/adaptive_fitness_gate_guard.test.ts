// Source-level guards on the plan-generator-v2 P2 fitness direction gate
// (decisions §144, §150). P2 reads health-derived load (CTL/ATL/TSB) into a
// training prescription, and its sign-off rests on two properties that a
// future edit could quietly break:
//
//   1. the gate is FAIL-CLOSED — unset / empty / "false" reads as off, and with
//      it off the engine is passed no fitness at all (exactly shipped P1); and
//   2. the snapshot is NEVER logged or persisted — it flows into one in-memory
//      decision as a call argument and dies there.
//
// The engine half is pinned in plan_adaptive_replan.test.ts; this pins the web
// call site. Its Dart mirror is adaptive_fitness_gate_guard_test.dart.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

/// The body of `adaptiveFitnessInput()` on the plan-detail page.
function fitnessInputBody(page: string): string {
	const start = page.indexOf('function adaptiveFitnessInput(');
	assert.ok(start >= 0, 'could not locate adaptiveFitnessInput — rename?');
	const end = page.indexOf('function proposeAdaptiveReplan(', start);
	assert.ok(end > start, 'could not locate proposeAdaptiveReplan after it');
	return page.slice(start, end);
}

test('the P2 fitness gate is fail-closed and reads PUBLIC_ADAPTIVE_FITNESS_GATE', () => {
	const flag = read('src/lib/training/adaptive_fitness_flag.ts');
	assert.match(flag, /PUBLIC_ADAPTIVE_FITNESS_GATE/,
		'the flag must read PUBLIC_ADAPTIVE_FITNESS_GATE');
	assert.match(flag, /from\s+'\$env\/dynamic\/public'/,
		'the flag must read the deploy-time public env, not a build-time constant');
	// Delegating to the parity-pair parser is what keeps web and mobile from
	// accepting different values for the same documented flag.
	assert.match(flag, /adaptiveFitnessGateEnabled\(/,
		'the flag must delegate to the shared adaptiveFitnessGateEnabled parser');
});

test('the plan page passes no fitness at all while the gate is off', () => {
	const body = fitnessInputBody(read('src/routes/plans/[id]/+page.svelte'));
	assert.match(body, /if\s*\(!isAdaptiveFitnessGateEnabled\(\)\)\s*return null;/,
		'adaptiveFitnessInput must return null before touching the load series when the gate is off');
	// The early return must be the FIRST statement, so a gated-off build never
	// even computes the series.
	const guardIdx = body.indexOf('isAdaptiveFitnessGateEnabled()');
	const seriesIdx = body.indexOf('computeTrainingLoadSeries');
	assert.ok(seriesIdx > guardIdx,
		'the load series must only be computed after the gate check');
});

test('the fitness snapshot is never stored, logged, or persisted by the plan page', () => {
	const page = read('src/routes/plans/[id]/+page.svelte');

	// It exists only as a call argument — never bound to a variable or to
	// component state, so there is nothing for a later write to pick up.
	const calls = (page.match(/(?<!function\s)adaptiveFitnessInput\(\)/g) ?? []).length;
	assert.equal(calls, 1, 'adaptiveFitnessInput() must be called exactly once');
	assert.match(page, /fitness:\s*adaptiveFitnessInput\(\)/,
		'the snapshot must be passed straight into adaptiveReplanRemaining');
	assert.equal(/(?:let|const|var)\s+\w+\s*=\s*adaptiveFitnessInput\(\)/.test(page), false,
		'the snapshot must not be bound to a variable');
	assert.equal(/=\s*adaptiveFitnessInput\(\)/.test(page), false,
		'the snapshot must not be assigned to state');

	assert.equal(/console\s*\./.test(fitnessInputBody(page)), false,
		'the snapshot must never be logged');

	// The only thing an applied re-plan writes is the workout distance the
	// shipped engine proposed — no load column, no new field.
	const applyStart = page.indexOf('async function applyReplan(');
	assert.ok(applyStart >= 0, 'could not locate applyReplan — rename?');
	const applyBody = page.slice(applyStart, page.indexOf('/// Human label for a proposed change row', applyStart));
	assert.ok(applyBody.length > 0, 'could not slice applyReplan');
	assert.match(applyBody, /updatePlanWorkout\(c\.workoutId,\s*\{\s*target_distance_m:\s*c\.toMetres\s*\}\)/,
		'applying a re-plan must write only target_distance_m');
	assert.equal(/tsb|atl|ctl/.test(applyBody), false,
		'the apply path must not carry a load value');
});
