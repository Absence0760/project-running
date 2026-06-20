// Meal-template plan ↔ log shaping (multi_modal.md § Nutrition mid tier).
//
// Two pure transforms with no Svelte / Supabase dependencies (runs under
// `npx tsx --test`). The Dart twin is
// apps/mobile_android/lib/meal_template.dart (parity pair — keep algorithm,
// edge cases, outputs, and test counts in lockstep).
//
//   templateFromEntries — promote a set of logged food entries into a template
//     draft (name + ordered items carrying each entry's macros). The
//     "Save as meal" path. Mirrors gym_routine.routineFromWorkout.
//   entriesFromTemplate — expand a saved template into food-log inputs ready to
//     insert, with one tap. The "Log template" path. Mirrors
//     gym_routine.prefillFromRoutine.
//
// A template is a reusable plan, NOT a dated activity, so it never feeds the
// activities view. An item's slot falls back to the template's default slot,
// which falls back to the slot passed at log time.

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';

/// A logged food entry, as it arrives from `food_log` (free-text name, nullable
/// macros + slot). The minimal shape the promotion reads.
export interface TemplateSourceEntry {
	item_name: string;
	meal_slot?: MealSlot | null;
	calories?: number | null;
	protein_g?: number | null;
	carbs_g?: number | null;
	fat_g?: number | null;
	external_id?: string | null;
}

/// One item within a template draft. Mirrors a `meal_template_items` row
/// (sans ids). Macros are copied straight from the source entry.
export interface MealTemplateDraftItem {
	position: number;
	itemName: string;
	mealSlot: MealSlot | null;
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	externalId: string | null;
}

/// The in-memory template shape "Save as meal" hands to the create call.
/// `itemCount` is the client-stamped denormalised count (meal_templates
/// non-authoritative cache — derived_state.md). `mealSlot` is the template's
/// default slot, derived from the source entries when they all agree.
export interface MealTemplateDraft {
	name: string;
	mealSlot: MealSlot | null;
	itemCount: number;
	items: MealTemplateDraftItem[];
}

/// A persisted template item, as read back from `meal_template_items`.
export interface PlannedTemplateItem {
	position: number;
	itemName: string;
	mealSlot: MealSlot | null;
	calories: number | null;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	externalId: string | null;
}

/// A persisted template flattened for instantiation: its items (ordered by
/// `position`) plus the template default slot.
export interface PlannedTemplate {
	name: string;
	mealSlot: MealSlot | null;
	items: PlannedTemplateItem[];
}

/// One food-log entry ready to insert (the shape `createFoodEntry` takes).
/// `startedAt` is left to the caller — every instantiated item logs at "now"
/// (or a caller-chosen day), never at the template's creation time.
export interface TemplateLogInput {
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

/// The default slot for a template promoted from `entries`: the common slot
/// when every entry that has a slot agrees, else null (a mixed-slot day has no
/// single default). An entry with no slot doesn't veto agreement.
function commonSlot(entries: TemplateSourceEntry[]): MealSlot | null {
	let found: MealSlot | null = null;
	for (const e of entries) {
		const s = isSlot(e.meal_slot) ? e.meal_slot : null;
		if (s == null) continue;
		if (found == null) {
			found = s;
		} else if (found !== s) {
			return null;
		}
	}
	return found;
}

/// Promote logged food entries into a template draft. Blank-named entries are
/// dropped. Each surviving entry becomes one ordered item carrying its macros.
/// The template's default slot is the entries' common slot (above). The name
/// defaults to `fallbackName` when blank.
export function templateFromEntries(
	name: string | null | undefined,
	entries: TemplateSourceEntry[],
	fallbackName = 'Meal',
): MealTemplateDraft {
	const items: MealTemplateDraftItem[] = [];
	for (const e of entries) {
		const itemName = (e.item_name ?? '').trim();
		if (itemName === '') continue;
		items.push({
			position: items.length,
			itemName,
			mealSlot: isSlot(e.meal_slot) ? e.meal_slot : null,
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
		mealSlot: commonSlot(entries),
		itemCount: items.length,
		items,
	};
}

/// Expand a saved template into food-log inputs ready to insert. Items are
/// ordered by `position` (defensively sorted — the caller may pass them in any
/// order). Each item's slot resolves to: the item's own slot, else the
/// template's default slot, else the caller's `slotOverride` (e.g. the slot the
/// user picked in the log sheet), else null. An empty template yields no
/// inputs (the caller treats that as a no-op, not an error).
export function entriesFromTemplate(
	template: PlannedTemplate,
	slotOverride: MealSlot | null = null,
): TemplateLogInput[] {
	const ordered = [...template.items].sort((a, b) => a.position - b.position);
	return ordered.map((it) => ({
		itemName: it.itemName,
		mealSlot: it.mealSlot ?? template.mealSlot ?? slotOverride,
		calories: it.calories,
		proteinG: it.proteinG,
		carbsG: it.carbsG,
		fatG: it.fatG,
		externalId: it.externalId,
	}));
}
