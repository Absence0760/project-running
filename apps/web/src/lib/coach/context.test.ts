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
			q.limit = () => Promise.resolve(result);
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
