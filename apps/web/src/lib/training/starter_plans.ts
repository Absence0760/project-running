/**
 * Built-in starter training plans (Training Phase-3). A starter is just a
 * preset set of `generatePlan` inputs — instantiating one produces a
 * `GeneratedPlan` that flows through the same `createTrainingPlan` path the
 * wizard already uses (no RPC, no schema, no DB template row). Distinct from
 * club templates, which are DB-owned rows cloned via `clone_plan_template`.
 *
 * Mirrors `apps/mobile_android/lib/starter_plans.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import {
	generatePlan,
	walkRunDefaultWeeks,
	type GeneratedPlan,
	type GoalEvent
} from './training';

export interface StarterPlan {
	/// Stable id; also the i18n key suffix (`plansNew.starter.<id>.name` / `.hint`).
	id: string;
	goalEvent: GoalEvent;
	weeks: number;
	daysPerWeek: number;
	/// C25K-style walk-run beginner plan.
	beginnerWalkRun?: boolean;
}

/// The catalogue. Order is the display order on the picker.
export const STARTER_PLANS: readonly StarterPlan[] = [
	// C25K: weeks MUST be walkRunDefaultWeeks() or the graduation week truncates
	// (training.md § C25K). beginnerWalkRun routes generatePlan to the walk-run shape.
	{ id: 'c25k', goalEvent: 'distance_5k', weeks: walkRunDefaultWeeks(), daysPerWeek: 3, beginnerWalkRun: true },
	{ id: 'half_12wk', goalEvent: 'distance_half', weeks: 12, daysPerWeek: 4 },
	{ id: 'marathon_16wk', goalEvent: 'distance_full', weeks: 16, daysPerWeek: 5 }
];

export function starterById(id: string): StarterPlan | undefined {
	return STARTER_PLANS.find((s) => s.id === id);
}

/// Instantiate a starter into a `GeneratedPlan` anchored at `startDate`,
/// delegating entirely to `generatePlan`. Returns null for an unknown id.
/// No goal time / recent-5k is supplied, so paces come back as the conservative
/// fallback (`pacesAreFallback`) — the caller discloses that, same as the wizard.
export function instantiateStarter(
	id: string,
	startDate: string,
	age?: number | null
): GeneratedPlan | null {
	const starter = starterById(id);
	if (!starter) return null;
	return generatePlan({
		goalEvent: starter.goalEvent,
		startDate,
		daysPerWeek: starter.daysPerWeek,
		weeks: starter.weeks,
		beginnerWalkRun: starter.beginnerWalkRun,
		age: age ?? null
	});
}
