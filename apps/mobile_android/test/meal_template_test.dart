import 'package:flutter_test/flutter_test.dart';

import '../lib/meal_template.dart';

TemplateSourceEntry entry(
  String itemName, {
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
}) =>
    TemplateSourceEntry(
      itemName: itemName,
      mealSlot: mealSlot,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      externalId: externalId,
    );

PlannedTemplateItem pitem(
  int position,
  String itemName, {
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
}) =>
    PlannedTemplateItem(
      position: position,
      itemName: itemName,
      mealSlot: mealSlot,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      externalId: externalId,
    );

PlannedTemplate tpl(List<PlannedTemplateItem> items, {String? mealSlot}) =>
    PlannedTemplate(name: 'T', mealSlot: mealSlot, items: items);

void main() {
  // ── templateFromEntries ───────────────────────────────────────────────────

  test('templateFromEntries copies name, item order, and macros', () {
    final d = templateFromEntries('Pre-run breakfast', [
      entry('Oats', calories: 300, proteinG: 10, carbsG: 54, fatG: 6),
      entry('Banana', calories: 105, carbsG: 27),
    ]);
    expect(d.name, 'Pre-run breakfast');
    expect(d.itemCount, 2);
    expect(d.items.length, 2);
    expect(d.items.map((i) => [i.position, i.itemName]).toList(),
        [[0, 'Oats'], [1, 'Banana']]);
    expect(d.items[0].calories, 300);
    expect(d.items[0].proteinG, 10);
    expect(d.items[1].carbsG, 27);
    expect(d.items[1].calories, 105);
    expect(d.items[1].proteinG, null);
  });

  test('templateFromEntries falls back to default name when blank', () {
    expect(templateFromEntries('', [entry('Egg')]).name, 'Meal');
    expect(templateFromEntries('   ', [entry('Egg')]).name, 'Meal');
    expect(templateFromEntries(null, [entry('Egg')]).name, 'Meal');
  });

  test('templateFromEntries honours a custom fallback name', () {
    expect(
        templateFromEntries('', [entry('Egg')], fallbackName: 'Lunch box').name,
        'Lunch box');
  });

  test('templateFromEntries drops blank-named entries and re-indexes positions',
      () {
    final d = templateFromEntries('x', [
      entry('Oats'),
      entry('   '),
      entry(''),
      entry('Coffee'),
    ]);
    expect(d.itemCount, 2);
    expect(d.items.map((i) => [i.position, i.itemName]).toList(),
        [[0, 'Oats'], [1, 'Coffee']]);
  });

  test('templateFromEntries trims item names', () {
    final d = templateFromEntries('x', [entry('  Greek yogurt  ')]);
    expect(d.items[0].itemName, 'Greek yogurt');
  });

  test('templateFromEntries default slot = common slot when all agree', () {
    final d = templateFromEntries('x', [
      entry('Oats', mealSlot: 'breakfast'),
      entry('Banana', mealSlot: 'breakfast'),
    ]);
    expect(d.mealSlot, 'breakfast');
  });

  test('templateFromEntries default slot = null when slots disagree', () {
    final d = templateFromEntries('x', [
      entry('Oats', mealSlot: 'breakfast'),
      entry('Soup', mealSlot: 'lunch'),
    ]);
    expect(d.mealSlot, null);
  });

  test('templateFromEntries slotless entries do not veto a common slot', () {
    final d = templateFromEntries('x', [
      entry('Oats', mealSlot: 'dinner'),
      entry('Water'),
      entry('Rice', mealSlot: 'dinner'),
    ]);
    expect(d.mealSlot, 'dinner');
  });

  test('templateFromEntries default slot = null when no entry has a slot', () {
    final d = templateFromEntries('x', [entry('Oats'), entry('Banana')]);
    expect(d.mealSlot, null);
  });

  test('templateFromEntries keeps per-item slot even when default is null', () {
    final d = templateFromEntries('x', [
      entry('Oats', mealSlot: 'breakfast'),
      entry('Soup', mealSlot: 'lunch'),
    ]);
    expect(d.items[0].mealSlot, 'breakfast');
    expect(d.items[1].mealSlot, 'lunch');
  });

  test('templateFromEntries ignores an invalid slot value', () {
    final d = templateFromEntries('x', [entry('Oats', mealSlot: 'brunch')]);
    expect(d.items[0].mealSlot, null);
    expect(d.mealSlot, null);
  });

  test('templateFromEntries coerces numeric strings and rejects NaN macros',
      () {
    final d = templateFromEntries('x', [
      TemplateSourceEntry(
        itemName: 'Oats',
        calories: null,
        proteinG: double.nan,
      ),
    ]);
    expect(d.items[0].proteinG, null);
  });

  test('templateFromEntries preserves the Open Food Facts external_id', () {
    final d = templateFromEntries('x', [entry('Oats', externalId: 'off:123')]);
    expect(d.items[0].externalId, 'off:123');
  });

  test('templateFromEntries empty input yields an empty draft', () {
    final d = templateFromEntries('Empty', []);
    expect(d.itemCount, 0);
    expect(d.items.length, 0);
    expect(d.mealSlot, null);
  });

  // ── entriesFromTemplate ───────────────────────────────────────────────────

  test('entriesFromTemplate maps items to log inputs in position order', () {
    final inputs = entriesFromTemplate(tpl([
      pitem(1, 'Banana', calories: 105),
      pitem(0, 'Oats', calories: 300, proteinG: 10),
    ]));
    expect(inputs.map((i) => i.itemName).toList(), ['Oats', 'Banana']);
    expect(inputs[0].calories, 300);
    expect(inputs[0].proteinG, 10);
    expect(inputs[1].calories, 105);
  });

  test('entriesFromTemplate item slot wins over template + override', () {
    final inputs = entriesFromTemplate(
      tpl([pitem(0, 'Oats', mealSlot: 'breakfast')], mealSlot: 'dinner'),
      slotOverride: 'lunch',
    );
    expect(inputs[0].mealSlot, 'breakfast');
  });

  test('entriesFromTemplate template default slot fills a slotless item', () {
    final inputs = entriesFromTemplate(
      tpl([pitem(0, 'Oats')], mealSlot: 'dinner'),
      slotOverride: 'lunch',
    );
    expect(inputs[0].mealSlot, 'dinner');
  });

  test('entriesFromTemplate override fills when item + template slot are null',
      () {
    final inputs = entriesFromTemplate(
      tpl([pitem(0, 'Oats')]),
      slotOverride: 'snack',
    );
    expect(inputs[0].mealSlot, 'snack');
  });

  test('entriesFromTemplate slot is null when nothing supplies one', () {
    final inputs = entriesFromTemplate(tpl([pitem(0, 'Oats')]));
    expect(inputs[0].mealSlot, null);
  });

  test('entriesFromTemplate carries macros + external_id through', () {
    final inputs = entriesFromTemplate(tpl([
      pitem(0, 'Oats',
          calories: 300,
          proteinG: 10,
          carbsG: 54,
          fatG: 6,
          externalId: 'off:42'),
    ]));
    expect(inputs[0].itemName, 'Oats');
    expect(inputs[0].mealSlot, null);
    expect(inputs[0].calories, 300);
    expect(inputs[0].proteinG, 10);
    expect(inputs[0].carbsG, 54);
    expect(inputs[0].fatG, 6);
    expect(inputs[0].externalId, 'off:42');
  });

  test('entriesFromTemplate empty template yields no inputs', () {
    expect(entriesFromTemplate(tpl([])), isEmpty);
  });

  test('entriesFromTemplate round-trips a saved-then-logged meal', () {
    final draft = templateFromEntries('Lunch', [
      entry('Chicken', mealSlot: 'lunch', calories: 250, proteinG: 40),
      entry('Rice', mealSlot: 'lunch', calories: 200, carbsG: 44),
    ]);
    final planned = PlannedTemplate(
      name: draft.name,
      mealSlot: draft.mealSlot,
      items: [
        for (final it in draft.items)
          pitem(it.position, it.itemName,
              mealSlot: it.mealSlot,
              calories: it.calories,
              proteinG: it.proteinG,
              carbsG: it.carbsG,
              fatG: it.fatG,
              externalId: it.externalId),
      ],
    );
    final inputs = entriesFromTemplate(planned);
    expect(inputs.length, 2);
    expect(inputs[0].itemName, 'Chicken');
    expect(inputs[0].mealSlot, 'lunch');
    expect(inputs[0].calories, 250);
    expect(inputs[1].carbsG, 44);
  });
}
