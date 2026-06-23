import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	recipeFromEntries,
	sumRecipe,
	logInputFromRecipe,
	type RecipeSourceEntry,
	type PlannedRecipe,
	type PlannedRecipeIngredient,
} from './recipe';

function entry(item_name: string, opts: Partial<RecipeSourceEntry> = {}): RecipeSourceEntry {
	return { item_name, ...opts };
}

function ing(
	position: number,
	itemName: string,
	opts: Partial<PlannedRecipeIngredient> = {},
): PlannedRecipeIngredient {
	return {
		position,
		itemName,
		quantity: 1,
		calories: null,
		proteinG: null,
		carbsG: null,
		fatG: null,
		externalId: null,
		...opts,
	};
}

// ── recipeFromEntries ───────────────────────────────────────────────────────

test('recipeFromEntries copies name, ingredient order, and macros', () => {
	const d = recipeFromEntries('Overnight oats', [
		entry('Oats', { calories: 300, protein_g: 10, carbs_g: 54, fat_g: 6 }),
		entry('Banana', { calories: 105, carbs_g: 27 }),
	]);
	assert.equal(d.name, 'Overnight oats');
	assert.equal(d.ingredientCount, 2);
	assert.equal(d.ingredients.length, 2);
	assert.deepEqual(
		d.ingredients.map((i) => [i.position, i.itemName]),
		[[0, 'Oats'], [1, 'Banana']],
	);
	assert.equal(d.ingredients[0].calories, 300);
	assert.equal(d.ingredients[1].carbsG, 27);
	assert.equal(d.ingredients[1].proteinG, null);
});

test('recipeFromEntries defaults to one serving', () => {
	assert.equal(recipeFromEntries('x', [entry('Oats')]).servings, 1);
});

test('recipeFromEntries ingredients default to quantity 1', () => {
	assert.equal(recipeFromEntries('x', [entry('Oats')]).ingredients[0].quantity, 1);
});

test('recipeFromEntries falls back to default name when blank', () => {
	assert.equal(recipeFromEntries('', [entry('Egg')]).name, 'Recipe');
	assert.equal(recipeFromEntries('   ', [entry('Egg')]).name, 'Recipe');
	assert.equal(recipeFromEntries(null, [entry('Egg')]).name, 'Recipe');
	assert.equal(recipeFromEntries(undefined, [entry('Egg')]).name, 'Recipe');
});

test('recipeFromEntries derives the common meal slot, else null', () => {
	// All-agree → that slot.
	assert.equal(
		recipeFromEntries('Chilli', [
			entry('Beans', { meal_slot: 'dinner' }),
			entry('Rice', { meal_slot: 'dinner' }),
		]).mealSlot,
		'dinner',
	);
	// A slotless entry doesn't veto agreement.
	assert.equal(
		recipeFromEntries('Chilli', [
			entry('Beans', { meal_slot: 'dinner' }),
			entry('Rice'),
		]).mealSlot,
		'dinner',
	);
	// Mixed slots → no single default.
	assert.equal(
		recipeFromEntries('Mix', [
			entry('Eggs', { meal_slot: 'breakfast' }),
			entry('Rice', { meal_slot: 'dinner' }),
		]).mealSlot,
		null,
	);
	// No slots at all → null.
	assert.equal(recipeFromEntries('Plain', [entry('Oats')]).mealSlot, null);
});

test('recipeFromEntries honours a custom fallback name', () => {
	assert.equal(recipeFromEntries('', [entry('Egg')], 'Chilli').name, 'Chilli');
});

test('recipeFromEntries drops blank-named entries and re-indexes positions', () => {
	const d = recipeFromEntries('x', [entry('Oats'), entry('   '), entry(''), entry('Coffee')]);
	assert.equal(d.ingredientCount, 2);
	assert.deepEqual(
		d.ingredients.map((i) => [i.position, i.itemName]),
		[[0, 'Oats'], [1, 'Coffee']],
	);
});

test('recipeFromEntries trims item names', () => {
	const d = recipeFromEntries('x', [entry('  Greek yogurt  ')]);
	assert.equal(d.ingredients[0].itemName, 'Greek yogurt');
});

test('recipeFromEntries coerces numeric strings and rejects NaN macros', () => {
	const d = recipeFromEntries('x', [
		entry('Oats', {
			calories: '300' as unknown as number,
			protein_g: 'abc' as unknown as number,
		}),
	]);
	assert.equal(d.ingredients[0].calories, 300);
	assert.equal(d.ingredients[0].proteinG, null);
});

test('recipeFromEntries preserves the Open Food Facts external_id', () => {
	const d = recipeFromEntries('x', [entry('Oats', { external_id: 'off:123' })]);
	assert.equal(d.ingredients[0].externalId, 'off:123');
});

test('recipeFromEntries empty input yields an empty draft', () => {
	const d = recipeFromEntries('Empty', []);
	assert.equal(d.ingredientCount, 0);
	assert.equal(d.ingredients.length, 0);
});

// ── sumRecipe ────────────────────────────────────────────────────────────────

test('sumRecipe adds ingredient macros across the recipe', () => {
	const m = sumRecipe({
		servings: 1,
		ingredients: [
			ing(0, 'Oats', { calories: 300, proteinG: 10, carbsG: 54, fatG: 6 }),
			ing(1, 'Banana', { calories: 105, carbsG: 27 }),
		],
	});
	assert.equal(m.calories, 405);
	assert.equal(m.proteinG, 10);
	assert.equal(m.carbsG, 81);
	assert.equal(m.fatG, 6);
});

test('sumRecipe scales an ingredient by its quantity', () => {
	const m = sumRecipe({
		servings: 1,
		ingredients: [ing(0, 'Egg', { quantity: 3, calories: 70, proteinG: 6 })],
	});
	assert.equal(m.calories, 210);
	assert.equal(m.proteinG, 18);
});

test('sumRecipe divides the total by servings', () => {
	const m = sumRecipe({
		servings: 4,
		ingredients: [ing(0, 'Stew', { calories: 2000, proteinG: 120 })],
	});
	assert.equal(m.calories, 500);
	assert.equal(m.proteinG, 30);
});

test('sumRecipe rounds per-serving macros to 0.1', () => {
	const m = sumRecipe({
		servings: 3,
		ingredients: [ing(0, 'Mix', { calories: 100, proteinG: 10 })],
	});
	assert.equal(m.calories, 33.3);
	assert.equal(m.proteinG, 3.3);
});

test('sumRecipe missing macro on one ingredient contributes 0, not null', () => {
	const m = sumRecipe({
		servings: 1,
		ingredients: [
			ing(0, 'A', { calories: 100, proteinG: 10 }),
			ing(1, 'B', { calories: 50 }),
		],
	});
	assert.equal(m.calories, 150);
	assert.equal(m.proteinG, 10);
});

test('sumRecipe a macro stays null when no ingredient carries it', () => {
	const m = sumRecipe({
		servings: 1,
		ingredients: [ing(0, 'A', { calories: 100 }), ing(1, 'B', { calories: 50 })],
	});
	assert.equal(m.calories, 150);
	assert.equal(m.proteinG, null);
	assert.equal(m.carbsG, null);
	assert.equal(m.fatG, null);
});

test('sumRecipe clamps servings below 1 to 1', () => {
	const m = sumRecipe({
		servings: 0,
		ingredients: [ing(0, 'A', { calories: 100 })],
	});
	assert.equal(m.calories, 100);
});

test('sumRecipe treats a negative quantity as 1', () => {
	const m = sumRecipe({
		servings: 1,
		ingredients: [ing(0, 'A', { quantity: -2, calories: 100 })],
	});
	assert.equal(m.calories, 100);
});

test('sumRecipe empty recipe yields all-null macros', () => {
	const m = sumRecipe({ servings: 1, ingredients: [] });
	assert.deepEqual(m, { calories: null, proteinG: null, carbsG: null, fatG: null });
});

// ── logInputFromRecipe ─────────────────────────────────────────────────────

function recipe(
	ingredients: PlannedRecipeIngredient[],
	opts: { servings?: number; mealSlot?: PlannedRecipe['mealSlot'] } = {},
): PlannedRecipe {
	return { name: 'R', servings: opts.servings ?? 1, mealSlot: opts.mealSlot ?? null, ingredients };
}

test('logInputFromRecipe yields one entry with the recipe name + summed macros', () => {
	const input = logInputFromRecipe(
		recipe([
			ing(0, 'Oats', { calories: 300, proteinG: 10 }),
			ing(1, 'Banana', { calories: 105 }),
		]),
	);
	assert.ok(input);
	assert.equal(input.itemName, 'R');
	assert.equal(input.calories, 405);
	assert.equal(input.proteinG, 10);
	assert.equal(input.externalId, null);
});

test('logInputFromRecipe uses the recipe default slot over the override', () => {
	const input = logInputFromRecipe(recipe([ing(0, 'A', { calories: 1 })], { mealSlot: 'dinner' }), 'lunch');
	assert.equal(input?.mealSlot, 'dinner');
});

test('logInputFromRecipe falls back to the override slot when no default', () => {
	const input = logInputFromRecipe(recipe([ing(0, 'A', { calories: 1 })]), 'snack');
	assert.equal(input?.mealSlot, 'snack');
});

test('logInputFromRecipe ignores an invalid override slot', () => {
	const input = logInputFromRecipe(
		recipe([ing(0, 'A', { calories: 1 })]),
		'brunch' as unknown as 'lunch',
	);
	assert.equal(input?.mealSlot, null);
});

test('logInputFromRecipe empty recipe yields null', () => {
	assert.equal(logInputFromRecipe(recipe([])), null);
});

test('logInputFromRecipe round-trips a saved-then-logged recipe across servings', () => {
	const draft = recipeFromEntries('Chilli', [
		entry('Beans', { calories: 400, protein_g: 24 }),
		entry('Mince', { calories: 600, protein_g: 90 }),
	]);
	const planned: PlannedRecipe = {
		name: draft.name,
		servings: 2,
		mealSlot: 'dinner',
		ingredients: draft.ingredients,
	};
	const input = logInputFromRecipe(planned);
	assert.ok(input);
	assert.equal(input.itemName, 'Chilli');
	assert.equal(input.mealSlot, 'dinner');
	assert.equal(input.calories, 500);
	assert.equal(input.proteinG, 57);
});
