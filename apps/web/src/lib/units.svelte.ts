/// Unit preference + distance/pace formatters.
///
/// `preferredUnit` is a module-level reactive signal — any Svelte view
/// that calls `formatDistance` or `formatPace` re-renders automatically
/// when the user flips the setting on `/settings/preferences`. The auth
/// store calls `setUnit(...)` once after the profile loads so all views
/// pick up the saved preference without plumbing it through every call.
///
/// The unit label is appended by the formatters themselves so templates
/// never hardcode "km" / "mi" — one of the biggest sources of stale
/// labels when we first wired the preference in.

import type { PreferredUnit } from './types';

const METRES_PER_MILE = 1609.344;

// `$state.raw` so non-Svelte callers (pure functions, SSR) can still
// read the value; rune-aware callers still get reactivity.
const unit = $state<{ value: PreferredUnit }>({ value: 'km' });

export function getUnit(): PreferredUnit {
	return unit.value;
}

export function setUnit(u: PreferredUnit | null | undefined): void {
	unit.value = u === 'mi' ? 'mi' : 'km';
}

/// Distance label: km for metric, mi for imperial. Sub-kilometre
/// metric distances render in metres; sub-mile imperial distances
/// render in yards for parity with how runners read race distances.
export function formatDistance(metres: number): string {
	if (unit.value === 'mi') {
		const miles = metres / METRES_PER_MILE;
		if (miles >= 1) return `${miles.toFixed(2)} mi`;
		const yards = Math.round(metres * 1.09361);
		return `${yards} yd`;
	}
	if (metres >= 1000) return `${(metres / 1000).toFixed(2)} km`;
	return `${Math.round(metres)} m`;
}

/// Pace label: "m:ss" with the appropriate per-unit suffix baked in
/// ("/km" or "/mi") so templates don't have to append it separately.
export function formatPace(seconds: number, metres: number): string {
	if (metres === 0) return '--:--';
	const perKm = seconds / (metres / 1000);
	const perUnit = unit.value === 'mi' ? perKm * (METRES_PER_MILE / 1000) : perKm;
	const m = Math.floor(perUnit / 60);
	const s = Math.round(perUnit % 60);
	const mm = String(m);
	const ss = String(s).padStart(2, '0');
	return `${mm}:${ss} /${unit.value}`;
}

/// Variant for callers that want just the pace digits without a suffix
/// (sparklines, axis ticks). Renders the same per-unit value.
export function formatPaceNoSuffix(seconds: number, metres: number): string {
	if (metres === 0) return '--:--';
	const perKm = seconds / (metres / 1000);
	const perUnit = unit.value === 'mi' ? perKm * (METRES_PER_MILE / 1000) : perKm;
	const m = Math.floor(perUnit / 60);
	const s = Math.round(perUnit % 60);
	return `${m}:${String(s).padStart(2, '0')}`;
}

/// Convert a metre count into the user's preferred display unit
/// (for custom rendering — charts, goal fills, etc). Returns a
/// `{ value, unit }` tuple so callers can format how they like.
export function distanceInPreferred(metres: number): { value: number; unit: 'km' | 'mi' } {
	if (unit.value === 'mi') return { value: metres / METRES_PER_MILE, unit: 'mi' };
	return { value: metres / 1000, unit: 'km' };
}

/// Compact distance — `XX.X km` / `XX.X mi`. Used by training plan
/// surfaces (week grid, calendar, today card) where we want a fixed
/// digit count rather than the more flexible `formatDistance`.
export function fmtKm(metres: number | null | undefined, digits = 1): string {
	if (metres == null) return '—';
	if (unit.value === 'mi') return `${(metres / METRES_PER_MILE).toFixed(digits)} mi`;
	return `${(metres / 1000).toFixed(digits)} km`;
}

/// Plan-surface pace formatter. Input is always seconds-per-km (the
/// canonical unit stored on `plan_workouts`); we convert to /mi when
/// the user prefers miles.
export function fmtPace(secPerKm: number | null | undefined): string {
	if (!secPerKm) return '—';
	const sec = unit.value === 'mi' ? secPerKm * (METRES_PER_MILE / 1000) : secPerKm;
	const m = Math.floor(sec / 60);
	const s = Math.round(sec % 60);
	return `${m}:${String(s).padStart(2, '0')}/${unit.value}`;
}
