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

import type { PreferredUnit } from '../types';
import { currentLocale } from '../i18n/store.svelte';
import { formatDecimal, formatInteger } from './number';

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
	const loc = currentLocale();
	if (unit.value === 'mi') {
		const miles = metres / METRES_PER_MILE;
		if (miles >= 1) return `${formatDecimal(miles, 2, loc)} mi`;
		const yards = Math.round(metres * 1.09361);
		return `${formatInteger(yards, loc)} yd`;
	}
	if (metres >= 1000) return `${formatDecimal(metres / 1000, 2, loc)} km`;
	return `${formatInteger(Math.round(metres), loc)} m`;
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

/// Average speed label paired with the user's preferred-unit suffix
/// ("km/h" or "mph"). Companion to `formatPace` — same underlying
/// data, different orientation. Some runners think in pace, some in
/// speed; surfacing both makes the key-stats grid serve everyone +
/// guarantees the cell is non-empty (no metadata or settings
/// required beyond what every run already carries).
export function formatSpeed(seconds: number, metres: number): string {
	if (seconds === 0 || metres === 0) return '--';
	const loc = currentLocale();
	const mPerSec = metres / seconds;
	if (unit.value === 'mi') {
		const mph = mPerSec * 2.23694;
		return `${formatDecimal(mph, 1, loc)} mph`;
	}
	const kmh = mPerSec * 3.6;
	return `${formatDecimal(kmh, 1, loc)} km/h`;
}

/// Compact distance — `XX.X km` / `XX.X mi`. Used by training plan
/// surfaces (week grid, calendar, today card) where we want a fixed
/// digit count rather than the more flexible `formatDistance`.
export function fmtKm(metres: number | null | undefined, digits = 1): string {
	if (metres == null) return '—';
	const loc = currentLocale();
	if (unit.value === 'mi') return `${formatDecimal(metres / METRES_PER_MILE, digits, loc)} mi`;
	return `${formatDecimal(metres / 1000, digits, loc)} km`;
}

const FEET_PER_METRE = 3.28084;

/// Elevation gain label: `Xm` / `Xft` with the unit baked in. Used
/// for vert ("vertical metres climbed") stats on dashboards + run
/// lists. Persona-hunt Round 3 finding Ultra #4 — pro / ultra
/// runners track vert as a first-class metric and the dashboard
/// hid it. null / undefined → '—'. Rounds to integer because
/// sub-metre precision on cumulative gain is GPS-noise floor.
export function formatElevation(metres: number | null | undefined): string {
	if (metres == null) return '—';
	const loc = currentLocale();
	if (unit.value === 'mi') return `${formatInteger(Math.round(metres * FEET_PER_METRE), loc)} ft`;
	return `${formatInteger(Math.round(metres), loc)} m`;
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
