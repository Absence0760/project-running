// Builds the JSON context block fed into the coach prompt: profile,
// runner prefs (HR zones, mileage goal, coach_personality), active
// (or pinned) plan + plan weeks + plan workouts, and the most recent
// runs. Pure function over a Supabase client — same code path in dev
// and prod.

import type { SupabaseClient } from '@supabase/supabase-js';
import { TABLES } from '../core/schema';
import { distinctExerciseCount } from '../gym/gym_prs';

export interface CoachContext {
	data?: unknown;
}

/// The slice of the `get_my_profile()` row the coach context reads. The
/// handler fetches this row for the consent gate and passes it in, so
/// the same SECURITY DEFINER RPC isn't issued twice per coach message.
export interface CoachProfileRow {
	display_name: string | null;
	preferred_unit: string | null;
	health_data_consent_at: string | null;
}

export async function buildContext(
	supabase: SupabaseClient,
	userId: string,
	planId: string | null,
	runsLimit: number,
	profileRow: CoachProfileRow | null,
): Promise<CoachContext> {
	// `profileRow` is the `get_my_profile()` result the handler already
	// fetched for the coach-consent gate — passed in rather than re-queried
	// so a duplicate SECURITY DEFINER RPC round-trip doesn't fire on every
	// coach message. The RPC is the self-read path because `subscription_tier`
	// is column-level revoked from authenticated callers (migration
	// 20260707_001). `subscription_tier` is intentionally dropped from the
	// profile projection emitted to Anthropic — the handler already knows
	// tier and adjusts limits server-side; sending billing-tier metadata to
	// a sub-processor violates Art 5(1)(c) data minimisation (audit/coach
	// May 2026 Medium #9).
	const profileRowTyped = profileRow;
	const profile = profileRowTyped
		? {
				display_name: profileRowTyped.display_name,
				preferred_unit: profileRowTyped.preferred_unit,
			}
		: null;

	// GDPR Art 9(2)(a): special-category health-adjacent data (DOB +
	// HR metrics, dietary intake) only flows to Anthropic when the user
	// has actively granted health-data consent via Settings → Preferences.
	// The `coach_consent_at` (Art 6(1)(a) AI consent) gate in handler.ts
	// authorises using the Coach AT ALL; this is the second, distinct gate
	// for the *health* category. See migration
	// `20260921_001_user_profiles_gdpr_consent_timestamps.sql` for the
	// two-gate design and audit/coach May 2026 High #1. Derived from the
	// passed-in profile row, so it's known before any query — the nutrition
	// lane below can join the parallel fan-out instead of waiting on a
	// profile fetch. This is the CALLER's consent; because every lane is now
	// scoped to `userId` (the caller), the data being gated is the caller's
	// own — the consent tenant and data tenant match by construction.
	const healthConsentGranted = profileRowTyped?.health_data_consent_at != null;

	// These five reads are mutually independent: the active plan (+ its
	// week→workout sub-chain), recent runs, recent lifts (+ their sets),
	// user settings, and the consent-gated 7-day nutrition rollup. They
	// used to run as five sequential awaits, so every coach message stacked
	// ~5 Supabase round-trips of latency before the first token streamed.
	// Fan them out with Promise.all so the endpoint pays ~one round-trip
	// instead (perf-hunt 2026-06-10). Each lane keeps its own internal
	// sequential sub-chain where one query genuinely feeds the next.
	const planLane = (async (): Promise<{
		plan: unknown;
		weeks: unknown[];
		workouts: unknown[];
	}> => {
		// Scope every data lane to the caller explicitly — do NOT lean on RLS
		// alone. Migrations 20261103_001 + 20261116_001 additively granted an
		// active coach read on their athletes' runs/plans, so an RLS-only read
		// from a coach's own /coach chat would UNION the athlete's rows into the
		// coach's context (and the no-plan_id branch could return the athlete's
		// active plan). The `.eq('user_id', userId)` keeps this the caller's own
		// data; plan_weeks/plan_workouts inherit the scope transitively through
		// the plan (they carry no user_id column).
		const { data: plan } = planId
			? await supabase
					.from('training_plans')
					.select('*')
					.eq('id', planId)
					.eq('user_id', userId)
					.maybeSingle()
			: await supabase
					.from('training_plans')
					.select('*')
					.eq('user_id', userId)
					.eq('status', 'active')
					.maybeSingle();
		let weeks: unknown[] = [];
		let workouts: unknown[] = [];
		if (plan && typeof plan === 'object' && 'id' in plan) {
			const planRow = plan as { id: string; start_date?: string | null };
			// Bound the plan window like recent_runs / recent_lifts so a long
			// plan (ultra base block, multi-year, or a REST-inserted row with
			// no row-count CHECK) can't re-serialise its entire week/workout
			// history into the prompt on every call. Bias to the weeks around
			// "now" — a short look-back plus the cap of upcoming weeks — so the
			// coach keeps the current + upcoming weeks it reasons about, not a
			// long plan's stale opening block.
			const startMs = planRow.start_date
				? new Date(planRow.start_date).getTime()
				: NaN;
			const currentWeek = Number.isFinite(startMs)
				? Math.max(0, Math.floor((Date.now() - startMs) / (7 * 86_400_000)))
				: 0;
			const fromWeek = Math.max(0, currentWeek - COACH_PLAN_WEEKS_LOOKBACK);
			const weekRes = await supabase
				.from('plan_weeks')
				.select('*')
				.eq('plan_id', planRow.id)
				.gte('week_index', fromWeek)
				.order('week_index', { ascending: true })
				.limit(COACH_PLAN_WEEKS_CAP);
			weeks = weekRes.data ?? [];
			if (weeks.length === 0) {
				// A fully-elapsed plan viewed explicitly (its last week is before
				// `fromWeek`): fall back to its final cap of weeks so the coach
				// still sees the taper/race, never an empty plan.
				const tailRes = await supabase
					.from('plan_weeks')
					.select('*')
					.eq('plan_id', planRow.id)
					.order('week_index', { ascending: false })
					.limit(COACH_PLAN_WEEKS_CAP);
				weeks = (tailRes.data ?? []).slice().reverse();
			}
			if (weeks.length > 0) {
				const ids = (weeks as { id: string }[]).map((w) => w.id);
				const wkRes = await supabase
					.from('plan_workouts')
					.select('*')
					.in('week_id', ids)
					.order('scheduled_date', { ascending: true })
					.limit(COACH_PLAN_WORKOUTS_CAP);
				workouts = wkRes.data ?? [];
			}
		}
		return { plan: plan ?? null, weeks, workouts };
	})();

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
	const runsLane = (async () => {
		const { data: rawRecentRuns } = await supabase
			.from(TABLES.runs)
			.select('id, started_at, distance_m, duration_s, metadata, route_id')
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			.limit(runsLimit);
		return (rawRecentRuns ?? []).map((r) => ({
			...r,
			metadata: pickAllowedRunMetadata(
				r.metadata as Record<string, unknown> | null,
				healthConsentGranted,
			),
		}));
	})();

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
	// gym_workouts / food_log are owner-only today, but scope them to the
	// caller explicitly anyway — the same not-rely-on-RLS-alone defence the
	// plan/runs lanes now apply, so a future additive coach-visibility grant
	// (as already happened to runs/plans) can't quietly leak an athlete's
	// lifts/nutrition into a coach's own context. gym_sets inherits the scope
	// transitively through the workout ids (no user_id column).
	const liftsLane = (async (): Promise<LiftSummary[]> => {
		const { data: liftWorkouts } = await supabase
			.from(TABLES.gym_workouts)
			.select('id, title, started_at')
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			.limit(COACH_LIFTS_CAP);
		if (!liftWorkouts || liftWorkouts.length === 0) return [];
		const ids = (liftWorkouts as { id: string }[]).map((w) => w.id);
		const { data: liftSets } = await supabase
			.from(TABLES.gym_sets)
			.select('workout_id, exercise_name, reps, weight_kg')
			.in('workout_id', ids);
		return summarizeRecentLifts(
			liftWorkouts as LiftWorkoutRow[],
			(liftSets ?? []) as LiftSetRow[],
		);
	})();

	const settingsLane = (async (): Promise<Record<string, unknown>> => {
		const { data: userSettings } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle();
		return (userSettings?.prefs ?? {}) as Record<string, unknown>;
	})();

	// Nutrition is health-adjacent (dietary intake), so it crosses the
	// same Art 9(2)(a) special-category boundary as DOB / HR and is
	// gated on the SAME health-data consent. Lifts (working-set tonnage)
	// are activity data like runs — ungated, sent whenever logged. A 200-
	// row cap over a 7-day window is plenty to compute daily averages and
	// bounds the worst case (a power-logger).
	const nutritionLane = (async (): Promise<NutritionSummary | null> => {
		if (healthConsentGranted) {
			const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
			const { data: foodRows } = await supabase
				.from(TABLES.food_log)
				.select('started_at, calories, protein_g, carbs_g, fat_g')
				.eq('user_id', userId)
				.gte('started_at', sevenDaysAgo)
				.order('started_at', { ascending: false })
				.limit(200);
			return summarizeNutrition((foodRows ?? []) as FoodLogRow[], new Date());
		}
		return null;
	})();

	const [{ plan, weeks, workouts }, recentRuns, recentLifts, prefs, nutrition7d] =
		await Promise.all([planLane, runsLane, liftsLane, settingsLane, nutritionLane]);

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
			profile: profile ?? null,
			runner_context: runnerContext,
			plan: plan ?? null,
			plan_weeks: weeks,
			plan_workouts: workouts,
			recent_runs: recentRuns ?? [],
			recent_lifts: recentLifts,
			nutrition_7d: nutrition7d,
			// LAST, not first: this is the only ever-changing field, and the
			// serialized context is sent as an Anthropic ephemeral-cache block
			// (providers.ts) that only hits on a byte-identical prefix. Leading
			// with the timestamp busts the cache on every message; trailing it
			// keeps the whole prefix stable across a conversation. Issue #390.
			now_iso: new Date().toISOString(),
		},
	};
}

/// Fixed cap on lift sessions sent to the coach. Bounded so the prompt
/// size + per-call cost stay roughly flat as gym history grows — the
/// coach reasons about recent training, not a lifetime log.
export const COACH_LIFTS_CAP = 8;

/// Fixed caps on the plan window sent to the coach. Bounded — like
/// recent_runs / recent_lifts — so a long or REST-inserted plan can't
/// grow the prompt without limit. `WEEKS_CAP` covers a full marathon
/// block; `WORKOUTS_CAP` is WEEKS_CAP × the 7-day max. `WEEKS_LOOKBACK`
/// keeps a couple of recently-completed weeks for adherence context
/// while the cap fills with the current + upcoming weeks.
export const COACH_PLAN_WEEKS_CAP = 20;
export const COACH_PLAN_WORKOUTS_CAP = 140;
export const COACH_PLAN_WEEKS_LOOKBACK = 2;

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
	/// Distinct exercises in the session, counted on the canonical grouping
	/// key so a lift logged under two spellings is one exercise here as it is
	/// everywhere else in the app.
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
		let volume = 0;
		for (const s of mine) {
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
			// Counted on the canonical grouping key, not the runtime's own
			// fold: the model is being told how many exercises the session
			// held, and every keyed surface in the app answers that with
			// `normaliseExerciseName` (§ 1274).
			exercises: distinctExerciseCount(mine.map((s) => s.exercise_name)),
			sets: mine.length,
			volume_kg: Math.round(volume),
		};
	});
}

interface FoodLogRow {
	started_at: string;
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
		const t = new Date(r.started_at).getTime();
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
		days.add(r.started_at.slice(0, 10));
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
	'avg_bpm', // Art 9 heart-rate — stripped unless health consent granted (COACH_HEALTH_METADATA_KEYS); HR zones use it
	'workout_kind', // structured workouts — coach reads to track plan adherence
	'workout_step_results', // per-step planned-vs-actual; coach summarises adherence
	'manual_completion', // user marked a workout done — affects plan completion
	'is_indoor', // treadmill / track session — coach phrases advice differently
	'elevation_m', // total gain — useful for route-context advice
]);

/// Allowlisted keys that are Art 9(2)(a) special-category health data.
/// Stripped from the coach payload unless the runner granted health-data
/// consent — the same gate `runner_context` applies to DOB / HR zones,
/// now enforced at the per-run metadata layer too.
const COACH_HEALTH_METADATA_KEYS: ReadonlySet<string> = new Set(['avg_bpm']);

export function pickAllowedRunMetadata(
	metadata: Record<string, unknown> | null,
	healthConsentGranted: boolean,
): Record<string, unknown> | null {
	if (!metadata) return null;
	const out: Record<string, unknown> = {};
	for (const key of Object.keys(metadata)) {
		if (!COACH_METADATA_ALLOWLIST.has(key)) continue;
		if (!healthConsentGranted && COACH_HEALTH_METADATA_KEYS.has(key)) continue;
		out[key] = metadata[key];
	}
	// Return null when the allowlist would emit an empty object so
	// the JSON payload stays compact + omits the key entirely.
	return Object.keys(out).length === 0 ? null : out;
}
