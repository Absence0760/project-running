/**
 * Pure helpers behind the per-meal detail route (`/nutrition/[date]/[slot]`).
 * Kept rune-free so they're node:test-runnable; the `.svelte` page is the only
 * caller. Web-only (no Dart twin — the mobile detail screen reimplements the
 * same shaping against its local store).
 */

import type { MealSlot } from './nutrition_totals';

export interface MealDetailRow {
	started_at: string;
	meal_slot: MealSlot | null;
	calories: number | null;
}

/// Local YYYY-MM-DD key for an ISO timestamp. A null meal_slot folds into
/// `snack` (the same default the day view uses).
export function dayKey(iso: string): string {
	return new Date(iso).toISOString().slice(0, 10);
}

/// Entries from `rows` that fall on local calendar day `date` AND belong to
/// `slot` (null slot → snack).
export function entriesForSlotOnDay<T extends MealDetailRow>(
	rows: T[],
	date: string,
	slot: MealSlot,
): T[] {
	const start = new Date(`${date}T00:00:00`);
	const end = new Date(start);
	end.setDate(end.getDate() + 1);
	return rows.filter((e) => {
		const t = new Date(e.started_at);
		if (t < start || t >= end) return false;
		return (e.meal_slot ?? 'snack') === slot;
	});
}

/// The trailing 7-day calorie trend for `slot`, ending (inclusive) on `date`.
/// Always returns exactly 7 buckets in chronological order, zero-filled for
/// days with nothing logged, so the bar chart's x-axis is stable.
export function slotCalorieTrend(
	rows: MealDetailRow[],
	date: string,
	slot: MealSlot,
	days = 7,
): { date: string; calories: number }[] {
	const anchor = new Date(`${date}T00:00:00`);
	const byDay = new Map<string, number>();
	for (let i = days - 1; i >= 0; i--) {
		const d = new Date(anchor);
		d.setDate(d.getDate() - i);
		byDay.set(localDateKey(d), 0);
	}
	for (const e of rows) {
		if ((e.meal_slot ?? 'snack') !== slot) continue;
		const key = localDateKey(new Date(e.started_at));
		if (byDay.has(key)) byDay.set(key, (byDay.get(key) ?? 0) + (e.calories ?? 0));
	}
	return [...byDay.entries()].map(([d, calories]) => ({ date: d, calories }));
}

/// Zero-padded local YYYY-MM-DD (not UTC) for a Date.
export function localDateKey(d: Date): string {
	const mm = String(d.getMonth() + 1).padStart(2, '0');
	const dd = String(d.getDate()).padStart(2, '0');
	return `${d.getFullYear()}-${mm}-${dd}`;
}
