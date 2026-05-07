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

	test('run_kudos UNIQUE rejects a duplicate (user_id, run_id) pair', async () => {
		// run_kudos is the engagement table where the rule "one kudos
		// per (user, run)" makes the toggle UI work — clicking kudos
		// twice rescinds rather than inserting two rows. The DB-level
		// guard is a primary key on (user_id, run_id).
		const admin = getAdminClient();
		const { data: run } = await admin
			.from('runs')
			.select('id')
			.eq('user_id', USER_A.id)
			.eq('is_public', true)
			.limit(1)
			.single();
		const runId = (run as { id: string }).id;
		// Plant a kudos with USER_A; second insert with the same pair
		// must 23505.
		await admin.from('run_kudos').insert({ run_id: runId, user_id: USER_A.id });
		try {
			const { error } = await admin
				.from('run_kudos')
				.insert({ run_id: runId, user_id: USER_A.id });
			expect(error?.code).toBe('23505');
		} finally {
			await admin
				.from('run_kudos')
				.delete()
				.eq('run_id', runId)
				.eq('user_id', USER_A.id);
		}
	});

	test('user_follows UNIQUE rejects a duplicate (follower_id, followee_id) pair', async () => {
		// user_follows enforces "one follow edge per (a, b)" via primary
		// key. A regression that lets the same edge be inserted twice
		// would inflate follower_count via fetchProfile (which counts
		// rows). Test: USER_A already follows USER_B per seed; INSERT
		// the same edge again must 23505.
		const admin = getAdminClient();
		const { error } = await admin
			.from('user_follows')
			.insert({ follower_id: USER_A.id, followee_id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012' });
		expect(error?.code).toBe('23505');
	});

	test('club_members PK rejects a duplicate (club_id, user_id) pair', async () => {
		// club_members is keyed on (club_id, user_id) so a user can be
		// at most one row per club. Alex is seeded as active in Sydney
		// Run Club; a duplicate INSERT must reject.
		const admin = getAdminClient();
		const { error } = await admin.from('club_members').insert({
			club_id: 'c1111111-0000-0000-0000-000000000001',
			user_id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012',
			role: 'member',
			status: 'active'
		});
		expect(error?.code).toBe('23505');
	});

	test('clubs.slug UNIQUE rejects a duplicate slug', async () => {
		// clubs.slug is text unique not null. Two clubs with the same
		// slug would break /clubs/[slug] addressing entirely.
		const admin = getAdminClient();
		const { error } = await admin.from('clubs').insert({
			owner_id: USER_A.id,
			name: 'duplicate slug attempt',
			slug: 'sydney-run-club',
			is_public: true,
			join_policy: 'open'
		});
		expect(error?.code).toBe('23505');
	});

	test('training_plans CHECK end_date >= start_date rejects an inverted range', async () => {
		// The plan generator's contract is end > start. A regression
		// that passes them swapped must 23514 at the DB level.
		const admin = getAdminClient();
		const { error } = await admin.from('training_plans').insert({
			user_id: USER_A.id,
			name: 'inverted-range attempt',
			goal_event: 'distance_5k',
			goal_distance_m: 5000,
			start_date: '2026-12-01',
			end_date: '2026-09-01',
			days_per_week: 4,
			status: 'completed' // avoid stepping on the active-uniqueness test
		});
		expect(error?.code).toBe('23514');
	});

	test('training_plans CHECK days_per_week between 3 and 7 rejects an out-of-range value', async () => {
		const admin = getAdminClient();
		const { error } = await admin.from('training_plans').insert({
			user_id: USER_A.id,
			name: 'days-per-week range attempt',
			goal_event: 'distance_5k',
			goal_distance_m: 5000,
			start_date: '2026-09-01',
			end_date: '2026-12-01',
			days_per_week: 10,
			status: 'completed'
		});
		expect(error?.code).toBe('23514');
	});

	test('runs.source CHECK rejects an unknown source enum value', async () => {
		// runs.source is a narrow-union CHECK enforced by migration
		// 20260505_001. Valid values: app / strava / parkrun / healthkit
		// / garmin. A regression that lets 'foo' through would surface
		// rows with no badge color or a fallthrough label.
		const admin = getAdminClient();
		const { error } = await admin.from('runs').insert({
			user_id: USER_A.id,
			started_at: new Date().toISOString(),
			duration_s: 600,
			distance_m: 1000,
			source: 'banana'
		});
		expect(error?.code).toBe('23514');
	});

	test('routes.surface CHECK rejects an unknown surface value', async () => {
		// routes.surface narrow union: road / trail / track / mixed.
		// `waypoints` is jsonb not null — supply an empty array.
		const admin = getAdminClient();
		const { error } = await admin.from('routes').insert({
			user_id: USER_A.id,
			name: 'e2e bad-surface attempt',
			waypoints: [],
			distance_m: 5000,
			surface: 'lava'
		});
		expect(error?.code).toBe('23514');
	});

	test('club_members.role CHECK rejects an unknown role value', async () => {
		// ClubRole narrow union: owner / admin / event_organiser /
		// race_director / member. The role-select dropdown is gated
		// on these; a write of any other value must reject.
		const admin = getAdminClient();
		const { error } = await admin.from('club_members').insert({
			club_id: 'c1111111-0000-0000-0000-000000000001',
			user_id: 'c3d4e5f6-a7b8-9012-cdef-345678901234', // morgan, not a member
			role: 'archmage',
			status: 'active'
		});
		expect(error?.code).toBe('23514');
	});

	test('user_profiles.subscription_tier CHECK rejects an unknown tier value (narrow union enforcement)', async () => {
		// SubscriptionTier is a TS narrow-union pinned in CHECK
		// constraints. A regression that tried to write 'gold' or
		// any value outside ('free','pro','lifetime') must 23514.
		const admin = getAdminClient();
		const { error } = await admin
			.from('user_profiles')
			.update({ subscription_tier: 'gold', subscription_at: new Date().toISOString() })
			.eq('id', USER_A.id);
		expect(error?.code).toBe('23514');
	});
});
