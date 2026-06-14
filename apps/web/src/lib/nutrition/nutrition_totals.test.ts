import assert from 'node:assert/strict';
import { test } from 'node:test';

import { groupByMealSlot, ringFraction, sumMacros, type MacroRow } from './nutrition_totals';

const rows: MacroRow[] = [
	{ calories: 412, protein_g: 12, carbs_g: 58, fat_g: 8, meal_slot: 'breakfast' },
	{ calories: 640, protein_g: 48, carbs_g: 52, fat_g: 20, meal_slot: 'lunch' },
	{ calories: 150, protein_g: null, carbs_g: 30, fat_g: null, meal_slot: null }, // → snack
];

test('sumMacros sums fields, treating null as zero', () => {
	const t = sumMacros(rows);
	assert.equal(t.calories, 1202);
	assert.equal(t.proteinG, 60);
	assert.equal(t.carbsG, 140);
	assert.equal(t.fatG, 28);
});

test('sumMacros of an empty day is all zeros', () => {
	assert.deepEqual(sumMacros([]), { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 });
});

test('groupByMealSlot orders slots and omits empty ones', () => {
	const groups = groupByMealSlot(rows);
	assert.deepEqual(groups.map((g) => g.slot), ['breakfast', 'lunch', 'snack']);
	// dinner has no entries → omitted entirely
	assert.equal(groups.find((g) => g.slot === 'dinner'), undefined);
	// null-slot row folds into snack
	assert.equal(groups.find((g) => g.slot === 'snack')!.entries.length, 1);
	assert.equal(groups.find((g) => g.slot === 'breakfast')!.calories, 412);
});

test('groupByMealSlot sums calories across multiple entries in one slot', () => {
	const many: MacroRow[] = [
		{ calories: 100, protein_g: null, carbs_g: null, fat_g: null, meal_slot: 'breakfast' },
		{ calories: 250, protein_g: null, carbs_g: null, fat_g: null, meal_slot: 'breakfast' },
		{ calories: null, protein_g: 5, carbs_g: null, fat_g: null, meal_slot: 'breakfast' }, // null kcal → 0
		{ calories: 300, protein_g: null, carbs_g: null, fat_g: null, meal_slot: null }, // → snack
	];
	const groups = groupByMealSlot(many);
	assert.deepEqual(groups.map((g) => g.slot), ['breakfast', 'snack']);
	const breakfast = groups.find((g) => g.slot === 'breakfast')!;
	assert.equal(breakfast.entries.length, 3);
	assert.equal(breakfast.calories, 350);
	assert.equal(groups.find((g) => g.slot === 'snack')!.calories, 300);
});

test('groupByMealSlot preserves entry order within a slot', () => {
	const ordered: MacroRow[] = [
		{ calories: 1, protein_g: null, carbs_g: null, fat_g: null, meal_slot: 'lunch' },
		{ calories: 2, protein_g: null, carbs_g: null, fat_g: null, meal_slot: 'lunch' },
		{ calories: 3, protein_g: null, carbs_g: null, fat_g: null, meal_slot: 'lunch' },
	];
	const lunch = groupByMealSlot(ordered).find((g) => g.slot === 'lunch')!;
	assert.deepEqual(lunch.entries.map((e) => e.calories), [1, 2, 3]);
});

test('ringFraction clamps to [0,1] and hides on a missing/zero target', () => {
	assert.equal(ringFraction(500, 2000), 0.25);
	assert.equal(ringFraction(3000, 2000), 1); // clamped
	assert.equal(ringFraction(500, null), null);
	assert.equal(ringFraction(500, 0), null);
});
