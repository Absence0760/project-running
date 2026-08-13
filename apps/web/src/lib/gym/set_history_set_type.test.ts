// The gym set-history reads must carry `gym_sets.set_type` all the way to the
// prescriber, and this file pins both halves of that.
//
// `gym_progression` drops a warmup by reading exactly that column. Until
// migration 20270525_001 neither history RPC returned it and none of the three
// `GymSetWithDate` producers mapped it, so every ramp-up reached the web
// prescriber looking like a working set. `workingSets` (decisions § 602)
// narrows the judgement to the session's top completed weight, which catches a
// LIGHTER ramp-up with or without a label — but an explicitly-typed warmup
// logged AT the working weight survived that narrowing and was judged. Mobile
// reads its local store, which carries the column, so it excluded that set and
// web did not.
//
// Two tests, because the defect had two halves:
//   - the behavioural half — the label is what separates a warmup from a
//     working set once both are at the same load;
//   - the plumbing half — a source guard over the three producers in
//     core/data.ts, which is where the column was actually being dropped. A
//     behavioural test alone cannot see that: the prescriber and
//     `lastSessionSets` always honoured `set_type`; they were simply never
//     handed it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { lastSessionSets } from './progression_prefill';
import { nextPrescription } from './gym_progression';
import type { GymSetWithDate } from '../core/data';

function histRow(
	exercise_name: string,
	reps: number | null,
	weight_kg: number | null,
	set_type: string | null,
): GymSetWithDate {
	return {
		workout_id: 'w1',
		started_at: '2026-08-10T09:00:00.000Z',
		exercise_name,
		reps,
		weight_kg,
		rpe: null,
		duration_s: null,
		set_type,
	};
}

// A 5×5 session at 100 kg preceded by a heavy single at the SAME 100 kg,
// logged as a warmup. Every set is at the session's top completed weight, so
// the working-weight narrowing keeps all six; only the label separates them.
function sessionWithWarmupAtWorkingWeight(warmupType: string | null): GymSetWithDate[] {
	return [
		histRow('Back Squat', 2, 100, warmupType),
		...Array.from({ length: 5 }, () => histRow('Back Squat', 5, 100, 'working')),
	];
}

test('an explicitly-typed warmup at the working weight is not judged', () => {
	const last = lastSessionSets(sessionWithWarmupAtWorkingWeight('warmup'), 'Back Squat');
	assert.ok(last);
	const sug = nextPrescription({
		scheme: 'five_by_five',
		lastSets: last,
		targetRepsMin: 5,
		targetRepsMax: 5,
		params: null,
	});
	assert.equal(sug.reason, 'increase_weight');
	assert.equal(sug.suggestedWeightKg, 102.5);
});

test('the same session without the label holds the load — the label is what decides', () => {
	const last = lastSessionSets(sessionWithWarmupAtWorkingWeight(null), 'Back Squat');
	assert.ok(last);
	const sug = nextPrescription({
		scheme: 'five_by_five',
		lastSets: last,
		targetRepsMin: 5,
		targetRepsMax: 5,
		params: null,
	});
	assert.equal(sug.reason, 'hold');
	assert.equal(sug.suggestedWeightKg, 100);
});

const DATA_SOURCE = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');

/// The body of one exported function, from its declaration to the next
/// top-level `export` — enough to see what its row mapping emits.
function functionBody(name: string): string {
	const start = DATA_SOURCE.indexOf(`export async function ${name}`);
	assert.notEqual(start, -1, `${name} must exist in core/data.ts`);
	const end = DATA_SOURCE.indexOf('\nexport ', start + 1);
	return DATA_SOURCE.slice(start, end === -1 ? undefined : end);
}

test('GymSetWithDate declares set_type', () => {
	assert.match(
		DATA_SOURCE,
		/export interface GymSetWithDate \{[\s\S]*?\bset_type: string \| null;[\s\S]*?\n\}/,
		'GymSetWithDate must carry set_type so no producer can silently drop it',
	);
});

for (const producer of [
	'fetchGymSetHistoryWithError',
	'fetchExerciseSetHistoryWithError',
	'fetchExerciseSetHistoryBatch',
]) {
	test(`${producer} maps set_type onto the row it returns`, () => {
		assert.match(
			functionBody(producer),
			/\n\t+set_type: r\.set_type,?\n/,
			`${producer} must carry set_type through — the prescriber's warmup ` +
				'exclusion reads exactly that column',
		);
	});
}
