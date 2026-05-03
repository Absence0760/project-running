// Builds the JSON context block fed into the coach prompt: profile,
// runner prefs (HR zones, mileage goal, coach_personality), active
// (or pinned) plan + plan weeks + plan workouts, and the most recent
// runs. Pure function over a Supabase client — same code path in dev
// and prod.

import type { SupabaseClient } from '@supabase/supabase-js';

export interface CoachContext {
	data?: unknown;
}

export async function buildContext(
	supabase: SupabaseClient,
	userId: string,
	planId: string | null,
	runsLimit: number,
): Promise<CoachContext> {
	const { data: plan } = planId
		? await supabase.from('training_plans').select('*').eq('id', planId).maybeSingle()
		: await supabase
				.from('training_plans')
				.select('*')
				.eq('status', 'active')
				.maybeSingle();

	let weeks: unknown[] = [];
	let workouts: unknown[] = [];
	if (plan && typeof plan === 'object' && 'id' in plan) {
		const weekRes = await supabase
			.from('plan_weeks')
			.select('*')
			.eq('plan_id', (plan as { id: string }).id)
			.order('week_index', { ascending: true });
		weeks = weekRes.data ?? [];
		if (weeks.length > 0) {
			const ids = (weeks as { id: string }[]).map((w) => w.id);
			const wkRes = await supabase
				.from('plan_workouts')
				.select('*')
				.in('week_id', ids)
				.order('scheduled_date', { ascending: true });
			workouts = wkRes.data ?? [];
		}
	}

	const { data: recentRuns } = await supabase
		.from('runs')
		.select('id, started_at, distance_m, duration_s, metadata, route_id')
		.order('started_at', { ascending: false })
		.limit(runsLimit);

	const { data: profile } = await supabase
		.from('user_profiles')
		.select('display_name, preferred_unit, subscription_tier')
		.eq('id', userId)
		.maybeSingle();

	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const prefs = (userSettings?.prefs ?? {}) as Record<string, unknown>;

	return {
		data: {
			now_iso: new Date().toISOString(),
			profile: profile ?? null,
			runner_context: {
				date_of_birth: prefs.date_of_birth ?? null,
				resting_hr_bpm: prefs.resting_hr_bpm ?? null,
				max_hr_bpm: prefs.max_hr_bpm ?? null,
				hr_zones: prefs.hr_zones ?? null,
				weekly_mileage_goal_m: prefs.weekly_mileage_goal_m ?? null,
				auto_pause_enabled: prefs.auto_pause_enabled ?? null,
				coach_personality: prefs.coach_personality ?? null,
			},
			plan: plan ?? null,
			plan_weeks: weeks,
			plan_workouts: workouts,
			recent_runs: recentRuns ?? [],
		},
	};
}
