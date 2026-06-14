/// Pure pace-string formatting, split out from `units.svelte.ts` so it can
/// be unit-tested without the Svelte compiler (the unit-preference signal
/// lives in the `.svelte.ts` shell; this layer is rune-free).

/// Split a pace value (seconds per the display unit) into whole minutes +
/// seconds, rounding to the nearest second FIRST so the seconds field is
/// always 0–59.
///
/// Splitting before rounding — `Math.floor(x / 60)` for minutes but
/// `Math.round(x % 60)` for seconds — lets a fractional input produce a
/// seconds field of 60 (e.g. 299.6 → 4 min + 60 s), which renders as the
/// malformed "4:60" and, in a two-field editor, exceeds the `max="59"`
/// input bound. Rounding the total first keeps the rollover correct.
export function paceParts(secPerUnit: number): { minutes: number; seconds: number } {
	const total = Math.round(secPerUnit);
	return { minutes: Math.floor(total / 60), seconds: total % 60 };
}

/// Format a pace value (seconds per the display unit, already converted to
/// km or mi by the caller) as "m:ss". Mirrors `fmtPaceCell` in
/// training/plan_serialize.ts and the Dart `UnitFormat.pace` twin in
/// preferences.dart.
export function paceMinutesSeconds(secPerUnit: number): string {
	const { minutes, seconds } = paceParts(secPerUnit);
	return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
