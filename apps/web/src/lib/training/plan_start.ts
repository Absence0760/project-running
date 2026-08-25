// The plan wizard's start-date alignment. The plan generator (training.ts)
// hard-anchors day 0 of the start week to the Sunday long run — every day
// role is an OFFSET from the start date, not a real weekday — so a plan's
// start date must be a Sunday or every day-role shifts.
//
// Its own pair rather than part of training.ts ↔ training.dart: this is
// wizard-input ergonomics, not generator algorithm. Dart twin
// `apps/mobile_android/lib/plan_start.dart` takes a `DateTime` where this
// side takes the ISO string an `<input type="date">` yields; that input type
// is the only difference.

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
