import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildPhasePlan,
	phaseAt,
	phaseTargetPaceSecPerKm,
	goalPaceSecPerKm,
	type RacePhase,
	type RacePhaseIntent,
	type RacePhasePreset
} from './race_phases';

const TEN_MILE_FRACTION = 16_093.44 / 42_195;

function weightedMeanFactor(phases: RacePhase[]): number {
	const total = phases[phases.length - 1].endM;
	return phases.reduce((sum, p) => sum + p.paceFactor * (p.endM - p.startM), 0) / total;
}

test('even preset is one full-distance phase at factor 1', () => {
	const plan = buildPhasePlan(10_000, 'even');
	assert.equal(plan.length, 1);
	assert.deepEqual(plan[0], { startM: 0, endM: 10_000, intent: 'even', paceFactor: 1 });
});

test('ten_ten_ten boundaries land on the generalised 10-mile fractions for a marathon', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(plan.length, 3);
	assert.equal(plan[0].startM, 0);
	assert.ok(Math.abs(plan[1].startM - 16_093.44) < 1e-9);
	assert.ok(Math.abs(plan[2].startM - 32_186.88) < 1e-9);
	assert.equal(plan[2].endM, 42_195);
	assert.equal(plan[0].endM, plan[1].startM);
	assert.equal(plan[1].endM, plan[2].startM);
});

test('ten_ten_ten intents and factors: hold back, settle, then a derived faster finish', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.deepEqual(
		plan.map((p) => p.intent),
		['hold_back', 'settle', 'race']
	);
	assert.equal(plan[0].paceFactor, 1.02);
	assert.equal(plan[1].paceFactor, 1);
	const f = TEN_MILE_FRACTION;
	const derived = (1 - f * 1.02 - f * 1) / (1 - f - f);
	assert.ok(Math.abs(plan[2].paceFactor - derived) < 1e-12);
	assert.ok(plan[2].paceFactor > 0.96 && plan[2].paceFactor < 0.97);
});

test('distance-weighted mean factor is 1 for ten_ten_ten at any distance', () => {
	for (const distanceM of [42_195, 10_000, 160_934]) {
		const plan = buildPhasePlan(distanceM, 'ten_ten_ten');
		assert.ok(Math.abs(weightedMeanFactor(plan) - 1) < 1e-9);
	}
});

test('negative_split is two halves: held back then a derived faster finish, mean 1', () => {
	const plan = buildPhasePlan(21_097.5, 'negative_split');
	assert.equal(plan.length, 2);
	assert.deepEqual(
		plan.map((p) => p.intent),
		['hold_back', 'race']
	);
	assert.equal(plan[0].endM, 21_097.5 / 2);
	assert.equal(plan[1].startM, 21_097.5 / 2);
	assert.equal(plan[0].paceFactor, 1.02);
	assert.ok(Math.abs(plan[1].paceFactor - (1 - 0.5 * 1.02) / 0.5) < 1e-12);
	assert.ok(Math.abs(weightedMeanFactor(plan) - 1) < 1e-9);
});

test('phaseAt: an exact boundary belongs to the next phase', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(phaseAt(plan, 0), 0);
	assert.equal(phaseAt(plan, plan[1].startM - 0.001), 0);
	assert.equal(phaseAt(plan, plan[1].startM), 1);
	assert.equal(phaseAt(plan, plan[2].startM), 2);
});

test('phaseAt clamps: past the end to last, negative to first, empty to -1', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(phaseAt(plan, 42_195), 2);
	assert.equal(phaseAt(plan, 100_000), 2);
	assert.equal(phaseAt(plan, -5), 0);
	assert.equal(phaseAt([], 1_000), -1);
});

test('a non-positive or non-finite distance yields an empty plan', () => {
	for (const distanceM of [0, -42_195, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.deepEqual(buildPhasePlan(distanceM, 'ten_ten_ten'), []);
		assert.deepEqual(buildPhasePlan(distanceM, 'negative_split'), []);
		assert.deepEqual(buildPhasePlan(distanceM, 'even'), []);
	}
});

test('goalPaceSecPerKm divides the goal time over the km and rejects bad inputs', () => {
	assert.equal(goalPaceSecPerKm(10_000, 3_000), 300);
	assert.equal(goalPaceSecPerKm(0, 3_000), null);
	assert.equal(goalPaceSecPerKm(-1, 3_000), null);
	assert.equal(goalPaceSecPerKm(10_000, 0), null);
	assert.equal(goalPaceSecPerKm(10_000, -60), null);
	assert.equal(goalPaceSecPerKm(Number.NaN, 3_000), null);
	assert.equal(goalPaceSecPerKm(10_000, Number.NaN), null);
});

test('phaseTargetPaceSecPerKm scales the goal pace by the phase factor and rejects bad pace', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.ok(Math.abs(phaseTargetPaceSecPerKm(plan[0], 300)! - 306) < 1e-9);
	assert.equal(phaseTargetPaceSecPerKm(plan[1], 300), 300);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], null), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], 0), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], -300), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], Number.NaN), null);
});

test('preset and intent wire names are stable', () => {
	const presets: RacePhasePreset[] = ['ten_ten_ten', 'negative_split', 'even'];
	const intents: RacePhaseIntent[] = ['hold_back', 'settle', 'race', 'even'];
	assert.deepEqual(presets, ['ten_ten_ten', 'negative_split', 'even']);
	assert.deepEqual(intents, ['hold_back', 'settle', 'race', 'even']);
});
