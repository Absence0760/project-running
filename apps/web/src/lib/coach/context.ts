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

	// Tier-1 multi-modal coach context (docs/features/multi_modal.md §
	// "Cross-modality touches"). The coach SEES recent lift sessions +
	// a 7-day nutrition rollup and reasons about them — advisory, it
	// never auto-mutates a plan. Both are BOUNDED so prompt size + per-
	// call cost stay flat as history grows: a fixed cap of recent lift
	// sessions (summaries, not raw sets) and a 7-day rolling nutrition
	// summary (daily averages, not every food row). When the user logs
	// neither, both self-hide (empty array / null) and the JSON stays
	// the same size as today's running-only payload.
	//
	// RLS scopes both queries to the caller (gym_workouts / gym_sets /
	// food_log are owner-only), so no user_id filter is needed — the
	// forwarded JWT does the scoping, same as recent_runs above.
	const { data: liftWorkouts } = await supabase
		.from('gym_workouts')
		.select('id, title, started_at')
		.order('started_at', { ascending: false })
		.limit(COACH_LIFTS_CAP);
	let recentLifts: LiftSummary[] = [];
	if (liftWorkouts && liftWorkouts.length > 0) {
		const ids = (liftWorkouts as { id: string }[]).map((w) => w.id);
		const { data: liftSets } = await supabase
			.from('gym_sets')
			.select('workout_id, exercise_name, reps, weight_kg')
			.in('workout_id', ids);
		recentLifts = summarizeRecentLifts(
			liftWorkouts as LiftWorkoutRow[],
			(liftSets ?? []) as LiftSetRow[],
		);
	}
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

	// Nutrition is health-adjacent (dietary intake), so it crosses the
	// same Art 9(2)(a) special-category boundary as DOB / HR and is
	// gated on the SAME health-data consent. Lifts (working-set tonnage)
	// are activity data like runs — ungated, sent whenever logged. A 200-
	// row cap over a 7-day window is plenty to compute daily averages and
	// bounds the worst case (a power-logger).
	let nutrition7d: NutritionSummary | null = null;
	if (healthConsentGranted) {
		const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
		const { data: foodRows } = await supabase
			.from('food_log')
			.select('logged_at, calories, protein_g, carbs_g, fat_g')
			.gte('logged_at', sevenDaysAgo)
			.order('logged_at', { ascending: false })
			.limit(200);
		nutrition7d = summarizeNutrition((foodRows ?? []) as FoodLogRow[], new Date());
	}

	return {
		data: {
			now_iso: new Date().toISOString(),
			profile: profile ?? null,
			runner_context: runnerContext,
			plan: plan ?? null,
			plan_weeks: weeks,
			plan_workouts: workouts,
			recent_runs: recentRuns ?? [],
			recent_lifts: recentLifts,
			nutrition_7d: nutrition7d,
		},
	};
}

/// Fixed cap on lift sessions sent to the coach. Bounded so the prompt
/// size + per-call cost stay roughly flat as gym history grows — the
/// coach reasons about recent training, not a lifetime log.
export const COACH_LIFTS_CAP = 8;

interface LiftWorkoutRow {
	id: string;
	title: string | null;
	started_at: string;
}

interface LiftSetRow {
	workout_id: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
}

export interface LiftSummary {
	/// Local-ish calendar date (YYYY-MM-DD) of the session.
	date: string;
	title: string | null;
	/// Distinct exercise names in the session.
	exercises: number;
	/// Total logged sets.
	sets: number;
	/// Σ(reps · weight_kg) across the session, rounded. Bodyweight-only
	/// sets (no weight) contribute 0, matching the lift-load model.
	volume_kg: number;
}

export interface NutritionSummary {
	/// Distinct days with at least one logged item in the window.
	days_logged: number;
	/// Daily averages over the days logged (total ÷ days_logged), rounded.
	/// Null when no row in the window carried that macro.
	avg_calories: number | null;
	avg_protein_g: number | null;
	avg_carbs_g: number | null;
	avg_fat_g: number | null;
}

/// Collapse recent gym workouts + their sets into bounded per-session
/// summaries (no raw set rows cross the sub-processor boundary). Pure +
/// unit-tested. Workouts arrive newest-first; we keep the first `cap`.
export function summarizeRecentLifts(
	workouts: LiftWorkoutRow[],
	sets: LiftSetRow[],
	cap: number = COACH_LIFTS_CAP,
): LiftSummary[] {
	const byWorkout = new Map<string, LiftSetRow[]>();
	for (const s of sets) {
		const arr = byWorkout.get(s.workout_id) ?? [];
		arr.push(s);
		byWorkout.set(s.workout_id, arr);
	}
	return workouts.slice(0, cap).map((w) => {
		const mine = byWorkout.get(w.id) ?? [];
		const names = new Set<string>();
		let volume = 0;
		for (const s of mine) {
			const name = s.exercise_name?.trim().toLowerCase();
			if (name) names.add(name);
			if (
				s.reps != null &&
				s.weight_kg != null &&
				s.reps > 0 &&
				s.weight_kg > 0
			) {
				volume += s.reps * s.weight_kg;
			}
		}
		return {
			date: w.started_at.slice(0, 10),
			title: w.title,
			exercises: names.size,
			sets: mine.length,
			volume_kg: Math.round(volume),
		};
	});
}

interface FoodLogRow {
	logged_at: string;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
}

/// Roll a window of food-log rows into 7-day daily averages. Pure +
/// unit-tested. Returns null when nothing falls in the trailing 7-day
/// window so the key is omitted (self-hiding). Averages divide the
/// macro total by the number of DAYS LOGGED (not row count), so the
/// figure reads as "on a day you log, you average X".
export function summarizeNutrition(
	rows: FoodLogRow[],
	now: Date,
): NutritionSummary | null {
	const cutoff = now.getTime() - 7 * 86_400_000;
	const recent = rows.filter((r) => {
		const t = new Date(r.logged_at).getTime();
		return Number.isFinite(t) && t >= cutoff;
	});
	if (recent.length === 0) return null;
	const days = new Set<string>();
	let cal = 0;
	let calN = 0;
	let pro = 0;
	let proN = 0;
	let carb = 0;
	let carbN = 0;
	let fat = 0;
	let fatN = 0;
	for (const r of recent) {
		days.add(r.logged_at.slice(0, 10));
		if (r.calories != null) {
			cal += r.calories;
			calN++;
		}
		if (r.protein_g != null) {
			pro += r.protein_g;
			proN++;
		}
		if (r.carbs_g != null) {
			carb += r.carbs_g;
			carbN++;
		}
		if (r.fat_g != null) {
			fat += r.fat_g;
			fatN++;
		}
	}
	const dayCount = days.size;
	const avg = (total: number, present: number): number | null =>
		present > 0 && dayCount > 0 ? Math.round(total / dayCount) : null;
	return {
		days_logged: dayCount,
		avg_calories: avg(cal, calN),
		avg_protein_g: avg(pro, proN),
		avg_carbs_g: avg(carb, carbN),
		avg_fat_g: avg(fat, fatN),
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
