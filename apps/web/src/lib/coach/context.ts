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

	const { data: rawRecentRuns } = await supabase
		.from('runs')
		.select('id, started_at, distance_m, duration_s, metadata, route_id')
		.order('started_at', { ascending: false })
		.limit(runsLimit);
	// Persona-hunt Round 2 finding Pro #3. `metadata` is a free-form
	// jsonb bag (docs/backend/metadata.md). Some keys are useful coaching
	// signal (activity_type, avg_bpm, workout_kind, etc.); many are
	// not — `notes` (free-form, anything the runner typed), `event`
	// + `position` (parkrun athlete + finishing place), raw `laps[]`
	// arrays, `imported_from`, `strava_id` / `garmin_id`, internal
	// flags like `recovered_from_crash`, owner-only data the
	// `public_runs` view explicitly strips. Selecting metadata whole
	// shipped all of it to Anthropic — defence-in-depth violation
	// against the same Art 5(1)(c) minimisation the surrounding code
	// (subscription_tier strip, health-consent gate) defends elsewhere.
	//
	// Allowlist the keys the coach actually uses for advice. Pre-fix
	// behaviour for unallowlisted keys: included. Post-fix: dropped.
	const recentRuns = (rawRecentRuns ?? []).map((r) => ({
		...r,
		metadata: pickAllowedRunMetadata(r.metadata as Record<string, unknown> | null),
	}));

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

/// Keys on `runs.metadata` that the coach is allowed to see. Adding a
/// key here is a deliberate decision — every key crosses a sub-
/// processor boundary and must justify its coaching value. Audited
/// against docs/backend/metadata.md.
const COACH_METADATA_ALLOWLIST: ReadonlySet<string> = new Set([
	'activity_type', // run / walk / hike / cycle — coach gates advice on this
	'avg_bpm', // gated on health consent at the row level; HR zones use this
	'workout_kind', // structured workouts — coach reads to track plan adherence
	'workout_step_results', // per-step planned-vs-actual; coach summarises adherence
	'manual_completion', // user marked a workout done — affects plan completion
	'is_indoor', // treadmill / track session — coach phrases advice differently
	'elevation_m', // total gain — useful for route-context advice
]);

export function pickAllowedRunMetadata(
	metadata: Record<string, unknown> | null,
): Record<string, unknown> | null {
	if (!metadata) return null;
	const out: Record<string, unknown> = {};
	for (const key of Object.keys(metadata)) {
		if (COACH_METADATA_ALLOWLIST.has(key)) {
			out[key] = metadata[key];
		}
	}
	// Return null when the allowlist would emit an empty object so
	// the JSON payload stays compact + omits the key entirely.
	return Object.keys(out).length === 0 ? null : out;
}
