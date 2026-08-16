import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	EXTENDED_NUTRIENTS,
	FIBER_G_PER_1000_KCAL,
	SATURATED_FAT_KCAL_FRACTION,
	SODIUM_BASELINE_MG,
	SODIUM_MG_PER_EXERCISE_MIN,
	extendedNutrientBudgets,
	extendedNutrientTargets,
	type ExtendedNutrientRow,
	type NutrientKind,
} from './extended_nutrients';
import { MAX_EXERCISE_MINUTES } from './hydration';
import type { NutritionTargets } from './nutrition_targets';

function row(over: Partial<ExtendedNutrientRow> = {}): ExtendedNutrientRow {
	return {
		fiber_g: null,
		sugar_g: null,
		sodium_mg: null,
		saturated_fat_g: null,
		cholesterol_mg: null,
		...over,
	};
}

function targets(over: Partial<NutritionTargets> = {}): NutritionTargets {
	return {
		calories: 2500,
		baseCalories: 2500,
		exerciseKcal: 0,
		proteinG: 126,
		carbsG: 300,
		fatG: 83,
		...over,
	};
}

function budgetFor(kind: NutrientKind, rows: ExtendedNutrientRow[], t = targets(), mins = 0) {
	const b = extendedNutrientBudgets(rows, extendedNutrientTargets(t, mins)).find(
		(x) => x.kind === kind,
	);
	assert.ok(b, `expected a ${kind} budget`);
	return b;
}

test('EXTENDED_NUTRIENTS covers every nullable food_log nutrient column exactly once', () => {
	const columns = EXTENDED_NUTRIENTS.map((s) => s.column).sort();
	assert.deepEqual(columns, [
		'cholesterol_mg',
		'fiber_g',
		'saturated_fat_g',
		'sodium_mg',
		'sugar_g',
	]);
	assert.equal(new Set(EXTENDED_NUTRIENTS.map((s) => s.kind)).size, EXTENDED_NUTRIENTS.length);
});

test('targets: fibre scales off the BASE calorie goal, not the exercise-inflated one', () => {
	const t = targets({ baseCalories: 2500, calories: 3300, exerciseKcal: 800 });
	const got = extendedNutrientTargets(t, 0);
	assert.equal(got.fiber, Math.round((2500 / 1000) * FIBER_G_PER_1000_KCAL));
	assert.equal(got.fiber, 35);
});

test('targets: saturated fat is a share of the FULL dynamic calorie goal', () => {
	const t = targets({ baseCalories: 2500, calories: 3300, exerciseKcal: 800 });
	const got = extendedNutrientTargets(t, 0);
	assert.equal(got.saturatedFat, Math.round((SATURATED_FAT_KCAL_FRACTION * 3300) / 9));
	assert.equal(got.saturatedFat, 37);
});

test('targets: sodium is the flat ceiling plus a per-minute sweat allowance', () => {
	assert.equal(extendedNutrientTargets(targets(), 0).sodium, SODIUM_BASELINE_MG);
	assert.equal(
		extendedNutrientTargets(targets(), 60).sodium,
		SODIUM_BASELINE_MG + 60 * SODIUM_MG_PER_EXERCISE_MIN,
	);
});

test('targets: the sodium sweat allowance stops at hydration.ts MAX_EXERCISE_MINUTES', () => {
	const capped = SODIUM_BASELINE_MG + MAX_EXERCISE_MINUTES * SODIUM_MG_PER_EXERCISE_MIN;
	assert.equal(extendedNutrientTargets(targets(), MAX_EXERCISE_MINUTES).sodium, capped);
	assert.equal(extendedNutrientTargets(targets(), 12 * 60).sodium, capped);
});

test('targets: a negative or missing exercise duration adds nothing', () => {
	assert.equal(extendedNutrientTargets(targets(), -30).sodium, SODIUM_BASELINE_MG);
	assert.equal(extendedNutrientTargets(targets(), null).sodium, SODIUM_BASELINE_MG);
	assert.equal(extendedNutrientTargets(targets(), undefined).sodium, SODIUM_BASELINE_MG);
});

test('targets: with no body metrics sodium still resolves, calorie-scaled ones do not', () => {
	const got = extendedNutrientTargets(null, 45);
	assert.equal(got.sodium, SODIUM_BASELINE_MG + 45 * SODIUM_MG_PER_EXERCISE_MIN);
	assert.equal(got.fiber, null);
	assert.equal(got.saturatedFat, null);
});

test('targets: sugar and cholesterol are deliberately ungraded', () => {
	const got = extendedNutrientTargets(targets(), 90);
	assert.equal(got.sugar, null);
	assert.equal(got.cholesterol, null);
	for (const spec of EXTENDED_NUTRIENTS) {
		if (spec.kind === 'sugar' || spec.kind === 'cholesterol') {
			assert.equal(spec.direction, 'none');
		}
	}
});

test('budgets: a nutrient no entry reported is omitted, not shown as zero', () => {
	const out = extendedNutrientBudgets(
		[row({ sodium_mg: 400 }), row({ sodium_mg: 250 })],
		extendedNutrientTargets(targets(), 0),
	);
	assert.deepEqual(
		out.map((b) => b.kind),
		['sodium'],
	);
});

test('budgets: an empty day yields nothing, so the caller self-hides the section', () => {
	assert.deepEqual(extendedNutrientBudgets([], extendedNutrientTargets(targets(), 0)), []);
	assert.deepEqual(extendedNutrientBudgets([row()], extendedNutrientTargets(targets(), 0)), []);
});

test('budgets: full coverage sums every entry and reports remaining', () => {
	const b = budgetFor('sodium', [row({ sodium_mg: 400 }), row({ sodium_mg: 250 })]);
	assert.equal(b.consumed, 650);
	assert.equal(b.reportedEntries, 2);
	assert.equal(b.totalEntries, 2);
	assert.equal(b.partial, false);
	assert.equal(b.target, SODIUM_BASELINE_MG);
	assert.equal(b.remaining, SODIUM_BASELINE_MG - 650);
	assert.equal(b.exceeded, false);
});

test('budgets: an unreported entry makes the total a lower bound and withholds remaining', () => {
	const b = budgetFor('sodium', [row({ sodium_mg: 400 }), row({ fiber_g: 3 })]);
	assert.equal(b.consumed, 400);
	assert.equal(b.reportedEntries, 1);
	assert.equal(b.totalEntries, 2);
	assert.equal(b.partial, true);
	assert.equal(b.remaining, null, 'a "1900 mg left" claim is unsound under partial coverage');
	assert.equal(b.exceeded, false);
});

test('budgets: exceeding a ceiling still holds under partial coverage', () => {
	const b = budgetFor('sodium', [row({ sodium_mg: 2600 }), row({ fiber_g: 3 }), row()]);
	assert.equal(b.partial, true);
	assert.equal(b.exceeded, true, 'the reported entries alone already clear the ceiling');
	assert.equal(b.remaining, null);
	assert.equal(b.fraction, 1);
});

test('budgets: reaching a floor still holds under partial coverage', () => {
	const b = budgetFor('fiber', [row({ fiber_g: 36 }), row({ sodium_mg: 100 })]);
	assert.equal(b.partial, true);
	assert.equal(b.reached, true, 'the reported entries alone already clear the floor');
	assert.equal(b.exceeded, false);
	assert.equal(b.remaining, null);
});

test('budgets: exactly on a ceiling is not yet exceeded; exactly on a floor is reached', () => {
	const ceiling = budgetFor('sodium', [row({ sodium_mg: SODIUM_BASELINE_MG })]);
	assert.equal(ceiling.exceeded, false);
	assert.equal(ceiling.remaining, 0);
	const floor = budgetFor('fiber', [row({ fiber_g: 35 })]);
	assert.equal(floor.reached, true);
	assert.equal(floor.remaining, 0);
});

test('budgets: an ungraded nutrient reports its total and nothing else', () => {
	const b = budgetFor('sugar', [row({ sugar_g: 42.25 })]);
	assert.equal(b.consumed, 42.3);
	assert.equal(b.target, null);
	assert.equal(b.fraction, null);
	assert.equal(b.remaining, null);
	assert.equal(b.exceeded, false);
	assert.equal(b.reached, false);
});

test('budgets: with no targets at all the totals still report, ungraded', () => {
	const out = extendedNutrientBudgets(
		[row({ fiber_g: 12, sodium_mg: 900 })],
		extendedNutrientTargets(null, 0),
	);
	const fiber = out.find((b) => b.kind === 'fiber');
	assert.ok(fiber);
	assert.equal(fiber.target, null);
	assert.equal(fiber.reached, false);
	const sodium = out.find((b) => b.kind === 'sodium');
	assert.ok(sodium);
	assert.equal(sodium.target, SODIUM_BASELINE_MG, 'sodium needs no body metrics');
});

test('budgets: grams round to 0.1 and milligrams to whole', () => {
	const fiber = budgetFor('fiber', [row({ fiber_g: 3.04 }), row({ fiber_g: 4.03 })]);
	assert.equal(fiber.consumed, 7.1);
	const sodium = budgetFor('sodium', [row({ sodium_mg: 100.4 }), row({ sodium_mg: 200.4 })]);
	assert.equal(sodium.consumed, 301);
});

test('budgets: a non-finite stored value is treated as unreported, never NaN', () => {
	const b = budgetFor('sodium', [
		row({ sodium_mg: Number.NaN }),
		row({ sodium_mg: 300 }),
	]);
	assert.equal(b.consumed, 300);
	assert.equal(b.reportedEntries, 1);
	assert.equal(b.partial, true);
});

test('budgets: results come back in EXTENDED_NUTRIENTS display order', () => {
	const out = extendedNutrientBudgets(
		[row({ fiber_g: 5, sugar_g: 9, sodium_mg: 300, saturated_fat_g: 2, cholesterol_mg: 40 })],
		extendedNutrientTargets(targets(), 0),
	);
	assert.deepEqual(
		out.map((b) => b.kind),
		EXTENDED_NUTRIENTS.map((s) => s.kind),
	);
});

test('budgets: fraction clamps to [0, 1] and never divides by a null target', () => {
	const over = budgetFor('sodium', [row({ sodium_mg: 9000 })]);
	assert.equal(over.fraction, 1);
	const none = budgetFor('cholesterol', [row({ cholesterol_mg: 500 })]);
	assert.equal(none.fraction, null);
});
