import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Backend boundary: hard database guards that protect a security or
 * business invariant. Each one is a "the safety net itself works"
 * assertion — distinct from RLS policy tests (which check who-can-
 * read) and trigger tests (which check side-effects fire). These
 * verify the DB rejects state that violates a constraint, even
 * when the offending write goes through service-role (which
 * bypasses RLS but NOT the underlying constraint).
 */

test.describe('database constraints', () => {
	test('training_plans_one_active partial unique index rejects a duplicate active plan', async () => {
		// Migration 20260419_001 ships:
		//   create unique index training_plans_one_active
		//     on training_plans(user_id) where status = 'active';
		// `createTrainingPlan` works around this in app code by auto-
		// demoting the existing active plan to 'completed' before
		// inserting the new one. This test pins the SAFETY NET — if
		// app-side demotion ever broke (or a future migration
		// dropped the partial index), the DB itself must still
		// reject the duplicate. Service role does NOT bypass unique
		// constraints; the insert below will fail with 23505.
		const admin = getAdminClient();

		// Sanity: runner already has Sydney Half active (per seed).
		const { data: existing } = await admin
			.from('training_plans')
			.select('id, status')
			.eq('user_id', USER_A.id)
			.eq('status', 'active');
		expect(existing?.length).toBeGreaterThanOrEqual(1);

		// Try to insert a SECOND active plan for runner. We let the
		// auto-generator skip plan_weeks/plan_workouts; the index is
		// on training_plans alone.
		const { error } = await admin.from('training_plans').insert({
			user_id: USER_A.id,
			name: 'e2e duplicate-active-plan attempt',
			// goal_event is a custom enum (distance_5k / distance_10k /
			// distance_half / distance_full / custom). Pick the same
			// shape as the seeded Sydney Half plan so the row passes
			// the CHECK + enum cast.
			goal_event: 'distance_half',
			goal_distance_m: 21097,
			start_date: '2026-09-01',
			end_date: '2026-12-01',
			days_per_week: 4,
			vdot: 50,
			status: 'active'
		});

		expect(error?.code).toBe('23505'); // unique_violation
		expect(error?.message ?? '').toMatch(/training_plans_one_active/);

		// Sanity: runner still has exactly the seeded count of active
		// plans — no half-inserted row leaked.
		const { count } = await admin
			.from('training_plans')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id)
			.eq('status', 'active');
		expect(count).toBe(existing?.length);
	});

	test('subscription_tier is read-only for non-service-role callers (no self-upgrade to Pro)', async () => {
		// Migration 20260624_001 installs a BEFORE-UPDATE trigger that
		// raises if a non-service-role caller mutates subscription_tier
		// or subscription_at. The threat: a malicious user opens
		// devtools and PATCHes their own user_profiles row to bump
		// themselves to Pro. RLS allows the row update (it's their
		// own row) but the trigger MUST block the privileged column
		// from changing. Without this guard the paywall is bypassable
		// in 30 seconds with curl.
		//
		// Sign in as runner with a real user JWT (NOT the service-role
		// client — that one would actually succeed). Attempt the
		// upgrade, expect a Postgres exception, then verify via
		// service-role that the row never changed.
		const admin = getAdminClient();
		const { data: before } = await admin
			.from('user_profiles')
			.select('subscription_tier, subscription_at')
			.eq('id', USER_A.id)
			.single();
		expect(before?.subscription_tier).toBe('free');

		const userClient = await getUserClient({
			email: USER_A.email,
			password: USER_A.password
		});

		const { error } = await userClient
			.from('user_profiles')
			.update({ subscription_tier: 'pro' })
			.eq('id', USER_A.id);

		// The trigger raises with a message starting with
		// "subscription_tier is read-only for non-service-role callers".
		expect(error).not.toBeNull();
		expect(error?.message ?? '').toMatch(/read-only|service-role/i);

		// Verify via service-role that the row didn't change.
		const { data: after } = await admin
			.from('user_profiles')
			.select('subscription_tier, subscription_at')
			.eq('id', USER_A.id)
			.single();
		expect(after?.subscription_tier).toBe('free');
		expect(after?.subscription_at).toBe(before?.subscription_at ?? null);
	});
});
