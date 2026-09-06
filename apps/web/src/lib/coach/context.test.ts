// Source-grep guards on context.ts. Run with
// `npx tsx --test apps/web/src/lib/coach/context.test.ts`.
//
// `buildContext` makes 5 Supabase RPC + table queries and can't be
// usefully unit-tested without spinning up a stack. Instead, pin the
// load-bearing audit-compliance invariants in the source so a future
// refactor that silently drops one fails CI rather than slipping
// through to production.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	buildContext,
	summarizeRecentLifts,
	summarizeNutrition,
	COACH_LIFTS_CAP,
	COACH_PLAN_WEEKS_CAP,
	COACH_PLAN_WORKOUTS_CAP,
} from './context';
import type { CoachProfileRow } from './context';

const SRC = readFileSync(
	resolve(import.meta.dirname ?? '.', 'context.ts'),
	'utf8',
);

test('subscription_tier is NOT projected into the Anthropic context', () => {
	// audit/coach May 2026 Medium #9 — Art 5(1)(c) data minimisation.
	// The handler knows tier and adjusts limits server-side; sending
	// billing-tier metadata to a sub-processor has no functional
	// purpose. The profile projection must include display_name +
	// preferred_unit only (plus internal consent flags read off the
	// row but not emitted).
	const profileObj = SRC.match(/const profile = profileRowTyped[\s\S]*?\{([\s\S]*?)\}[\s\S]*?:\s*null;/);
	assert.ok(
		profileObj,
		'context.ts must expose a `profile` projection object',
	);
	assert.equal(
		profileObj![1].includes('subscription_tier'),
		false,
		'subscription_tier MUST NOT appear in the Anthropic-bound profile projection',
	);
});

test('buildContext reuses the handler-fetched profile row (no duplicate get_my_profile)', () => {
	// perf-hunt (coach request path): the handler already calls
	// get_my_profile() for the coach-consent gate. buildContext used to
	// call the SAME SECURITY DEFINER RPC a second time, a redundant
	// round-trip on every coach message. The row is now threaded in as a
	// parameter — pin both halves so a refactor can't reintroduce the
	// duplicate.
	assert.equal(
		/rpc\(\s*['"]get_my_profile['"]/.test(SRC),
		false,
		'context.ts must NOT call get_my_profile — the handler passes the row in',
	);
	assert.match(
		SRC,
		/export async function buildContext\([\s\S]*?profileRow:\s*CoachProfileRow\s*\|\s*null,?\s*\):/,
		'buildContext must accept the profile row as a parameter',
	);
});

test('DOB + HR metrics gated on health_data_consent_at', () => {
	// audit/coach May 2026 High #1 — GDPR Art 9(2)(a) explicit consent
	// for special-category health data. When `health_data_consent_at`
	// is null (or revoked), DOB / resting_hr_bpm / max_hr_bpm /
	// hr_zones MUST emit as null. The two-gate design is documented
	// in migration 20260921_001_user_profiles_gdpr_consent_timestamps.
	assert.match(
		SRC,
		/healthConsentGranted\s*=\s*profileRowTyped\?\.health_data_consent_at\s*!=\s*null/,
		'context.ts must derive healthConsentGranted from profile.health_data_consent_at',
	);
	for (const field of ['date_of_birth', 'resting_hr_bpm', 'max_hr_bpm', 'hr_zones']) {
		// Each health field must be wrapped in the conditional.
		const re = new RegExp(`${field}:\\s*healthConsentGranted\\s*\\?`);
		assert.match(
			SRC,
			re,
			`context.ts must gate \`${field}\` on healthConsentGranted (Art 9(2)(a))`,
		);
	}
});

test('runner_context never emits raw secrets (defence-in-depth)', () => {
	// Sentinel check: the prefs bag could grow to include sensitive
	// keys later (e.g. an OAuth token, a third-party API key). Any
	// known-secret name should never appear in the runner_context
	// payload. Add new names to this list if the prefs schema grows.
	const FORBIDDEN_PREFS = ['access_token', 'refresh_token', 'api_key', 'password'];
	for (const k of FORBIDDEN_PREFS) {
		assert.equal(
			new RegExp(`prefs\\.${k}`).test(SRC),
			false,
			`context.ts must NEVER project \`prefs.${k}\` into runner_context`,
		);
	}
});

test('nutrition_7d is gated on health-data consent', () => {
	// Dietary intake is health-adjacent special-category data (Art 9),
	// so the 7-day nutrition rollup must only be queried when
	// healthConsentGranted is true — the same gate as DOB / HR. A
	// refactor that hoists the food_log query out of the guard fails
	// here rather than silently shipping intake data to Anthropic.
	// The table name routes through the F11 registry (core/schema.ts),
	// so the guard matches `from(TABLES.food_log)`, not the bare literal.
	// Indentation-tolerant: the query now lives inside the nutrition lane's
	// async IIFE, so the `if` block is nested one level deeper. Match from
	// the consent check through the food_log query up to the next closing
	// brace (the if-block's), regardless of indent.
	const guard = SRC.match(
		/if \(healthConsentGranted\) \{[\s\S]*?from\(TABLES\.food_log\)[\s\S]*?\}/,
	);
	assert.ok(
		guard,
		'the food_log query MUST live inside an `if (healthConsentGranted)` block',
	);
});

test('plan_weeks + plan_workouts queries are bounded by a .limit()', () => {
	// bug-hunt 2026-07-r2 H2 (issue #374). Every other context lane caps
	// itself (recent_runs .limit(runsLimit), recent_lifts, nutrition_7d)
	// so prompt size + per-call cost stay flat as history grows. The plan
	// lane used to fetch EVERY week + workout with no bound — a long or
	// REST-inserted plan then re-serialised its whole history into the
	// prompt on every call. Pin the caps in the source so a refactor that
	// drops one fails here rather than silently reintroducing the leak.
	assert.match(
		SRC,
		/from\('plan_weeks'\)[\s\S]*?\.limit\(COACH_PLAN_WEEKS_CAP\)/,
		'the plan_weeks query must be capped with .limit(COACH_PLAN_WEEKS_CAP)',
	);
	assert.match(
		SRC,
		/from\('plan_workouts'\)[\s\S]*?\.limit\(COACH_PLAN_WORKOUTS_CAP\)/,
		'the plan_workouts query must be capped with .limit(COACH_PLAN_WORKOUTS_CAP)',
	);
});

test('buildContext caps plan_weeks + plan_workouts row counts', async () => {
	// End-to-end over the chainable stub (whose .limit(n) truncates like
	// PostgREST): a plan with far more than the caps' worth of weeks +
	// workouts must not send them all. Fails before the fix (unbounded →
	// full history returned) and passes after (arrays clamped to the caps).
	const planRow = { id: 'p1', start_date: '2026-06-01', status: 'active' };
	const weeks = Array.from({ length: COACH_PLAN_WEEKS_CAP + 12 }, (_, i) => ({
		id: `w${i}`,
		plan_id: 'p1',
		week_index: i,
	}));
	const workouts = Array.from(
		{ length: COACH_PLAN_WORKOUTS_CAP + 60 },
		(_, i) => ({ id: `k${i}`, week_id: 'w0', scheduled_date: '2026-06-01' }),
	);
	const ctx = await buildContext(
		fakeSupabase({
			training_plans: planRow,
			plan_weeks: weeks,
			plan_workouts: workouts,
		}) as never,
		'user-1',
		null,
		10,
		{ display_name: 'R', preferred_unit: 'km', health_data_consent_at: null },
	);
	const data = ctx.data as { plan_weeks: unknown[]; plan_workouts: unknown[] };
	assert.equal(data.plan_weeks.length, COACH_PLAN_WEEKS_CAP);
	assert.equal(data.plan_workouts.length, COACH_PLAN_WORKOUTS_CAP);
});

test('buildContext runs its independent reads in parallel, not serially', () => {
	// perf-hunt 2026-06-10 (coach request path): plan, recent_runs,
	// recent_lifts, user_settings and the consent-gated nutrition rollup
	// are mutually independent. They used to run as five sequential awaits,
	// stacking ~5 Supabase round-trips of latency onto every coach message
	// before the first token streamed. Pin the Promise.all fan-out so a
	// refactor can't quietly re-serialise them.
	assert.match(
		SRC,
		/await Promise\.all\(\[/,
		'independent reads must be issued via Promise.all',
	);
	// Each independent read is an async IIFE lane handed to Promise.all —
	// count them so collapsing one back to a bare top-level await trips
	// this guard.
	const lanes = SRC.match(/const \w+Lane = \(async \(/g) ?? [];
	assert.ok(
		lanes.length >= 5,
		`expected >=5 parallel query lanes, found ${lanes.length}`,
	);
});

test('food_log query uses started_at, never the renamed logged_at column', () => {
	// Migration 20261208_001 renamed food_log.logged_at -> started_at.
	// A stray `.gte('logged_at', ...)` / `.order('logged_at', ...)` is a
	// PostgREST 400 (column does not exist), not a silent null, so pin
	// the column name in the source.
	assert.equal(
		/['"]logged_at['"]/.test(SRC),
		false,
		'context.ts must not reference the renamed logged_at column',
	);
	assert.match(
		SRC,
		/\.gte\(\s*'started_at'/,
		'the food_log window filter must use started_at',
	);
});

// --- buildContext end-to-end HR gate ----------------------------------

// Minimal chainable Supabase stub: every filter/order returns `this`;
// the terminal `.limit()` / `.maybeSingle()` resolve to `{ data }` keyed
// by table. Unknown tables resolve to null so lanes self-empty.
function fakeSupabase(tableData: Record<string, unknown>) {
	return {
		from(table: string) {
			const result = { data: tableData[table] ?? null, error: null };
			const q: Record<string, unknown> = {};
			for (const m of ['select', 'eq', 'in', 'order', 'gte']) {
				q[m] = () => q;
			}
			q.limit = (n?: number) =>
				Promise.resolve(
					Array.isArray(result.data) && typeof n === 'number'
						? { data: result.data.slice(0, n), error: null }
						: result,
				);
			q.maybeSingle = () => Promise.resolve(result);
			return q;
		},
	};
}

function runWithConsent(consentAt: string | null) {
	const runRow = {
		id: 'r1',
		started_at: '2026-06-08T08:00:00.000Z',
		distance_m: 10000,
		duration_s: 3000,
		metadata: { activity_type: 'run', avg_bpm: 152 },
		route_id: null,
	};
	const profileRow: CoachProfileRow = {
		display_name: 'Runner',
		preferred_unit: 'km',
		health_data_consent_at: consentAt,
	};
	return buildContext(
		fakeSupabase({ runs: [runRow] }) as never,
		'user-1',
		null,
		10,
		profileRow,
	);
}

test('buildContext strips per-run avg_bpm when health consent is null', async () => {
	// End-to-end: an Art 9 heart-rate value on a recent run must NOT reach
	// the Anthropic-bound context when the runner has never granted (or has
	// revoked) health-data consent.
	const ctx = await runWithConsent(null);
	const runs = (ctx.data as { recent_runs: { metadata: unknown }[] }).recent_runs;
	assert.equal(runs.length, 1);
	assert.deepEqual(runs[0].metadata, { activity_type: 'run' });
});

test('buildContext keeps per-run avg_bpm when health consent is granted', async () => {
	const ctx = await runWithConsent('2026-06-01T00:00:00.000Z');
	const runs = (ctx.data as { recent_runs: { metadata: unknown }[] }).recent_runs;
	assert.equal(runs.length, 1);
	assert.deepEqual(runs[0].metadata, { activity_type: 'run', avg_bpm: 152 });
});

// --- cross-tenant scoping (issue #373) --------------------------------

// Filter-aware Supabase stub: honours .eq / .in / .gte so a query that
// forgets .eq('user_id', caller) sees EVERY seeded row (the pre-fix leak),
// while the scoped query sees only the caller's. Terminal .limit resolves to
// the matched array, .maybeSingle to its first row (or null).
function filteringSupabase(tableData: Record<string, unknown[]>) {
	return {
		from(table: string) {
			const rows: unknown[] = Array.isArray(tableData[table]) ? tableData[table] : [];
			const eqs: Array<[string, unknown]> = [];
			const ins: Array<[string, unknown[]]> = [];
			let gte: [string, string] | null = null;
			const matched = () =>
				rows.filter((r) => {
					const row = r as Record<string, unknown>;
					if (!eqs.every(([c, v]) => row[c] === v)) return false;
					if (!ins.every(([c, vs]) => vs.includes(row[c]))) return false;
					if (gte && !(String(row[gte[0]]) >= gte[1])) return false;
					return true;
				});
			const q: Record<string, unknown> = {};
			q.select = () => q;
			q.order = () => q;
			q.eq = (c: string, v: unknown) => {
				eqs.push([c, v]);
				return q;
			};
			q.in = (c: string, vs: unknown[]) => {
				ins.push([c, vs]);
				return q;
			};
			q.gte = (c: string, v: string) => {
				gte = [c, v];
				return q;
			};
			q.limit = () => Promise.resolve({ data: matched(), error: null });
			q.maybeSingle = () => Promise.resolve({ data: matched()[0] ?? null, error: null });
			// Awaiting a query that terminates in .eq/.in/.order (plan_weeks,
			// plan_workouts, gym_sets have no .limit) resolves to the array.
			q.then = (
				onFulfilled: (v: unknown) => unknown,
				onRejected?: (e: unknown) => unknown,
			) => Promise.resolve({ data: matched(), error: null }).then(onFulfilled, onRejected);
			return q;
		},
	};
}

const ATHLETE = 'athlete-a';
const COACH = 'coach-b';

function coachTenantFixture() {
	// Athlete rows are listed FIRST in every array so a pre-fix, RLS-only
	// read (which the filtering stub models by returning all rows the query
	// didn't filter) would surface the ATHLETE's row — .maybeSingle() would
	// pick the athlete's active plan, .limit() would include the athlete's
	// runs/lifts/food. The fix scopes each lane to the caller (COACH).
	const soon = new Date(Date.now() - 86_400_000).toISOString();
	return {
		runs: [
			{ id: 'run-a', user_id: ATHLETE, started_at: soon, distance_m: 21000, duration_s: 7200, metadata: { activity_type: 'run', avg_bpm: 160 }, route_id: null },
			{ id: 'run-b', user_id: COACH, started_at: soon, distance_m: 5000, duration_s: 1500, metadata: { activity_type: 'run' }, route_id: null },
		],
		training_plans: [
			{ id: 'plan-a', user_id: ATHLETE, status: 'active', is_template: false },
			{ id: 'plan-b', user_id: COACH, status: 'active', is_template: false },
		],
		plan_weeks: [
			{ id: 'week-a', plan_id: 'plan-a', week_index: 0 },
			{ id: 'week-b', plan_id: 'plan-b', week_index: 0 },
		],
		plan_workouts: [
			{ id: 'wk-a', week_id: 'week-a', scheduled_date: '2026-06-01' },
			{ id: 'wk-b', week_id: 'week-b', scheduled_date: '2026-06-01' },
		],
		gym_workouts: [
			{ id: 'gym-a', user_id: ATHLETE, title: 'A push', started_at: soon },
			{ id: 'gym-b', user_id: COACH, title: 'B pull', started_at: soon },
		],
		gym_sets: [
			{ workout_id: 'gym-a', exercise_name: 'Bench', reps: 5, weight_kg: 80 },
			{ workout_id: 'gym-b', exercise_name: 'Row', reps: 5, weight_kg: 60 },
		],
		food_log: [
			{ user_id: ATHLETE, started_at: soon, calories: 900, protein_g: 40, carbs_g: 100, fat_g: 20 },
			{ user_id: COACH, started_at: soon, calories: 500, protein_g: 30, carbs_g: 50, fat_g: 10 },
		],
	};
}

const COACH_PROFILE: CoachProfileRow = {
	display_name: 'Coach',
	preferred_unit: 'km',
	health_data_consent_at: '2026-06-01T00:00:00.000Z',
};

test('buildContext no-plan_id branch returns the CALLER active plan, not an athlete plan', async () => {
	const ctx = await buildContext(
		filteringSupabase(coachTenantFixture()) as never,
		COACH,
		null,
		10,
		COACH_PROFILE,
	);
	const data = ctx.data as {
		plan: { id: string; user_id: string } | null;
		plan_weeks: { id: string }[];
		plan_workouts: { id: string }[];
	};
	assert.equal(data.plan?.id, 'plan-b', 'must resolve the coach own active plan');
	assert.equal(data.plan?.user_id, COACH);
	assert.deepEqual(data.plan_weeks.map((w) => w.id), ['week-b']);
	assert.deepEqual(data.plan_workouts.map((w) => w.id), ['wk-b']);
});

test('buildContext leaks none of an athlete recent runs into a coach context', async () => {
	const ctx = await buildContext(
		filteringSupabase(coachTenantFixture()) as never,
		COACH,
		null,
		10,
		COACH_PROFILE,
	);
	const runs = (ctx.data as { recent_runs: { id: string; metadata: unknown }[] }).recent_runs;
	assert.deepEqual(runs.map((r) => r.id), ['run-b'], 'only the coach own run');
});

test('buildContext scopes lifts + nutrition to the caller', async () => {
	const ctx = await buildContext(
		filteringSupabase(coachTenantFixture()) as never,
		COACH,
		null,
		10,
		COACH_PROFILE,
	);
	const data = ctx.data as {
		recent_lifts: { title: string | null; volume_kg: number }[];
		nutrition_7d: { avg_calories: number | null } | null;
	};
	assert.equal(data.recent_lifts.length, 1);
	assert.equal(data.recent_lifts[0].title, 'B pull');
	assert.equal(data.recent_lifts[0].volume_kg, 5 * 60, 'only the coach own sets');
	// Coach food only: 500 kcal on the one logged day (the athlete 900 excluded).
	assert.equal(data.nutrition_7d?.avg_calories, 500);
});

test('buildContext with an athlete planId still returns nothing cross-tenant', async () => {
	// A coach passing an athlete plan id (RLS would allow the read) must not
	// resolve it — the plan lane scopes on user_id, so a foreign id yields null.
	const ctx = await buildContext(
		filteringSupabase(coachTenantFixture()) as never,
		COACH,
		'plan-a',
		10,
		COACH_PROFILE,
	);
	const data = ctx.data as { plan: unknown; plan_weeks: unknown[]; plan_workouts: unknown[] };
	assert.equal(data.plan, null, 'a foreign plan id must not resolve');
	assert.deepEqual(data.plan_weeks, []);
	assert.deepEqual(data.plan_workouts, []);
});

// --- summarizeRecentLifts ---------------------------------------------

test('summarizeRecentLifts rolls sets into per-session summaries', () => {
	const workouts = [
		{ id: 'w1', title: 'Push day', started_at: '2026-06-03T08:00:00.000Z' },
		{ id: 'w2', title: null, started_at: '2026-06-01T18:00:00.000Z' },
	];
	const sets = [
		{ workout_id: 'w1', exercise_name: 'Bench', reps: 5, weight_kg: 60 },
		{ workout_id: 'w1', exercise_name: 'Bench', reps: 5, weight_kg: 60 },
		{ workout_id: 'w1', exercise_name: 'OHP', reps: 8, weight_kg: 40 },
		{ workout_id: 'w2', exercise_name: 'Squat', reps: 5, weight_kg: 100 },
	];
	const out = summarizeRecentLifts(workouts, sets);
	assert.equal(out.length, 2);
	assert.deepEqual(out[0], {
		date: '2026-06-03',
		title: 'Push day',
		exercises: 2,
		sets: 3,
		volume_kg: 5 * 60 + 5 * 60 + 8 * 40, // 920
	});
	assert.equal(out[1].title, null);
	assert.equal(out[1].volume_kg, 500);
});

test('summarizeRecentLifts ignores bodyweight sets in volume + caps count', () => {
	const workouts = Array.from({ length: COACH_LIFTS_CAP + 3 }, (_, i) => ({
		id: `w${i}`,
		title: null,
		started_at: `2026-06-0${(i % 9) + 1}T08:00:00.000Z`,
	}));
	const sets = [
		{ workout_id: 'w0', exercise_name: 'Pull-up', reps: 10, weight_kg: null },
		{ workout_id: 'w0', exercise_name: 'Row', reps: 8, weight_kg: 50 },
	];
	const out = summarizeRecentLifts(workouts, sets);
	assert.equal(out.length, COACH_LIFTS_CAP, 'caps at COACH_LIFTS_CAP sessions');
	// Bodyweight set (no weight) contributes 0 tonnage; only the row counts.
	assert.equal(out[0].volume_kg, 8 * 50);
	assert.equal(out[0].exercises, 2);
	assert.equal(out[0].sets, 2);
});

test('summarizeRecentLifts counts exercises on the canonical grouping key', () => {
	// One lift, five spellings. Told to the model as five exercises, the
	// session reads as a circuit rather than as the five sets of bench it
	// was — and the tally used to answer differently from every keyed
	// surface in the app (§ 1274).
	const workouts = [{ id: 'w1', title: 'Push day', started_at: '2026-06-03T08:00:00.000Z' }];
	const spellings = ['Bench Press', 'bench press ', 'Bench  Press', 'Bench\u00a0Press', '\u0130ncline Press'];
	const sets = spellings.map((exercise_name) => ({
		workout_id: 'w1',
		exercise_name,
		reps: 5,
		weight_kg: 60,
	}));
	const out = summarizeRecentLifts(workouts, sets);
	assert.equal(out[0].exercises, 2, 'four spellings of bench plus one incline');
	assert.equal(out[0].sets, 5);
});

test('summarizeRecentLifts: a blank exercise name is not an exercise', () => {
	const workouts = [{ id: 'w1', title: null, started_at: '2026-06-03T08:00:00.000Z' }];
	const sets = [
		{ workout_id: 'w1', exercise_name: '   ', reps: 5, weight_kg: 60 },
		{ workout_id: 'w1', exercise_name: '\u00a0', reps: 5, weight_kg: 60 },
	];
	const out = summarizeRecentLifts(workouts, sets);
	assert.equal(out[0].exercises, 0);
	assert.equal(out[0].sets, 2);
});

// --- summarizeNutrition -----------------------------------------------

test('summarizeNutrition averages over days logged within the 7-day window', () => {
	const now = new Date('2026-06-08T12:00:00.000Z');
	const rows = [
		// Two items on day A
		{ started_at: '2026-06-08T08:00:00.000Z', calories: 400, protein_g: 30, carbs_g: 40, fat_g: 10 },
		{ started_at: '2026-06-08T13:00:00.000Z', calories: 600, protein_g: 20, carbs_g: 80, fat_g: 20 },
		// One item on day B
		{ started_at: '2026-06-06T08:00:00.000Z', calories: 1000, protein_g: 50, carbs_g: 100, fat_g: 30 },
	];
	const out = summarizeNutrition(rows, now);
	assert.ok(out);
	assert.equal(out.days_logged, 2);
	// Totals: cal 2000, protein 100, over 2 days → 1000 / 50.
	assert.equal(out.avg_calories, 1000);
	assert.equal(out.avg_protein_g, 50);
	assert.equal(out.avg_carbs_g, 110);
	assert.equal(out.avg_fat_g, 30);
});

test('summarizeNutrition drops rows outside the window and returns null when empty', () => {
	const now = new Date('2026-06-08T12:00:00.000Z');
	// 8 days old — outside the 7-day window.
	const stale = [
		{ started_at: '2026-05-31T08:00:00.000Z', calories: 500, protein_g: 20, carbs_g: 50, fat_g: 10 },
	];
	assert.equal(summarizeNutrition(stale, now), null);
	assert.equal(summarizeNutrition([], now), null);
});

test('summarizeNutrition yields null macro averages when no row carries that macro', () => {
	const now = new Date('2026-06-08T12:00:00.000Z');
	const rows = [
		{ started_at: '2026-06-08T08:00:00.000Z', calories: 400, protein_g: null, carbs_g: null, fat_g: null },
	];
	const out = summarizeNutrition(rows, now);
	assert.ok(out);
	assert.equal(out.avg_calories, 400);
	assert.equal(out.avg_protein_g, null);
	assert.equal(out.avg_carbs_g, null);
	assert.equal(out.avg_fat_g, null);
});
