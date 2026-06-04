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

		// Sanity: runner already has Richmond Half active (per seed).
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
			// shape as the seeded Richmond Half plan so the row passes
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
			slug: 'richmond-run-club',
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

	test('route_reviews.rating CHECK rejects ratings outside 1..5', async () => {
		// route_reviews.rating is a smallint with check (rating between
		// 1 and 5). The 5-star widget can't emit anything outside that
		// range, but a curl-from-devtools attack could. Pin the DB
		// guard.
		const admin = getAdminClient();
		const { data: route } = await admin
			.from('routes')
			.select('id')
			.eq('user_id', USER_A.id)
			.limit(1)
			.single();
		const routeId = (route as { id: string }).id;
		const { error } = await admin.from('route_reviews').insert({
			route_id: routeId,
			user_id: USER_A.id,
			rating: 10,
			comment: 'e2e bad-rating attempt'
		});
		expect(error?.code).toBe('23514');
	});

	test('event_results.finisher_status CHECK rejects unknown status values', async () => {
		// finisher_status narrow union: finished / dnf / dns. A
		// regression that wrote 'dq' (disqualified) or any other
		// label outside the union must reject. Find any seeded
		// event id to anchor the FK.
		const admin = getAdminClient();
		const { data: ev } = await admin
			.from('events')
			.select('id')
			.limit(1)
			.maybeSingle();
		if (!ev) return; // no seeded event — skip
		const { error } = await admin.from('event_results').insert({
			event_id: (ev as { id: string }).id,
			instance_start: new Date().toISOString(),
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			finisher_status: 'dq'
		});
		expect(error?.code).toBe('23514');
	});

	test('event_results.duration_s CHECK rejects negative durations', async () => {
		// duration_s has CHECK (duration_s >= 0). A negative value
		// would silently flip lap-time signs across the leaderboard.
		const admin = getAdminClient();
		const { data: ev } = await admin
			.from('events')
			.select('id')
			.limit(1)
			.maybeSingle();
		if (!ev) return;
		const { error } = await admin.from('event_results').insert({
			event_id: (ev as { id: string }).id,
			instance_start: new Date().toISOString(),
			user_id: USER_A.id,
			duration_s: -1,
			distance_m: 5000,
			finisher_status: 'finished'
		});
		expect(error?.code).toBe('23514');
	});

	test('training_plans.status CHECK rejects an unknown status value', async () => {
		// training_plans.status narrow union (per migration 20260421_001):
		// active / completed / abandoned. Pin the DB guard against any
		// label outside that set.
		const admin = getAdminClient();
		const { error } = await admin.from('training_plans').insert({
			user_id: USER_A.id,
			name: 'e2e bad-status attempt',
			goal_event: 'distance_5k',
			goal_distance_m: 5000,
			start_date: '2026-09-01',
			end_date: '2026-12-01',
			days_per_week: 4,
			status: 'pending' // not one of active/completed/abandoned
		});
		expect(error?.code).toBe('23514');
	});

	test('notifications.kind CHECK rejects an unknown notification kind', async () => {
		// notifications.kind narrow union per migration 20260528_001:
		// kudos / comment / comment_reply / follow. A trigger that
		// fan-outs with the wrong label must hit 23514.
		const admin = getAdminClient();
		const { error } = await admin.from('notifications').insert({
			user_id: USER_A.id,
			kind: 'unknown',
			actor_id: USER_A.id
		});
		expect(error?.code).toBe('23514');
	});

	test('device_tokens.platform CHECK rejects an unknown platform value', async () => {
		// device_tokens.platform narrow union per migration 20260506_001:
		// ios / android / web. A regression that let 'desktop' through
		// would let push-fan-out write to the wrong queue.
		const admin = getAdminClient();
		const { error } = await admin.from('device_tokens').insert({
			user_id: USER_A.id,
			platform: 'desktop',
			token: `e2e-token-${Date.now()}`
		});
		expect(error?.code).toBe('23514');
	});

	test('plan_workouts FK to plan_weeks rejects an orphaned week_id', async () => {
		// plan_workouts.week_id references plan_weeks(id). Inserting a
		// workout with a bogus parent week must 23503 (foreign_key_
		// violation). Pin the integrity rule — a regression that
		// dropped the FK would let zombie workouts accumulate.
		const admin = getAdminClient();
		const { error } = await admin.from('plan_workouts').insert({
			week_id: '00000000-0000-0000-0000-000000000bad',
			scheduled_date: '2026-09-01',
			kind: 'easy'
		});
		expect(error?.code).toBe('23503');
	});

	test('club_members.user_id FK rejects an orphaned user_id (auth.users does not exist)', async () => {
		// club_members.user_id references auth.users(id). Plant against
		// a bogus user ID — the FK must 23503. Pin the integrity rule
		// against a regression that downgraded the FK to a soft
		// reference (e.g. removed REFERENCES auth.users).
		const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
		const admin = getAdminClient();
		const { error } = await admin.from('club_members').insert({
			club_id: SYDNEY_RUN_CLUB_ID,
			user_id: '00000000-0000-0000-0000-000000000bad',
			role: 'member',
			status: 'active'
		});
		expect(error?.code).toBe('23503');
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

	test('runs.activity_type CHECK rejects an out-of-domain value; column defaults pin the F3 promotion', async () => {
		// activity_type + is_dnf were promoted out of runs.metadata into
		// real columns by 20261207_001 (ActivityType TS narrow-union ↔
		// CHECK lockstep, guarded by check_constraint_unions.mjs). A write
		// outside ('run','walk','hike','cycle','stroller') must 23514, and
		// a row that omits both columns must land the defaults.
		const admin = getAdminClient();

		const bad = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				duration_s: 600,
				distance_m: 2000,
				source: 'app',
				activity_type: 'swim'
			})
			.select('id')
			.single();
		expect(bad.error?.code).toBe('23514');
		expect(bad.data).toBeNull();

		const ok = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				duration_s: 600,
				distance_m: 2000,
				source: 'app'
			})
			.select('id, activity_type, is_dnf')
			.single();
		try {
			expect(ok.error).toBeNull();
			expect(ok.data?.activity_type).toBe('run');
			expect(ok.data?.is_dnf).toBe(false);
		} finally {
			if (ok.data?.id) await admin.from('runs').delete().eq('id', ok.data.id);
		}
	});
});
