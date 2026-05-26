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

	// Use the SECURITY DEFINER `get_my_profile` RPC because
	// `subscription_tier` is column-level revoked from authenticated callers
	// (see migration 20260707_001). `subscription_tier` is intentionally
	// dropped from the profile projection emitted to Anthropic — the
	// handler already knows tier and adjusts limits server-side; sending
	// billing-tier metadata to a sub-processor violates Art 5(1)(c) data
	// minimisation (audit/coach May 2026 Medium #9).
	const { data: profileRow } = await supabase.rpc('get_my_profile');
	const profileRowTyped = profileRow as
		| {
				display_name: string | null;
				preferred_unit: string | null;
				health_data_consent_at: string | null;
		  }
		| null;
	const profile = profileRowTyped
		? {
				display_name: profileRowTyped.display_name,
				preferred_unit: profileRowTyped.preferred_unit,
			}
		: null;

	const { data: userSettings } = await supabase
		.from('user_settings')
		.select('prefs')
		.eq('user_id', userId)
		.maybeSingle();
	const prefs = (userSettings?.prefs ?? {}) as Record<string, unknown>;

	// GDPR Art 9(2)(a): special-category health-adjacent data (DOB +
	// HR metrics) only flows to Anthropic when the user has actively
	// granted health-data consent via Settings → Preferences. The
	// `coach_consent_at` (Art 6(1)(a) AI consent) gate in handler.ts
	// authorises using the Coach AT ALL; this guard is the second,
	// distinct gate for the *health* category. See migration
	// `20260921_001_user_profiles_gdpr_consent_timestamps.sql` for
	// the two-gate design and audit/coach May 2026 High #1.
	const healthConsentGranted = profileRowTyped?.health_data_consent_at != null;
	const runnerContext = {
		// Non-health prefs are always safe to send.
		weekly_mileage_goal_m: prefs.weekly_mileage_goal_m ?? null,
		auto_pause_enabled: prefs.auto_pause_enabled ?? null,
		coach_personality: prefs.coach_personality ?? null,
		// Health-category fields — gated on Art 9 consent. When
		// consent has not been (or has been withdrawn from)
		// `health_data_consent_at`, these emit as null so the model
		// produces generic advice instead of HR-zone-specific advice.
		date_of_birth: healthConsentGranted ? (prefs.date_of_birth ?? null) : null,
		resting_hr_bpm: healthConsentGranted ? (prefs.resting_hr_bpm ?? null) : null,
		max_hr_bpm: healthConsentGranted ? (prefs.max_hr_bpm ?? null) : null,
		hr_zones: healthConsentGranted ? (prefs.hr_zones ?? null) : null,
	};

	return {
		data: {
			now_iso: new Date().toISOString(),
			profile: profile ?? null,
			runner_context: runnerContext,
			plan: plan ?? null,
			plan_weeks: weeks,
			plan_workouts: workouts,
			recent_runs: recentRuns ?? [],
		},
	};
}
