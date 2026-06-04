/// Pure kg <-> lbs conversion + display/parse helpers for the
/// `weight_unit` user preference (docs/backend/settings.md). Storage is
/// ALWAYS canonical kilograms (`gym_sets.weight_kg`, future `body_metrics`)
/// — these only change how a weight is shown and how a typed value is
/// interpreted, the same display-only split as `preferred_unit` km/mi.
///
/// Kept rune-free in a sibling of `units.svelte.ts` so it is unit-testable
/// with `npx tsx --test` and mirrors the mobile Dart `Preferences` weight
/// helpers byte-for-byte in behaviour. Do not add reactive state here.

export type WeightUnit = 'kg' | 'lbs';

const LBS_PER_KG = 2.2046226218;

export function parseWeightUnit(raw: string | null | undefined): WeightUnit {
	return raw === 'lbs' ? 'lbs' : 'kg';
}

/// Canonical kg -> the user's chosen display unit. Pure number, no label.
export function kgToDisplay(kg: number, unit: WeightUnit): number {
	return unit === 'lbs' ? kg * LBS_PER_KG : kg;
}

/// A value the user typed in their chosen unit -> canonical kg for storage.
export function displayToKg(value: number, unit: WeightUnit): number {
	return unit === 'lbs' ? value / LBS_PER_KG : value;
}

/// Round a display weight to a sensible precision: whole/.5 increments read
/// fine for both kg plates and lbs, so one decimal place is plenty and
/// avoids float dust (60 kg -> 132.3 lbs, not 132.27735...).
export function roundWeight(value: number): number {
	return Math.round(value * 10) / 10;
}

/// Format a canonical kg value for display in the user's unit, with the
/// unit suffix baked in so templates never hardcode "kg". `null`/`NaN`
/// render as an em dash. A trailing `.0` is dropped so a clean 60 kg reads
/// "60 kg", not "60.0 kg".
export function formatWeightKg(
	kg: number | null | undefined,
	unit: WeightUnit,
): string {
	if (kg == null || !Number.isFinite(kg)) return '—';
	const shown = roundWeight(kgToDisplay(kg, unit));
	const text = Number.isInteger(shown) ? String(shown) : shown.toFixed(1);
	return `${text} ${unit}`;
}

/// Parse a free-text weight the user typed in their chosen unit into
/// canonical kg. Returns null on empty / non-numeric / negative input so
/// callers can reject the entry rather than store NaN. Accepts a comma
/// decimal separator (locale-tolerant for "60,5").
export function parseWeightToKg(
	raw: string | null | undefined,
	unit: WeightUnit,
): number | null {
	if (raw == null) return null;
	const trimmed = raw.trim().replace(',', '.');
	if (trimmed === '') return null;
	const value = Number(trimmed);
	if (!Number.isFinite(value) || value < 0) return null;
	return displayToKg(value, unit);
}
