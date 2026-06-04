/**
 * Pure aggregation for the nutrition daily view — sum a day's logged food
 * into macro totals and group it by meal slot. No Supabase / runes, so it's
 * node:test-runnable and shared by the rings + the meal-slot list.
 */

import type { FoodMacros } from './food_search';

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';

/// Display order for the daily log (and the slot picker).
export const MEAL_SLOTS: MealSlot[] = ['breakfast', 'lunch', 'dinner', 'snack'];

export const MEAL_SLOT_LABELS: Record<MealSlot, string> = {
	breakfast: 'Breakfast',
	lunch: 'Lunch',
	dinner: 'Dinner',
	snack: 'Snack',
};

export interface MacroRow {
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	meal_slot: MealSlot | null;
}

/// Sum calories + macros across entries. Null fields count as 0 so a
/// partially-logged item (calories only) still contributes.
export function sumMacros(entries: MacroRow[]): FoodMacros {
	const t = { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 };
	for (const e of entries) {
		t.calories += e.calories ?? 0;
		t.proteinG += e.protein_g ?? 0;
		t.carbsG += e.carbs_g ?? 0;
		t.fatG += e.fat_g ?? 0;
	}
	return {
		calories: Math.round(t.calories),
		proteinG: Math.round(t.proteinG),
		carbsG: Math.round(t.carbsG),
		fatG: Math.round(t.fatG),
	};
}

export interface MealSlotGroup<T extends MacroRow> {
	slot: MealSlot;
	label: string;
	entries: T[];
	calories: number;
}

/// Group entries into the four meal slots in display order, omitting empty
/// slots (anti-clutter — no "Dinner 0 kcal" row). Entries with a null slot
/// fall under 'snack'.
export function groupByMealSlot<T extends MacroRow>(entries: T[]): MealSlotGroup<T>[] {
	const groups: MealSlotGroup<T>[] = [];
	for (const slot of MEAL_SLOTS) {
		const inSlot = entries.filter((e) => (e.meal_slot ?? 'snack') === slot);
		if (inSlot.length === 0) continue;
		groups.push({
			slot,
			label: MEAL_SLOT_LABELS[slot],
			entries: inSlot,
			calories: sumMacros(inSlot).calories,
		});
	}
	return groups;
}

/// Fraction of a target consumed, clamped to [0, 1] for ring rendering.
/// Returns null when there's no positive target (hide the comparison).
export function ringFraction(consumed: number, target: number | null | undefined): number | null {
	if (target == null || target <= 0) return null;
	return Math.max(0, Math.min(1, consumed / target));
}
