// Recipe ingredient-sum shaping (multi_modal.md Nutrition mid tier — the
// "N ingredients -> one logged meal" item after Meal templates).
//
// Dart twin of apps/web/src/lib/nutrition/recipe.ts (parity pair — keep
// algorithm, edge cases, outputs, and test counts in lockstep).
//
//   recipeFromEntries — promote a set of logged food entries into a recipe
//     draft (name + ordered ingredients carrying each entry's macros). The
//     "Save as recipe" path. Mirrors meal_template.templateFromEntries.
//   sumRecipe         — sum a recipe's ingredients (each scaled by its
//     quantity) into ONE combined-macro total, then scale by servings to give
//     the per-serving macros. This is what separates a recipe from a meal
//     template: a template logs each item; a recipe logs the SUM.
//   logInputFromRecipe — produce the SINGLE food_log input one logged serving
//     of a recipe instantiates into. The "Log recipe" path.
//
// A recipe is a reusable plan, NOT a dated activity, so it never feeds the
// activities view. Logging copies into food_log (no FK), so deleting a recipe
// leaves logged meals intact.

const List<String> _slots = ['breakfast', 'lunch', 'dinner', 'snack'];

bool _isSlot(Object? v) => v is String && _slots.contains(v);

String? _slotOrNull(Object? v) => _isSlot(v) ? v as String : null;

double? _numericOrNull(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final n = double.tryParse(v);
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

/// A positive quantity multiplier; non-finite / negative / missing falls back
/// to 1 (one of the item).
double _quantityOr1(Object? v) {
  final n = _numericOrNull(v);
  return (n != null && n >= 0) ? n : 1;
}

/// A servings count of at least 1; non-finite / <1 / missing falls back to 1
/// (the recipe is the whole thing). Mirrors the `servings >= 1` CHECK.
double _servingsOr1(Object? v) {
  final n = _numericOrNull(v);
  return (n != null && n >= 1) ? n : 1;
}

double _round1(double n) => (n * 10).round() / 10;

/// A logged food entry, as it arrives from `food_log` (free-text name, nullable
/// macros). The minimal shape the promotion reads.
class RecipeSourceEntry {
  const RecipeSourceEntry({
    required this.itemName,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final String itemName;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// One ingredient within a recipe draft. Mirrors a `recipe_ingredients` row
/// (sans ids). `quantity` multiplies the macros; macros are the per-unit
/// values copied from the source entry.
class RecipeDraftIngredient {
  const RecipeDraftIngredient({
    required this.position,
    required this.itemName,
    required this.quantity,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.externalId,
  });

  final int position;
  final String itemName;
  final double quantity;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// The in-memory recipe shape "Save as recipe" hands to the create call.
/// `ingredientCount` is the client-stamped denormalised count (recipes
/// non-authoritative cache — derived_state.md).
class RecipeDraft {
  const RecipeDraft({
    required this.name,
    required this.servings,
    required this.mealSlot,
    required this.ingredientCount,
    required this.ingredients,
  });

  final String name;
  final double servings;
  final String? mealSlot;
  final int ingredientCount;
  final List<RecipeDraftIngredient> ingredients;
}

/// A persisted ingredient, as read back from `recipe_ingredients`.
class PlannedRecipeIngredient {
  const PlannedRecipeIngredient({
    required this.position,
    required this.itemName,
    this.quantity = 1,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final int position;
  final String itemName;
  final double quantity;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// A persisted recipe flattened for instantiation: its ingredients plus the
/// servings count + default slot.
class PlannedRecipe {
  const PlannedRecipe({
    required this.name,
    required this.servings,
    required this.mealSlot,
    required this.ingredients,
  });

  final String name;
  final double servings;
  final String? mealSlot;
  final List<PlannedRecipeIngredient> ingredients;
}

/// The summed macros of a whole recipe (across every ingredient × quantity).
/// A macro is null only when NO ingredient carried it; a present value on any
/// ingredient makes the total numeric (a missing macro on one ingredient
/// contributes 0, it does not poison the sum).
class RecipeMacros {
  const RecipeMacros({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
}

/// One food-log entry ready to insert (the shape the food-log create takes).
/// `startedAt` is left to the caller — a logged serving lands at "now" (or a
/// caller-chosen day), never at the recipe's creation time.
class RecipeLogInput {
  const RecipeLogInput({
    required this.itemName,
    required this.mealSlot,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.externalId,
  });

  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;
}

/// Promote logged food entries into a recipe draft. Blank-named entries are
/// dropped. Each surviving entry becomes one ordered ingredient at quantity 1
/// carrying its macros. The name defaults to `fallbackName` when blank; the
/// recipe defaults to a single serving (one logged serving == the whole thing).
RecipeDraft recipeFromEntries(
  String? name,
  List<RecipeSourceEntry> entries, {
  String fallbackName = 'Recipe',
}) {
  final ingredients = <RecipeDraftIngredient>[];
  for (final e in entries) {
    final itemName = e.itemName.trim();
    if (itemName.isEmpty) continue;
    final ext = e.externalId;
    ingredients.add(RecipeDraftIngredient(
      position: ingredients.length,
      itemName: itemName,
      quantity: 1,
      calories: _numericOrNull(e.calories),
      proteinG: _numericOrNull(e.proteinG),
      carbsG: _numericOrNull(e.carbsG),
      fatG: _numericOrNull(e.fatG),
      externalId: (ext != null && ext.isNotEmpty) ? ext : null,
    ));
  }
  final trimmed = (name ?? '').trim();
  final finalName = trimmed.isNotEmpty ? trimmed : fallbackName;
  return RecipeDraft(
    name: finalName,
    servings: 1,
    mealSlot: null,
    ingredientCount: ingredients.length,
    ingredients: ingredients,
  );
}

/// Sum a recipe's ingredients into ONE total (each ingredient's macros × its
/// quantity), then divide by `servings` to give the macros of ONE serving.
/// A macro stays null only if no ingredient carried it; otherwise a missing
/// macro on an ingredient contributes 0. Totals round to 0.1 to match the
/// numeric(_,1) macro columns. `servings` is clamped to >= 1 (mirrors the CHECK).
RecipeMacros sumRecipe({
  required double servings,
  required List<PlannedRecipeIngredient> ingredients,
}) {
  final s = _servingsOr1(servings);
  var cal = 0.0, pro = 0.0, carb = 0.0, fat = 0.0;
  var seenCal = false, seenPro = false, seenCarb = false, seenFat = false;
  for (final ing in ingredients) {
    final q = _quantityOr1(ing.quantity);
    final c = ing.calories;
    if (c != null && c.isFinite) {
      cal += c * q;
      seenCal = true;
    }
    final p = ing.proteinG;
    if (p != null && p.isFinite) {
      pro += p * q;
      seenPro = true;
    }
    final cb = ing.carbsG;
    if (cb != null && cb.isFinite) {
      carb += cb * q;
      seenCarb = true;
    }
    final f = ing.fatG;
    if (f != null && f.isFinite) {
      fat += f * q;
      seenFat = true;
    }
  }
  return RecipeMacros(
    calories: seenCal ? _round1(cal / s) : null,
    proteinG: seenPro ? _round1(pro / s) : null,
    carbsG: seenCarb ? _round1(carb / s) : null,
    fatG: seenFat ? _round1(fat / s) : null,
  );
}

/// Produce the SINGLE food-log input one logged serving of a recipe
/// instantiates into: the recipe's name + its per-serving summed macros, in the
/// slot the user picked (`slotOverride`) else the recipe's default slot. An
/// empty recipe (no ingredients) yields null (the caller treats that as a
/// no-op, not an error). The summed entry carries no `external_id` — it is a
/// composite, not a single Open Food Facts product.
RecipeLogInput? logInputFromRecipe(
  PlannedRecipe recipe, {
  String? slotOverride,
}) {
  if (recipe.ingredients.isEmpty) return null;
  final macros = sumRecipe(
    servings: recipe.servings,
    ingredients: recipe.ingredients,
  );
  return RecipeLogInput(
    itemName: recipe.name,
    mealSlot: recipe.mealSlot ?? _slotOrNull(slotOverride),
    calories: macros.calories,
    proteinG: macros.proteinG,
    carbsG: macros.carbsG,
    fatG: macros.fatG,
    externalId: null,
  );
}
