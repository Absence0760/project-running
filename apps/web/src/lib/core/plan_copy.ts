/// The field sets the two plan publishers copy off a source plan onto the
/// template they insert. One definition, two callers.
///
/// `publishPlanToLibrary` (public library) and `publishPlanAsTemplate` (club)
/// each carried a hand-maintained copy of the same three lists, and the
/// library half had fallen four fields behind: every published workout lost
/// its `target_pace_end_sec_per_km` progression target and its `pace_zone`
/// label, and the head lost `source` and `rules`, so a cloner got a plan whose
/// zone chips were gone and whose adaptive re-plan had no rules to read.
/// Two lists that must agree is the bug; one list that both spread is the fix.
///
/// Pure and Supabase-free so `plan_copy.test.ts` can assert the shape against
/// the generated schema without a live stack.

import type { PlanWeek, PlanWorkout, TrainingPlan } from '../types';

/// Plan-design fields carried from the source plan onto the template head.
///
/// Deliberately absent: `vdot`, `current_5k_seconds` and `notes` are the
/// publisher's private fields (fitness proxies and their own free text) and
/// are stripped on publish — set to null by each caller and enforced by the
/// trigger in migration 20270508_001. `status`, `is_template`,
/// `is_public_template`, `club_id` and `parent_template_id` are what makes a
/// row a template at all, so each caller states them itself.
export function planHeadCopyFields(src: TrainingPlan): {
	name: string;
	goal_event: TrainingPlan['goal_event'];
	goal_distance_m: number;
	goal_time_seconds: number | null;
	start_date: string;
	end_date: string;
	days_per_week: number;
	source: string;
	rules: TrainingPlan['rules'];
} {
	return {
		name: src.name,
		goal_event: src.goal_event,
		goal_distance_m: src.goal_distance_m,
		goal_time_seconds: src.goal_time_seconds,
		start_date: src.start_date,
		end_date: src.end_date,
		days_per_week: src.days_per_week,
		source: src.source ?? 'manual',
		rules: src.rules,
	};
}

export function planWeekCopyRows(
	weeks: PlanWeek[],
	planId: string,
): {
	plan_id: string;
	week_index: number;
	phase: PlanWeek['phase'];
	target_volume_m: number | null;
	notes: string | null;
}[] {
	return weeks.map((w) => ({
		plan_id: planId,
		week_index: w.week_index,
		phase: w.phase,
		target_volume_m: w.target_volume_m,
		notes: w.notes,
	}));
}

/// Copy every workout whose week made it into the new plan. A workout whose
/// week has no mapping is dropped rather than orphaned — `week_id` is a
/// NOT NULL FK, so there is nothing honest to write.
///
/// Completion state (`completed_at`, `completed_run_id`, `manually_completed`,
/// `skipped_at`) is deliberately not copied: a template starts fresh.
export function planWorkoutCopyRows(
	workouts: PlanWorkout[],
	newWeekIdByOldId: Map<string, string>,
): {
	week_id: string;
	scheduled_date: string;
	kind: PlanWorkout['kind'];
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
	target_pace_end_sec_per_km: number | null;
	target_pace_tolerance_sec: number | null;
	pace_zone: string | null;
	structure: PlanWorkout['structure'];
	notes: string | null;
}[] {
	const rows = [];
	for (const w of workouts) {
		const weekId = newWeekIdByOldId.get(w.week_id);
		if (!weekId) continue;
		rows.push({
			week_id: weekId,
			scheduled_date: w.scheduled_date,
			kind: w.kind,
			target_distance_m: w.target_distance_m,
			target_duration_seconds: w.target_duration_seconds,
			target_pace_sec_per_km: w.target_pace_sec_per_km,
			target_pace_end_sec_per_km: w.target_pace_end_sec_per_km,
			target_pace_tolerance_sec: w.target_pace_tolerance_sec,
			pace_zone: w.pace_zone,
			structure: w.structure,
			notes: w.notes,
		});
	}
	return rows;
}
