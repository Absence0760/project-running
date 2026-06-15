import { expect, test } from '@playwright/test';

import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Server-side permission backstop. The club detail UI hides the post
 * composer from non-members and the admin controls from non-admins —
 * but the UI is not the security boundary. RLS is. These tests drive
 * the PostgREST API directly with a REAL user JWT (not the service-
 * role client, which bypasses RLS) to prove the policies reject:
 *
 *   - a non-member inserting a club_post     ("members can post")
 *   - a plain member approving a pending     ("admins can manage
 *     request (UPDATE status→active)          members" UPDATE)
 *   - a plain member changing another's role ( same UPDATE policy )
 *   - a plain member removing another member ("admins can manage
 *                                              members" DELETE)
 *
 * Richmond Run Club is open/public. Morgan (USER_C_PRO) is NOT seeded
 * into it, so she is a non-member. Alex (USER_B) IS a seeded plain
 * member, so he's the non-admin actor for the manage-members cases.
 */

const RICHMOND_ID = 'c1111111-0000-0000-0000-000000000001';

async function signedInClient(user: {
	email: string;
	password: string;
}): Promise<SupabaseClient> {
	const { url, anonKey } = loadSupabaseEnv();
	const client = createClient(url, anonKey, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
	const { error } = await client.auth.signInWithPassword({
		email: user.email,
		password: user.password
	});
	if (error) throw new Error(`sign-in failed for ${user.email}: ${error.message}`);
	return client;
}

test.describe('club write-path RLS — UI gates are not the security boundary', () => {
	test('a non-member cannot insert a club_post (RLS "members can post")', async () => {
		const morgan = await signedInClient(USER_C_PRO);
		// Unique body so the cleanup-sanity check below is scoped to THIS
		// insert and can't be confused by unrelated rows left by other
		// specs (e.g. the join-then-post saga in clubs/join.spec.ts).
		const body = `e2e-nonmember-post ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
		const { data, error } = await morgan
			.from('club_posts')
			.insert({
				club_id: RICHMOND_ID,
				author_id: USER_C_PRO.id,
				body
			})
			.select('id');

		// Insert must be rejected (RLS WITH CHECK fails → 42501).
		expect(error, 'non-member post insert must be rejected').not.toBeNull();
		expect(data ?? []).toEqual([]);

		// Belt-and-braces: this exact body never landed.
		const admin = getAdminClient();
		const { count } = await admin
			.from('club_posts')
			.select('id', { count: 'exact', head: true })
			.eq('club_id', RICHMOND_ID)
			.eq('body', body);
		expect(count).toBe(0);
	});

	test('a plain member cannot approve a pending request (UPDATE blocked by "admins can manage members")', async () => {
		// Plant a pending requester (morgan) via service-role, then have
		// alex (a plain member, not admin) try to flip her to active via
		// PostgREST. The admins-only UPDATE policy must filter the row out
		// so the UPDATE affects ZERO rows — morgan stays pending.
		const admin = getAdminClient();
		await admin.from('club_members').upsert(
			{ club_id: RICHMOND_ID, user_id: USER_C_PRO.id, role: 'member', status: 'pending' },
			{ onConflict: 'club_id,user_id' }
		);

		try {
			const alex = await signedInClient(USER_B);
			const { data } = await alex
				.from('club_members')
				.update({ status: 'active' })
				.eq('club_id', RICHMOND_ID)
				.eq('user_id', USER_C_PRO.id)
				.select('user_id');
			// Either a hard reject or (more typically) a silent zero-row
			// update — the RLS USING clause excludes the row for a non-admin.
			expect(data ?? []).toEqual([]);

			// Authoritative check: the status is still pending.
			const { data: row } = await admin
				.from('club_members')
				.select('status')
				.eq('club_id', RICHMOND_ID)
				.eq('user_id', USER_C_PRO.id)
				.single();
			expect(row?.status).toBe('pending');
		} finally {
			await admin
				.from('club_members')
				.delete()
				.eq('club_id', RICHMOND_ID)
				.eq('user_id', USER_C_PRO.id);
		}
	});

	test('a plain member cannot change another member\'s role', async () => {
		// Alex tries to promote himself (or anyone) to admin via PostgREST.
		// The admins-only UPDATE policy blocks it — alex stays a member.
		const admin = getAdminClient();
		const alex = await signedInClient(USER_B);
		const { data } = await alex
			.from('club_members')
			.update({ role: 'admin' })
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_B.id)
			.select('user_id');
		expect(data ?? []).toEqual([]);

		const { data: row } = await admin
			.from('club_members')
			.select('role')
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_B.id)
			.single();
		expect(row?.role).toBe('member');
	});

	test('a plain member cannot remove a different member (DELETE only self or admin)', async () => {
		// The owner (runner) row must survive a plain member's delete
		// attempt — "users can leave clubs" only lets you delete your OWN
		// row; "admins can manage members" lets an admin delete others.
		// Alex is neither admin nor the owner, so the delete affects zero
		// rows.
		const admin = getAdminClient();
		const alex = await signedInClient(USER_B);
		const { data } = await alex
			.from('club_members')
			.delete()
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_A.id)
			.select('user_id');
		expect(data ?? []).toEqual([]);

		// The owner row is intact.
		const { data: owner } = await admin
			.from('club_members')
			.select('role, status')
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_A.id)
			.single();
		expect(owner?.role).toBe('owner');
		expect(owner?.status).toBe('active');
	});
});
