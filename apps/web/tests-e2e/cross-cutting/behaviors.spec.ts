import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Behaviour tests — cheap, focused checks on specific data-layer
 * actions verified at the DB layer. Sit between the surface smoke
 * tests (page mounts) and the deeper feature specs (full journeys).
 */

test.describe('engagement uniqueness via UI toggle', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex kudos+rescind on the pinned public run leaves zero rows', async ({
		page
	}) => {
		// The kudos toggle is implemented as click→insert,
		// click-again→delete. After a kudos+rescind round-trip the
		// run_kudos table must hold zero rows for that (user, run) pair.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		const btn = page.locator('.kudos-btn');
		await expect(btn).toBeVisible({ timeout: 10_000 });
		// Make sure starting state is "not given" — defensive
		// against suite-leftover state.
		if (await btn.evaluate((el) => el.classList.contains('given'))) {
			await btn.click();
			await expect(btn).not.toHaveClass(/given/);
		}
		await btn.click();
		await expect(btn).toHaveClass(/given/);
		await btn.click();
		await expect(btn).not.toHaveClass(/given/);

		const admin = getAdminClient();
		const { count } = await admin
			.from('run_kudos')
			.select('user_id', { count: 'exact', head: true })
			.eq('run_id', RUNNER_PUBLIC_RUN_ID)
			.eq('user_id', USER_B.id);
		expect(count).toBe(0);
	});
});

test.describe('settings persistence', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('display name UI edit ends up in user_profiles via the data layer', async ({
		page
	}) => {
		const admin = getAdminClient();
		const newName = `e2e-name-${Date.now()}`;
		const { data: before } = await admin
			.from('user_profiles')
			.select('display_name')
			.eq('id', USER_A.id)
			.single();
		const original = (before as { display_name: string | null }).display_name;
		try {
			await page.goto('/settings/account');
			// Display Name input is the first text input under Profile.
			// The page's onMount polls auth.user (loading=false flips
			// before fetchUser resolves) and only THEN writes
			// `displayName = auth.user.display_name`. If we .fill() before
			// that hydration completes, the late assignment clobbers our
			// input back to the original. Wait for the input to carry the
			// pre-existing display_name so we know hydration has run.
			const input = page.locator('input[type="text"]').first();
			await expect(input).toBeVisible({ timeout: 10_000 });
			await expect(input).toHaveValue(original ?? '', { timeout: 10_000 });
			await input.fill(newName);
			await page.getByRole('button', { name: /Save Profile/ }).click();

			// Backend assertion: the row really updated.
			await expect.poll(async () => {
				const { data } = await admin
					.from('user_profiles')
					.select('display_name')
					.eq('id', USER_A.id)
					.single();
				return (data as { display_name: string | null } | null)?.display_name;
			}, { timeout: 5_000 }).toBe(newName);
		} finally {
			await admin
				.from('user_profiles')
				.update({ display_name: original })
				.eq('id', USER_A.id);
		}
	});
});

test.describe('trigger fan-out — UI-driven', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a club post inserted via UI fans out a club_posts row with correct shape', async ({
		page
	}) => {
		// Sanity for the createClubPost data-layer call: a UI submit
		// must end up as a row with the right club_id, author_id,
		// body. Catches a regression that posted to the wrong table
		// or dropped the author claim.
		const admin = getAdminClient();
		const body = `e2e-behavior-post-${Date.now()}`;

		await page.goto('/clubs/sydney-run-club');
		const composer = page.locator('.post-form textarea').first();
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(body);
		await page.locator('.post-form button[type="submit"]').click();
		await expect(
			page.locator('article.post', { hasText: body })
		).toBeVisible({ timeout: 10_000 });

		const { data: rows } = await admin
			.from('club_posts')
			.select('club_id, author_id, body, parent_post_id')
			.eq('body', body);
		expect(rows?.length).toBe(1);
		const row = rows?.[0] as {
			club_id: string;
			author_id: string;
			body: string;
			parent_post_id: string | null;
		};
		expect(row.club_id).toBe('c1111111-0000-0000-0000-000000000001');
		expect(row.author_id).toBe(USER_A.id);
		expect(row.parent_post_id).toBeNull();

		// Cleanup.
		await admin.from('club_posts').delete().eq('body', body);
	});
});

test.describe('public_runs view contract', () => {
	// Verified via the anon supabase-js client (the canonical way
	// non-owner web visitors read run rows). The view should expose
	// only is_public=true rows AND should hide is_public=false rows
	// AND should NOT have the column-redaction undone by a future
	// migration. RLS bonus: even though the view is queryable by
	// anyone, the row visibility is still gated.
	test('anon public_runs query returns only is_public=true rows', async () => {
		const { getUserClient: _ } = await import('../fixtures/local-supabase');
		// Use the anon key directly (NOT signed in).
		const { createClient } = await import('@supabase/supabase-js');
		const { loadSupabaseEnv } = await import('../fixtures/local-supabase');
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});
		const { data, error } = await anon
			.from('public_runs')
			.select('id')
			.limit(50);
		expect(error).toBeNull();
		expect(data?.length).toBeGreaterThan(0);

		// Cross-check via service-role: every row in `data` is is_public.
		const admin = getAdminClient();
		const ids = (data ?? []).map((r) => (r as { id: string }).id);
		const { data: rows } = await admin
			.from('runs')
			.select('id, is_public')
			.in('id', ids);
		for (const r of rows ?? []) {
			expect((r as { is_public: boolean }).is_public).toBe(true);
		}
	});
});
