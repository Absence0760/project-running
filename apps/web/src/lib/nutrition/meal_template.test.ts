import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	templateFromEntries,
	entriesFromTemplate,
	type TemplateSourceEntry,
	type PlannedTemplate,
	type PlannedTemplateItem,
} from './meal_template';

function entry(
	item_name: string,
	opts: Partial<TemplateSourceEntry> = {},
): TemplateSourceEntry {
	return { item_name, ...opts };
}

function pitem(
	position: number,
	itemName: string,
	opts: Partial<PlannedTemplateItem> = {},
): PlannedTemplateItem {
	return {
		position,
		itemName,
		mealSlot: null,
		calories: null,
		proteinG: null,
		carbsG: null,
		fatG: null,
		externalId: null,
		...opts,
	};
}

// ── templateFromEntries ─────────────────────────────────────────────────────

test('templateFromEntries copies name, item order, and macros', () => {
	const d = templateFromEntries('Pre-run breakfast', [
		entry('Oats', { calories: 300, protein_g: 10, carbs_g: 54, fat_g: 6 }),
		entry('Banana', { calories: 105, carbs_g: 27 }),
	]);
	assert.equal(d.name, 'Pre-run breakfast');
	assert.equal(d.itemCount, 2);
	assert.equal(d.items.length, 2);
	assert.deepEqual(
		d.items.map((i) => [i.position, i.itemName]),
		[[0, 'Oats'], [1, 'Banana']],
	);
	assert.equal(d.items[0].calories, 300);
	assert.equal(d.items[0].proteinG, 10);
	assert.equal(d.items[1].carbsG, 27);
	assert.equal(d.items[1].calories, 105);
	assert.equal(d.items[1].proteinG, null);
});

test('templateFromEntries falls back to default name when blank', () => {
	assert.equal(templateFromEntries('', [entry('Egg')]).name, 'Meal');
	assert.equal(templateFromEntries('   ', [entry('Egg')]).name, 'Meal');
	assert.equal(templateFromEntries(null, [entry('Egg')]).name, 'Meal');
	assert.equal(templateFromEntries(undefined, [entry('Egg')]).name, 'Meal');
});

test('templateFromEntries honours a custom fallback name', () => {
	assert.equal(templateFromEntries('', [entry('Egg')], 'Lunch box').name, 'Lunch box');
});

test('templateFromEntries drops blank-named entries and re-indexes positions', () => {
	const d = templateFromEntries('x', [
		entry('Oats'),
		entry('   '),
		entry(''),
		entry('Coffee'),
	]);
	assert.equal(d.itemCount, 2);
	assert.deepEqual(
		d.items.map((i) => [i.position, i.itemName]),
		[[0, 'Oats'], [1, 'Coffee']],
	);
});

test('templateFromEntries trims item names', () => {
	const d = templateFromEntries('x', [entry('  Greek yogurt  ')]);
	assert.equal(d.items[0].itemName, 'Greek yogurt');
});

test('templateFromEntries default slot = common slot when all agree', () => {
	const d = templateFromEntries('x', [
		entry('Oats', { meal_slot: 'breakfast' }),
		entry('Banana', { meal_slot: 'breakfast' }),
	]);
	assert.equal(d.mealSlot, 'breakfast');
});

test('templateFromEntries default slot = null when slots disagree', () => {
	const d = templateFromEntries('x', [
		entry('Oats', { meal_slot: 'breakfast' }),
		entry('Soup', { meal_slot: 'lunch' }),
	]);
	assert.equal(d.mealSlot, null);
});

test('templateFromEntries slotless entries do not veto a common slot', () => {
	const d = templateFromEntries('x', [
		entry('Oats', { meal_slot: 'dinner' }),
		entry('Water'),
		entry('Rice', { meal_slot: 'dinner' }),
	]);
	assert.equal(d.mealSlot, 'dinner');
});

test('templateFromEntries default slot = null when no entry has a slot', () => {
	const d = templateFromEntries('x', [entry('Oats'), entry('Banana')]);
	assert.equal(d.mealSlot, null);
});

test('templateFromEntries keeps per-item slot even when default is null', () => {
	const d = templateFromEntries('x', [
		entry('Oats', { meal_slot: 'breakfast' }),
		entry('Soup', { meal_slot: 'lunch' }),
	]);
	assert.equal(d.items[0].mealSlot, 'breakfast');
	assert.equal(d.items[1].mealSlot, 'lunch');
});

test('templateFromEntries ignores an invalid slot value', () => {
	const d = templateFromEntries('x', [
		entry('Oats', { meal_slot: 'brunch' as unknown as 'breakfast' }),
	]);
	assert.equal(d.items[0].mealSlot, null);
	assert.equal(d.mealSlot, null);
});

test('templateFromEntries coerces numeric strings and rejects NaN macros', () => {
	const d = templateFromEntries('x', [
		entry('Oats', {
			calories: '300' as unknown as number,
			protein_g: 'abc' as unknown as number,
		}),
	]);
	assert.equal(d.items[0].calories, 300);
	assert.equal(d.items[0].proteinG, null);
});

test('templateFromEntries preserves the Open Food Facts external_id', () => {
	const d = templateFromEntries('x', [entry('Oats', { external_id: 'off:123' })]);
	assert.equal(d.items[0].externalId, 'off:123');
});

test('templateFromEntries empty input yields an empty draft', () => {
	const d = templateFromEntries('Empty', []);
	assert.equal(d.itemCount, 0);
	assert.equal(d.items.length, 0);
	assert.equal(d.mealSlot, null);
});

// ── entriesFromTemplate ─────────────────────────────────────────────────────

function tpl(items: PlannedTemplateItem[], mealSlot: PlannedTemplate['mealSlot'] = null): PlannedTemplate {
	return { name: 'T', mealSlot, items };
}

test('entriesFromTemplate maps items to log inputs in position order', () => {
	const inputs = entriesFromTemplate(
		tpl([
			pitem(1, 'Banana', { calories: 105 }),
			pitem(0, 'Oats', { calories: 300, proteinG: 10 }),
		]),
	);
	assert.deepEqual(
		inputs.map((i) => i.itemName),
		['Oats', 'Banana'],
	);
	assert.equal(inputs[0].calories, 300);
	assert.equal(inputs[0].proteinG, 10);
	assert.equal(inputs[1].calories, 105);
});

test('entriesFromTemplate item slot wins over template + override', () => {
	const inputs = entriesFromTemplate(
		tpl([pitem(0, 'Oats', { mealSlot: 'breakfast' })], 'dinner'),
		'lunch',
	);
	assert.equal(inputs[0].mealSlot, 'breakfast');
});

test('entriesFromTemplate template default slot fills a slotless item', () => {
	const inputs = entriesFromTemplate(tpl([pitem(0, 'Oats')], 'dinner'), 'lunch');
	assert.equal(inputs[0].mealSlot, 'dinner');
});

test('entriesFromTemplate override fills when item + template slot are null', () => {
	const inputs = entriesFromTemplate(tpl([pitem(0, 'Oats')], null), 'snack');
	assert.equal(inputs[0].mealSlot, 'snack');
});

test('entriesFromTemplate slot is null when nothing supplies one', () => {
	const inputs = entriesFromTemplate(tpl([pitem(0, 'Oats')], null), null);
	assert.equal(inputs[0].mealSlot, null);
});

test('entriesFromTemplate carries macros + external_id through', () => {
	const inputs = entriesFromTemplate(
		tpl([
			pitem(0, 'Oats', {
				calories: 300,
				proteinG: 10,
				carbsG: 54,
				fatG: 6,
				externalId: 'off:42',
			}),
		]),
	);
	assert.deepEqual(inputs[0], {
		itemName: 'Oats',
		mealSlot: null,
		calories: 300,
		proteinG: 10,
		carbsG: 54,
		fatG: 6,
		externalId: 'off:42',
	});
});

test('entriesFromTemplate empty template yields no inputs', () => {
	assert.deepEqual(entriesFromTemplate(tpl([])), []);
});

test('entriesFromTemplate round-trips a saved-then-logged meal', () => {
	const draft = templateFromEntries('Lunch', [
		entry('Chicken', { meal_slot: 'lunch', calories: 250, protein_g: 40 }),
		entry('Rice', { meal_slot: 'lunch', calories: 200, carbs_g: 44 }),
	]);
	const planned: PlannedTemplate = {
		name: draft.name,
		mealSlot: draft.mealSlot,
		items: draft.items,
	};
	const inputs = entriesFromTemplate(planned);
	assert.equal(inputs.length, 2);
	assert.equal(inputs[0].itemName, 'Chicken');
	assert.equal(inputs[0].mealSlot, 'lunch');
	assert.equal(inputs[0].calories, 250);
	assert.equal(inputs[1].carbsG, 44);
});
