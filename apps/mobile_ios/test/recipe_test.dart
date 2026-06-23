import 'package:flutter_test/flutter_test.dart';

import '../lib/recipe.dart';

RecipeSourceEntry entry(
  String itemName, {
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
}) =>
    RecipeSourceEntry(
      itemName: itemName,
      mealSlot: mealSlot,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      externalId: externalId,
    );

PlannedRecipeIngredient ing(
  int position,
  String itemName, {
  double quantity = 1,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
}) =>
    PlannedRecipeIngredient(
      position: position,
      itemName: itemName,
      quantity: quantity,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      externalId: externalId,
    );

PlannedRecipe recipe(
  List<PlannedRecipeIngredient> ingredients, {
  double servings = 1,
  String? mealSlot,
}) =>
    PlannedRecipe(
      name: 'R',
      servings: servings,
      mealSlot: mealSlot,
      ingredients: ingredients,
    );

void main() {
  // ── recipeFromEntries ──────────────────────────────────────────────────

  test('recipeFromEntries copies name, ingredient order, and macros', () {
    final d = recipeFromEntries('Overnight oats', [
      entry('Oats', calories: 300, proteinG: 10, carbsG: 54, fatG: 6),
      entry('Banana', calories: 105, carbsG: 27),
    ]);
    expect(d.name, 'Overnight oats');
    expect(d.ingredientCount, 2);
    expect(d.ingredients.length, 2);
    expect(d.ingredients.map((i) => [i.position, i.itemName]).toList(),
        [[0, 'Oats'], [1, 'Banana']]);
    expect(d.ingredients[0].calories, 300);
    expect(d.ingredients[1].carbsG, 27);
    expect(d.ingredients[1].proteinG, isNull);
  });

  test('recipeFromEntries defaults to one serving', () {
    expect(recipeFromEntries('x', [entry('Oats')]).servings, 1);
  });

  test('recipeFromEntries ingredients default to quantity 1', () {
    expect(recipeFromEntries('x', [entry('Oats')]).ingredients[0].quantity, 1);
  });

  test('recipeFromEntries falls back to default name when blank', () {
    expect(recipeFromEntries('', [entry('Egg')]).name, 'Recipe');
    expect(recipeFromEntries('   ', [entry('Egg')]).name, 'Recipe');
    expect(recipeFromEntries(null, [entry('Egg')]).name, 'Recipe');
  });

  test('recipeFromEntries derives the common meal slot, else null', () {
    expect(
      recipeFromEntries('Chilli', [
        entry('Beans', mealSlot: 'dinner'),
        entry('Rice', mealSlot: 'dinner'),
      ]).mealSlot,
      'dinner',
    );
    // A slotless entry doesn't veto agreement.
    expect(
      recipeFromEntries('Chilli', [
        entry('Beans', mealSlot: 'dinner'),
        entry('Rice'),
      ]).mealSlot,
      'dinner',
    );
    // Mixed slots → no single default.
    expect(
      recipeFromEntries('Mix', [
        entry('Eggs', mealSlot: 'breakfast'),
        entry('Rice', mealSlot: 'dinner'),
      ]).mealSlot,
      isNull,
    );
    // No slots at all → null.
    expect(recipeFromEntries('Plain', [entry('Oats')]).mealSlot, isNull);
  });

  test('recipeFromEntries honours a custom fallback name', () {
    expect(
        recipeFromEntries('', [entry('Egg')], fallbackName: 'Chilli').name,
        'Chilli');
  });

  test('recipeFromEntries drops blank-named entries and re-indexes positions',
      () {
    final d = recipeFromEntries(
        'x', [entry('Oats'), entry('   '), entry(''), entry('Coffee')]);
    expect(d.ingredientCount, 2);
    expect(d.ingredients.map((i) => [i.position, i.itemName]).toList(),
        [[0, 'Oats'], [1, 'Coffee']]);
  });

  test('recipeFromEntries trims item names', () {
    final d = recipeFromEntries('x', [entry('  Greek yogurt  ')]);
    expect(d.ingredients[0].itemName, 'Greek yogurt');
  });

  test('recipeFromEntries rejects NaN macros', () {
    final d = recipeFromEntries('x', [
      entry('Oats', calories: 300, proteinG: double.nan),
    ]);
    expect(d.ingredients[0].calories, 300);
    expect(d.ingredients[0].proteinG, isNull);
  });

  test('recipeFromEntries preserves the Open Food Facts external_id', () {
    final d = recipeFromEntries('x', [entry('Oats', externalId: 'off:123')]);
    expect(d.ingredients[0].externalId, 'off:123');
  });

  test('recipeFromEntries empty input yields an empty draft', () {
    final d = recipeFromEntries('Empty', []);
    expect(d.ingredientCount, 0);
    expect(d.ingredients.length, 0);
  });

  // ── sumRecipe ──────────────────────────────────────────────────────────

  test('sumRecipe adds ingredient macros across the recipe', () {
    final m = sumRecipe(servings: 1, ingredients: [
      ing(0, 'Oats', calories: 300, proteinG: 10, carbsG: 54, fatG: 6),
      ing(1, 'Banana', calories: 105, carbsG: 27),
    ]);
    expect(m.calories, 405);
    expect(m.proteinG, 10);
    expect(m.carbsG, 81);
    expect(m.fatG, 6);
  });

  test('sumRecipe scales an ingredient by its quantity', () {
    final m = sumRecipe(servings: 1, ingredients: [
      ing(0, 'Egg', quantity: 3, calories: 70, proteinG: 6),
    ]);
    expect(m.calories, 210);
    expect(m.proteinG, 18);
  });

  test('sumRecipe divides the total by servings', () {
    final m = sumRecipe(servings: 4, ingredients: [
      ing(0, 'Stew', calories: 2000, proteinG: 120),
    ]);
    expect(m.calories, 500);
    expect(m.proteinG, 30);
  });

  test('sumRecipe rounds per-serving macros to 0.1', () {
    final m = sumRecipe(servings: 3, ingredients: [
      ing(0, 'Mix', calories: 100, proteinG: 10),
    ]);
    expect(m.calories, 33.3);
    expect(m.proteinG, 3.3);
  });

  test('sumRecipe missing macro on one ingredient contributes 0, not null', () {
    final m = sumRecipe(servings: 1, ingredients: [
      ing(0, 'A', calories: 100, proteinG: 10),
      ing(1, 'B', calories: 50),
    ]);
    expect(m.calories, 150);
    expect(m.proteinG, 10);
  });

  test('sumRecipe a macro stays null when no ingredient carries it', () {
    final m = sumRecipe(servings: 1, ingredients: [
      ing(0, 'A', calories: 100),
      ing(1, 'B', calories: 50),
    ]);
    expect(m.calories, 150);
    expect(m.proteinG, isNull);
    expect(m.carbsG, isNull);
    expect(m.fatG, isNull);
  });

  test('sumRecipe clamps servings below 1 to 1', () {
    final m = sumRecipe(servings: 0, ingredients: [ing(0, 'A', calories: 100)]);
    expect(m.calories, 100);
  });

  test('sumRecipe treats a negative quantity as 1', () {
    final m = sumRecipe(servings: 1, ingredients: [
      ing(0, 'A', quantity: -2, calories: 100),
    ]);
    expect(m.calories, 100);
  });

  test('sumRecipe empty recipe yields all-null macros', () {
    final m = sumRecipe(servings: 1, ingredients: []);
    expect(m.calories, isNull);
    expect(m.proteinG, isNull);
    expect(m.carbsG, isNull);
    expect(m.fatG, isNull);
  });

  // ── logInputFromRecipe ─────────────────────────────────────────────────

  test('logInputFromRecipe yields one entry with the recipe name + summed macros',
      () {
    final input = logInputFromRecipe(recipe([
      ing(0, 'Oats', calories: 300, proteinG: 10),
      ing(1, 'Banana', calories: 105),
    ]));
    expect(input, isNotNull);
    expect(input!.itemName, 'R');
    expect(input.calories, 405);
    expect(input.proteinG, 10);
    expect(input.externalId, isNull);
  });

  test('logInputFromRecipe uses the recipe default slot over the override', () {
    final input = logInputFromRecipe(
        recipe([ing(0, 'A', calories: 1)], mealSlot: 'dinner'),
        slotOverride: 'lunch');
    expect(input?.mealSlot, 'dinner');
  });

  test('logInputFromRecipe falls back to the override slot when no default', () {
    final input = logInputFromRecipe(recipe([ing(0, 'A', calories: 1)]),
        slotOverride: 'snack');
    expect(input?.mealSlot, 'snack');
  });

  test('logInputFromRecipe ignores an invalid override slot', () {
    final input = logInputFromRecipe(recipe([ing(0, 'A', calories: 1)]),
        slotOverride: 'brunch');
    expect(input?.mealSlot, isNull);
  });

  test('logInputFromRecipe empty recipe yields null', () {
    expect(logInputFromRecipe(recipe([])), isNull);
  });

  test('logInputFromRecipe round-trips a saved-then-logged recipe across servings',
      () {
    final draft = recipeFromEntries('Chilli', [
      entry('Beans', calories: 400, proteinG: 24),
      entry('Mince', calories: 600, proteinG: 90),
    ]);
    final planned = PlannedRecipe(
      name: draft.name,
      servings: 2,
      mealSlot: 'dinner',
      ingredients: draft.ingredients
          .map((i) => PlannedRecipeIngredient(
                position: i.position,
                itemName: i.itemName,
                quantity: i.quantity,
                calories: i.calories,
                proteinG: i.proteinG,
                carbsG: i.carbsG,
                fatG: i.fatG,
                externalId: i.externalId,
              ))
          .toList(),
    );
    final input = logInputFromRecipe(planned);
    expect(input, isNotNull);
    expect(input!.itemName, 'Chilli');
    expect(input.mealSlot, 'dinner');
    expect(input.calories, 500);
    expect(input.proteinG, 57);
  });
}
