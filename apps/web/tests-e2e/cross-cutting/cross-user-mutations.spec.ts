import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Cross-user write boundary — UPDATE and DELETE attempts.
 *
 * The auth-walls suite covers the SELECT-side leak (User A's private
 * run not visible to User B). The db-constraints suite covers
 * authenticated-but-privileged writes (the lock_subscription_columns
 * trigger). What was missing: a user with a real session attempting
 * UPDATE / DELETE on rows they don't own. RLS UPDATE / DELETE
 * policies are a separate code path from SELECT — a regression that
 * scopes a SELECT correctly but leaves UPDATE wide open silently
 * lets one user nuke another user's runs.
 *
 * Each test signs in as USER_B (alex) with a real JWT, attempts a
 * mutation against USER_A (runner)'s row, and asserts (a) the call
 * fails or no-ops, (b) the row is unchanged when re-read via
 * service-role.
 */

test.describe('cross-user mutation boundaries', () => {
	test('User B cannot UPDATE User A\'s run (RLS blocks the cross-user write)', async () => {
		const admin = getAdminClient();

		const { data: before } = await admin
			.from('runs')
			.select('distance_m, metadata')
			.eq('id', RUNNER_PUBLIC_RUN_ID)
			.single();
		const beforeDistance = (before as { distance_m: number }).distance_m;

		const alex = await getUserClient({
			email: USER_B.email,
			password: USER_B.password
		});

		// Try to clobber the distance. RLS UPDATE policy on `runs`
		// scopes by `auth.uid() = user_id`; alex's uid != runner's so
		// this must either error OR return zero rows updated.
		const { error, data } = await alex
			.from('runs')
			.update({ distance_m: 99 })
			.eq('id', RUNNER_PUBLIC_RUN_ID)
			.select();

		// Postgres-side: either an explicit RLS error, OR a successful
		// query that touches zero rows (returns []). Both are fine —
		// what matters is the row stayed put. supabase-js doesn't
		// surface "0 rows updated" as an error by default.
		if (error) {
			expect(error.code).not.toBe('00000');
		} else {
			expect((data as unknown[])?.length).toBe(0);
		}

		const { data: after } = await admin
			.from('runs')
			.select('distance_m')
			.eq('id', RUNNER_PUBLIC_RUN_ID)
			.single();
		expect((after as { distance_m: number }).distance_m).toBe(beforeDistance);
	});

	test('User B cannot DELETE User A\'s run', async () => {
		const admin = getAdminClient();
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false
		});

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});
			const { error } = await alex
				.from('runs')
				.delete()
				.eq('id', planted);

			if (error) {
				expect(error.code).not.toBe('00000');
			}

			// Row still there.
			const { data: row } = await admin
				.from('runs')
				.select('id')
				.eq('id', planted)
				.maybeSingle();
			expect(row).not.toBeNull();
		} finally {
			await deleteRun(planted);
		}
	});

	test('User B cannot UPDATE User A\'s route (e.g. star, public-toggle)', async () => {
		const admin = getAdminClient();

		// Find any of runner's routes to attack.
		const { data: route } = await admin
			.from('routes')
			.select('id, is_starred')
			.eq('user_id', USER_A.id)
			.limit(1)
			.single();
		const r = route as { id: string; is_starred: boolean };
		const beforeStarred = r.is_starred;

		const alex = await getUserClient({
			email: USER_B.email,
			password: USER_B.password
		});

		// Try to flip is_starred. RLS UPDATE policy must reject.
		const { error, data } = await alex
			.from('routes')
			.update({ is_starred: !beforeStarred })
			.eq('id', r.id)
			.select();

		if (error) {
			expect(error.code).not.toBe('00000');
		} else {
			expect((data as unknown[])?.length).toBe(0);
		}

		const { data: after } = await admin
			.from('routes')
			.select('is_starred')
			.eq('id', r.id)
			.single();
		expect((after as { is_starred: boolean }).is_starred).toBe(beforeStarred);
	});

	test('User B cannot DELETE comments they did not author on User A\'s run', async () => {
		const admin = getAdminClient();
		// Plant a comment authored by USER_A (the run owner) — alex
		// (USER_B) is neither the author nor the run owner so they
		// have no path to delete it.
		const { data: planted, error: insertErr } = await admin
			.from('run_comments')
			.insert({
				run_id: RUNNER_PUBLIC_RUN_ID,
				author_id: USER_A.id,
				body: `e2e-cross-user-delete ${Date.now()}`
			})
			.select('id')
			.single();
		if (insertErr) throw insertErr;
		const commentId = (planted as { id: string }).id;

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});
			const { error } = await alex
				.from('run_comments')
				.delete()
				.eq('id', commentId);

			if (error) {
				expect(error.code).not.toBe('00000');
			}

			const { data: row } = await admin
				.from('run_comments')
				.select('id')
				.eq('id', commentId)
				.maybeSingle();
			expect(row).not.toBeNull();
		} finally {
			await admin.from('run_comments').delete().eq('id', commentId);
		}
	});

	test('Morgan (non-member) cannot INSERT a club_post into Friends of Jared', async () => {
		// "Friends of Jared" is the seeded private club owned by
		// runner. Morgan (USER_C_PRO) is NOT a member; alex is a
		// 'pending' member which would still get past the
		// is_club_member gate if the policy was buggy, so morgan is
		// the cleaner attacker. RLS INSERT on club_posts requires
		// `is_club_member(club_id) AND author_id = auth.uid()`.
		const admin = getAdminClient();
		const FRIENDS_CLUB_ID = 'c2222222-0000-0000-0000-000000000002';

		// Sanity: morgan is not in this club (per seed).
		const { data: membership } = await admin
			.from('club_members')
			.select('user_id')
			.eq('club_id', FRIENDS_CLUB_ID)
			.eq('user_id', USER_C_PRO.id)
			.maybeSingle();
		expect(membership).toBeNull();

		const morgan = await getUserClient({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});

		const { error } = await morgan.from('club_posts').insert({
			club_id: FRIENDS_CLUB_ID,
			author_id: USER_C_PRO.id,
			body: 'e2e cross-user club post attempt'
		});

		// RLS rejection — Postgres returns an error for INSERT
		// violations (unlike UPDATE/DELETE which can return 0 rows
		// silently). Pin the rejection.
		expect(error).not.toBeNull();
		expect(error?.code).toMatch(/^(42501|PGRST|P0001)/);

		// Belt + braces: no row landed.
		const { count } = await admin
			.from('club_posts')
			.select('id', { count: 'exact', head: true })
			.eq('club_id', FRIENDS_CLUB_ID)
			.eq('author_id', USER_C_PRO.id);
		expect(count).toBe(0);
	});

	test('User B cannot UPDATE another user\'s run_kudos row', async () => {
		// run_kudos has a primary key on (run_id, user_id) and an RLS
		// policy that scopes writes to the row's user_id. Pin that
		// alex can't poison runner's existing kudos rows.
		const admin = getAdminClient();
		// Plant a kudos by runner on their own public run (well, it's
		// a no-op since runner can't kudos their own run via the UI,
		// but service-role can plant any pair).
		await admin
			.from('run_kudos')
			.insert({ run_id: RUNNER_PUBLIC_RUN_ID, user_id: USER_A.id });

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});
			// Try to delete a kudos belonging to a different user.
			const { error } = await alex
				.from('run_kudos')
				.delete()
				.eq('run_id', RUNNER_PUBLIC_RUN_ID)
				.eq('user_id', USER_A.id);

			if (error) {
				expect(error.code).not.toBe('00000');
			}

			const { data: row } = await admin
				.from('run_kudos')
				.select('user_id')
				.eq('run_id', RUNNER_PUBLIC_RUN_ID)
				.eq('user_id', USER_A.id)
				.maybeSingle();
			expect(row).not.toBeNull();
		} finally {
			await admin
				.from('run_kudos')
				.delete()
				.eq('run_id', RUNNER_PUBLIC_RUN_ID)
				.eq('user_id', USER_A.id);
		}
	});
});
