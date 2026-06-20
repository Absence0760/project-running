// Recipe ingredient-sum shaping (multi_modal.md § Nutrition mid tier — the
// "N ingredients -> one logged meal" item after Meal templates).
//
// Two pure transforms with no Svelte / Supabase dependencies (runs under
// `npx tsx --test`). The Dart twin is apps/mobile_android/lib/recipe.dart
// (parity pair — keep algorithm, edge cases, outputs, and test counts in
// lockstep).
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

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';

/// A logged food entry, as it arrives from `food_log` (free-text name, nullable
/// macros). The minimal shape the promotion reads.
export interface RecipeSourceEntry {
	item_name: string;
	calories?: number | null;
	protein_g?: number | null;
	carbs_g?: number | null;
	fat_g?: number | null;
	external_id?: string | null;
}

/// One ingredient within a recipe draft. Mirrors a `recipe_ingredients` row
/// (sans ids). `quantity` multiplies the macros; macros are the per-unit
/// values copied from the source entry.
export interface RecipeDraftIngredient {
	position: number;
	itemName: string;
	quantity: number;
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	externalId: string | null;
}

/// The in-memory recipe shape "Save as recipe" hands to the create call.
/// `ingredientCount` is the client-stamped denormalised count (recipes
/// non-authoritative cache — derived_state.md).
export interface RecipeDraft {
	name: string;
	servings: number;
	mealSlot: MealSlot | null;
	ingredientCount: number;
	ingredients: RecipeDraftIngredient[];
}

/// A persisted ingredient, as read back from `recipe_ingredients`.
export interface PlannedRecipeIngredient {
	position: number;
	itemName: string;
	quantity: number;
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	externalId: string | null;
}

/// A persisted recipe flattened for instantiation: its ingredients plus the
/// servings count + default slot.
export interface PlannedRecipe {
	name: string;
	servings: number;
	mealSlot: MealSlot | null;
	ingredients: PlannedRecipeIngredient[];
}

/// The summed macros of a whole recipe (across every ingredient × quantity).
/// A macro is null only when NO ingredient carried it; a present value on any
/// ingredient makes the total numeric (a missing macro on one ingredient
/// contributes 0, it does not poison the sum).
export interface RecipeMacros {
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
}

/// One food-log entry ready to insert (the shape `createFoodEntry` takes).
/// `startedAt` is left to the caller — a logged serving lands at "now" (or a
/// caller-chosen day), never at the recipe's creation time.
export interface RecipeLogInput {
	itemName: string;
	mealSlot: MealSlot | null;
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	externalId: string | null;
}

const SLOTS: readonly MealSlot[] = ['breakfast', 'lunch', 'dinner', 'snack'];

function isSlot(v: unknown): v is MealSlot {
	return typeof v === 'string' && (SLOTS as readonly string[]).includes(v);
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}

/// A positive quantity multiplier; non-finite / negative / missing falls back
/// to 1 (one of the item).
function quantityOr1(v: unknown): number {
	const n = numericOrNull(v);
	return n != null && n >= 0 ? n : 1;
}

/// A servings count of at least 1; non-finite / <1 / missing falls back to 1
/// (the recipe is the whole thing). Mirrors the `servings >= 1` CHECK.
function servingsOr1(v: unknown): number {
	const n = numericOrNull(v);
	return n != null && n >= 1 ? n : 1;
}

function round1(n: number): number {
	return Math.round(n * 10) / 10;
}

/// Promote logged food entries into a recipe draft. Blank-named entries are
/// dropped. Each surviving entry becomes one ordered ingredient at quantity 1
/// carrying its macros. The name defaults to `fallbackName` when blank; the
/// recipe defaults to a single serving (one logged serving == the whole thing).
export function recipeFromEntries(
	name: string | null | undefined,
	entries: RecipeSourceEntry[],
	fallbackName = 'Recipe',
): RecipeDraft {
	const ingredients: RecipeDraftIngredient[] = [];
	for (const e of entries) {
		const itemName = (e.item_name ?? '').trim();
		if (itemName === '') continue;
		ingredients.push({
			position: ingredients.length,
			itemName,
			quantity: 1,
			calories: numericOrNull(e.calories),
			proteinG: numericOrNull(e.protein_g),
			carbsG: numericOrNull(e.carbs_g),
			fatG: numericOrNull(e.fat_g),
			externalId: (e.external_id ?? null) || null,
		});
	}
	const finalName = (name ?? '').trim() || fallbackName;
	return {
		name: finalName,
		servings: 1,
		mealSlot: null,
		ingredientCount: ingredients.length,
		ingredients,
	};
}

/// Sum a recipe's ingredients into ONE total (each ingredient's macros × its
/// quantity), then divide by `servings` to give the macros of ONE serving.
/// A macro stays null only if no ingredient carried it; otherwise a missing
/// macro on an ingredient contributes 0. Totals round to 0.1 to match the
/// numeric(_,1) macro columns. `servings` is clamped to >= 1 (mirrors the CHECK).
export function sumRecipe(recipe: {
	servings: number;
	ingredients: Array<Pick<PlannedRecipeIngredient, 'quantity' | 'calories' | 'proteinG' | 'carbsG' | 'fatG'>>;
}): RecipeMacros {
	const servings = servingsOr1(recipe.servings);
	const acc = { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 };
	const seen = { calories: false, proteinG: false, carbsG: false, fatG: false };
	for (const ing of recipe.ingredients) {
		const q = quantityOr1(ing.quantity);
		for (const k of ['calories', 'proteinG', 'carbsG', 'fatG'] as const) {
			const v = ing[k];
			if (v != null && Number.isFinite(v)) {
				acc[k] += v * q;
				seen[k] = true;
			}
		}
	}
	return {
		calories: seen.calories ? round1(acc.calories / servings) : null,
		proteinG: seen.proteinG ? round1(acc.proteinG / servings) : null,
		carbsG: seen.carbsG ? round1(acc.carbsG / servings) : null,
		fatG: seen.fatG ? round1(acc.fatG / servings) : null,
	};
}

/// Produce the SINGLE food-log input one logged serving of a recipe
/// instantiates into: the recipe's name + its per-serving summed macros, in the
/// slot the user picked (`slotOverride`) else the recipe's default slot. An
/// empty recipe (no ingredients) yields null (the caller treats that as a
/// no-op, not an error). The summed entry carries no `external_id` — it is a
/// composite, not a single Open Food Facts product.
export function logInputFromRecipe(
	recipe: PlannedRecipe,
	slotOverride: MealSlot | null = null,
): RecipeLogInput | null {
	if (recipe.ingredients.length === 0) return null;
	const macros = sumRecipe(recipe);
	return {
		itemName: recipe.name,
		mealSlot: recipe.mealSlot ?? (isSlot(slotOverride) ? slotOverride : null),
		calories: macros.calories,
		proteinG: macros.proteinG,
		carbsG: macros.carbsG,
		fatG: macros.fatG,
		externalId: null,
	};
}
