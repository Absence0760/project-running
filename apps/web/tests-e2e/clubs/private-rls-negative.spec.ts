import { expect, test } from '@playwright/test';

import { createClient } from '@supabase/supabase-js';

import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * Private-club RLS negative cases.
 *
 * "Friends of Jared" is seeded private (is_public=false,
 * join_policy='invite'). The RLS contract (migration
 * 20260416_001_clubs_and_events.sql) is:
 *   - "public clubs are readable by anyone"
 *   - "private clubs are readable by members"
 *
 * So a non-member — signed-in OR anonymous — must NOT be able to read
 * the row. The client `fetchClubBySlug` does a `.maybeSingle()` which
 * resolves to null under RLS, and the page renders its "Club not
 * found" branch. This pins both the UI not-found surface AND the
 * underlying PostgREST wire behaviour so a future RLS loosening can't
 * silently leak private clubs + their posts/members.
 *
 * invite-token-lockdown.spec.ts already pins the token column; this is
 * the row-level membership gate.
 */

const FRIENDS_OF_JARED_ID = 'c3333333-0000-0000-0000-000000000003';

test.describe('private club — UI not-found for a non-member', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		// Belt-and-braces: ensure no membership row crept in for morgan.
		try {
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', FRIENDS_OF_JARED_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('signed-in non-member visiting a private club slug gets the not-found branch', async ({
		page
	}) => {
		// Morgan is not a member of Friends of Jared, so RLS hides the row
		// → fetchClubBySlug returns null → not-found.
		await page.goto('/clubs/friends-of-jared');

		await expect(
			page.getByRole('heading', { name: 'Club not found' })
		).toBeVisible({ timeout: 10_000 });

		// The private club's name must NOT leak into the page (no hero h1).
		await expect(
			page.getByRole('heading', { level: 1, name: 'Friends of Jared' })
		).toHaveCount(0);
		// And no member-only surface (post composer) renders.
		await expect(page.locator('.post-form textarea')).toHaveCount(0);
	});
});

test.describe('private club — PostgREST wire-level RLS', () => {
	test('signed-in non-member cannot SELECT the private club row by slug', async () => {
		const { url, anonKey } = loadSupabaseEnv();
		const client = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});
		const { error: signInErr } = await client.auth.signInWithPassword({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});
		expect(signInErr).toBeNull();

		const { data } = await client
			.from('clubs')
			.select('id, name, slug')
			.eq('id', FRIENDS_OF_JARED_ID)
			.maybeSingle();

		// RLS filters the row out for a non-member: zero rows, not an error.
		expect(data).toBeNull();
	});

	test('anonymous caller cannot SELECT the private club row', async () => {
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});

		const { data } = await anon
			.from('clubs')
			.select('id, name, slug')
			.eq('id', FRIENDS_OF_JARED_ID)
			.maybeSingle();
		expect(data).toBeNull();

		// And the private club must never appear in a broad public list.
		const { data: list } = await anon
			.from('clubs')
			.select('id, slug')
			.limit(50);
		const slugs = (list ?? []).map((r) => r.slug);
		expect(slugs).not.toContain('friends-of-jared');
	});

	test('signed-in non-member cannot read the private club posts via RLS', async () => {
		// Plant a post on the private club via service-role, then confirm a
		// non-member's authenticated read returns nothing. club_posts RLS
		// keys off club membership; a leak here would expose private feed
		// content to anyone who guessed the club id.
		const admin = getAdminClient();
		const body = `e2e-private-post ${Date.now()}`;
		const { data: planted, error: insErr } = await admin
			.from('club_posts')
			.insert({
				club_id: FRIENDS_OF_JARED_ID,
				author_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
				body
			})
			.select('id')
			.single();
		if (insErr) throw insErr;
		const postId = (planted as { id: string }).id;

		try {
			const { url, anonKey } = loadSupabaseEnv();
			const client = createClient(url, anonKey, {
				auth: { persistSession: false, autoRefreshToken: false }
			});
			await client.auth.signInWithPassword({
				email: USER_C_PRO.email,
				password: USER_C_PRO.password
			});

			const { data } = await client
				.from('club_posts')
				.select('id, body')
				.eq('club_id', FRIENDS_OF_JARED_ID);
			// Non-member sees no rows of the private club's feed.
			expect((data ?? []).map((r) => r.id)).not.toContain(postId);
		} finally {
			await admin.from('club_posts').delete().eq('id', postId);
		}
	});
});
