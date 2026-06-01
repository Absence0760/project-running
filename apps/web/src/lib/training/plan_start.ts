// Web-only helper for the plan wizard's start-date field. The plan
// generator (training.ts) hard-anchors day 0 of the start week to the
// Sunday long run, so a plan's start date must be a Sunday or every
// day-role shifts. Kept out of the training.ts ↔ training.dart parity
// pair because it's wizard-input ergonomics, not generator algorithm.

/// Snap an ISO `yyyy-mm-dd` date forward to the upcoming Sunday — a no-op
/// when it already is one. Parsed at local midnight so the weekday matches
/// what the user sees in their own timezone.
export function nextSundayIso(iso: string): string {
	const d = new Date(iso + 'T00:00:00');
	const off = (7 - d.getDay()) % 7;
	d.setDate(d.getDate() + off);
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

/// True when an ISO date falls on a Sunday (local time).
export function isSundayIso(iso: string): boolean {
	return new Date(iso + 'T00:00:00').getDay() === 0;
}
