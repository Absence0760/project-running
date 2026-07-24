import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

/**
 * A measured axis must seed empty.
 *
 * `GymExecutionBand` prefills reps / load / RPE from the prescription — those
 * are targets the athlete confirms by completing the set. Distance and
 * duration are different: they are measurements, and prefilling them means an
 * athlete who taps Complete without touching the field logs the plan as the
 * fact. `gym_programming.md` states the rule ("an unmeasured axis logs null,
 * never the target"); duration always honoured it, distance did not.
 *
 * Source-level because the seeding lives in a `$effect` that a DOM-free unit
 * test cannot drive.
 */
const src = readFileSync(
	new URL('./GymExecutionBand.svelte', import.meta.url),
	'utf8'
);

function seedExpression(name: string): string {
	const start = src.indexOf(`\t\t${name}Str =`);
	assert.ok(start >= 0, `${name}Str seeding not found — rename?`);
	return src.slice(start, src.indexOf(';', start));
}

test('distance seeds only from what was entered, never from the target', () => {
	const expr = seedExpression('distance');
	assert.ok(
		expr.includes('entered.distanceM'),
		'distance must seed from the entered value'
	);
	assert.ok(
		!expr.includes('targetDistanceM'),
		'distance must NOT fall back to the prescription — that logs the plan as the measurement'
	);
});

test('duration still seeds only from what was entered', () => {
	const expr = seedExpression('duration');
	assert.ok(expr.includes('entered.durationS'));
	assert.ok(!expr.includes('targetDurationS'));
});

test('reps and load DO seed from the target — they are confirmed, not measured', () => {
	assert.ok(seedExpression('weight').includes('targetWeightKg'));
	assert.ok(seedExpression('rpe').includes('targetRpe'));
});
