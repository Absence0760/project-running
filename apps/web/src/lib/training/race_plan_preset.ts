/**
 * Derive a training-plan preset from a race on the calendar, so "train for
 * this race" lands on a plan whose final race week contains race day.
 *
 * Pure logic, no Supabase / auth.
 *
 * Dart twin: apps/mobile_android/lib/race_plan_preset.dart (parity pair — keep
 * the arithmetic, tolerances, refusals, and test counts in lockstep). The
 * surfaces are `RaceCalendarCard` → `/plans/new` here and the races screen's
 * "train for this race" action → `PlanNewScreen` there.
 *
 * Two constraints drive every number here:
 *
 *  - `generatePlan` hard-anchors day 0 of the start week to the Sunday long
 *    run (see `plan_start.ts`), so a derived start date must be a Sunday or
 *    every day-role shifts.
 *  - The generated plan's last week is the `race` week, spanning
 *    `[start + (weeks-1)*7, start + weeks*7 - 1]`. Anchoring that week's
 *    Sunday to the Sunday on or before race day puts race day inside it for
 *    any weekday the race falls on.
 *
 * Dates are compared as whole UTC epoch-days rather than by millisecond
 * difference: a span crossing a DST transition is 167 or 169 hours, which
 * truncates a day short and would shift the anchor by a week.
 */

import { GOAL_DISTANCES_M, defaultPlanWeeks, type GoalEvent } from './training';

/// Shortest plan the preset will propose. Mirrors the wizard's own
/// `min="4"` week input — a shorter build isn't a plan, it's a taper.
export const RACE_PLAN_MIN_WEEKS = 4;

/// How far a race's advertised distance may sit from a standard rung and
/// still be treated as that event. Courses are certified to the metre but
/// listings round ("21.1 km"), so an exact match is too strict.
export const RACE_PLAN_DISTANCE_TOLERANCE = 0.02;

export type RacePlanRefusal =
	/// Race day has been and gone (or is today) — nothing left to train for.
	| 'past'
	/// Fewer than RACE_PLAN_MIN_WEEKS whole weeks remain before race week.
	| 'too_soon'
	/// The race date isn't a usable `yyyy-mm-dd`.
	| 'invalid';

export interface RacePlanPreset {
	/// The standard event the race distance matches, or null when it matches
	/// none. The wizard has no custom-distance input, so claiming the nearest
	/// rung for (say) a 50k would silently train the runner for a marathon;
	/// null leaves the goal on the wizard's own default and still presets the
	/// dates, which is the half of the answer we can stand behind.
	goalEvent: GoalEvent | null;
	/// Total plan weeks, >= RACE_PLAN_MIN_WEEKS.
	weeks: number;
	/// ISO `yyyy-mm-dd`, always a Sunday, never before today.
	startDate: string;
}

export type RacePlanPresetResult =
	| { ok: true; preset: RacePlanPreset }
	| { ok: false; reason: RacePlanRefusal };

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/// Whole days since the epoch for an ISO date, or null when unparseable.
/// UTC-based so the count is immune to DST and to the caller's offset; both
/// inputs go through the same function, so only their difference matters.
function epochDay(iso: string): number | null {
	if (!ISO_DATE.test(iso)) return null;
	const [y, m, d] = iso.split('-').map(Number);
	const ms = Date.UTC(y, m - 1, d);
	// Round-trip guards an out-of-range component ("2026-02-31" rolls over).
	const back = new Date(ms);
	if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) {
		return null;
	}
	return Math.floor(ms / 86_400_000);
}

function isoFromEpochDay(day: number): string {
	const d = new Date(day * 86_400_000);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/// Day of week for an epoch day, 0 = Sunday. Epoch day 0 (1970-01-01) was a
/// Thursday, hence the +4.
function dayOfWeek(day: number): number {
	return (((day + 4) % 7) + 7) % 7;
}

/// The standard goal event a race distance represents, or null when it sits
/// outside RACE_PLAN_DISTANCE_TOLERANCE of every rung.
export function goalEventForDistance(distanceM: number | null | undefined): GoalEvent | null {
	const d = Number(distanceM);
	if (!Number.isFinite(d) || d <= 0) return null;
	for (const [event, rung] of Object.entries(GOAL_DISTANCES_M) as [
		Exclude<GoalEvent, 'custom'>,
		number,
	][]) {
		if (Math.abs(d - rung) / rung <= RACE_PLAN_DISTANCE_TOLERANCE) return event;
	}
	return null;
}

/**
 * Propose the plan shape that peaks on a race.
 *
 * `weeks` is capped at the goal's own default rather than filling every week
 * between now and race day: a marathon 30 weeks out wants the standard
 * 16-week build starting in 14 weeks, not a 30-week grind.
 */
export function racePlanPreset(input: {
	raceDateIso: string;
	distanceM?: number | null;
	todayIso: string;
}): RacePlanPresetResult {
	const raceDay = epochDay(input.raceDateIso);
	const today = epochDay(input.todayIso);
	if (raceDay === null || today === null) return { ok: false, reason: 'invalid' };
	if (raceDay <= today) return { ok: false, reason: 'past' };

	const goalEvent = goalEventForDistance(input.distanceM);

	// The race week is the calendar week (Sunday-based) race day falls in.
	const raceWeekStart = raceDay - dayOfWeek(raceDay);
	// Earliest legal start: the Sunday on or after today. Starting today is
	// fine — the wizard only rejects a start date strictly in the past.
	const firstStart = today + ((7 - dayOfWeek(today)) % 7);

	const available = (raceWeekStart - firstStart) / 7 + 1;
	if (available < RACE_PLAN_MIN_WEEKS) return { ok: false, reason: 'too_soon' };

	const weeks = Math.min(available, defaultPlanWeeks(goalEvent ?? 'custom'));
	return {
		ok: true,
		preset: {
			goalEvent,
			weeks,
			startDate: isoFromEpochDay(raceWeekStart - (weeks - 1) * 7),
		},
	};
}
