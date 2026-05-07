import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Backend boundary: Supabase Realtime + the `postgres_changes`
 * subscription on `/clubs/[slug]`. The page subscribes to INSERTs
 * on `club_posts` filtered by club_id (see subscribeRealtime in
 * /clubs/[slug]/+page.svelte) and reloads the feed on push.
 *
 * A regression that breaks any link in the chain — the channel
 * config, the Realtime publication on the table, the RLS policy
 * evaluated against the listener, or the debounce reload — would
 * surface as a feed that goes stale until the user manually
 * refreshes. This pins the round-trip end-to-end: open the club
 * page in one context, INSERT a club_posts row via service-role
 * (which bypasses RLS but still fans out through Realtime), then
 * assert the new post appears WITHOUT the test page reloading.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('realtime fan-out', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('reload after a service-role DELETE drops the post (load() picks up the new state)', async ({
		page
	}) => {
		// Realtime DELETE events on a filtered postgres_changes channel
		// require REPLICA IDENTITY FULL to surface the matched row;
		// /clubs/[slug] doesn't currently flip the table to FULL, so
		// DELETEs only land via load() on the next refresh. Pin the
		// reload-then-fetch path so a regression that broke load()
		// would surface here even though we don't pin instant
		// realtime DELETE fan-out.
		const admin = getAdminClient();
		const body = `e2e-realtime-delete ${Date.now()}`;
		const { data: planted, error } = await admin
			.from('club_posts')
			.insert({
				club_id: SYDNEY_RUN_CLUB_ID,
				author_id: USER_A.id,
				body
			})
			.select('id')
			.single();
		if (error) throw error;
		const plantedId = (planted as { id: string }).id;

		await page.goto('/clubs/sydney-run-club');
		await expect(page.locator('article.post', { hasText: body }))
			.toBeVisible({ timeout: 10_000 });

		await admin.from('club_posts').delete().eq('id', plantedId);
		await page.reload();
		await expect(page.locator('article.post', { hasText: body }))
			.toHaveCount(0, { timeout: 10_000 });
	});

	test('service-role INSERT into club_posts pushes to a subscribed /clubs/[slug] page', async ({
		page
	}) => {
		const body = `e2e-realtime ${Date.now()}`;
		const admin = getAdminClient();
		let plantedId: string | null = null;

		try {
			await page.goto('/clubs/sydney-run-club');
			// Wait for the initial fetch + the realtime subscription to
			// settle. The composer textarea is the proxy for "page
			// finished loading + realtime channel subscribed".
			await expect(page.locator('.post-form textarea').first())
				.toBeVisible({ timeout: 10_000 });

			// Snapshot the post-card count before the push so we can
			// assert a delta rather than an absolute number (the seed +
			// any leftover test posts vary).
			const before = await page.locator('article.post').count();

			// INSERT via service-role — bypasses RLS but still fires
			// the postgres_changes notification through the Realtime
			// publication.
			const { data: planted, error } = await admin
				.from('club_posts')
				.insert({
					club_id: SYDNEY_RUN_CLUB_ID,
					author_id: USER_A.id,
					body
				})
				.select('id')
				.single();
			expect(error).toBeNull();
			plantedId = (planted as { id: string }).id;

			// The page's subscribeRealtime handler debounces 250ms then
			// re-runs load(). Within a couple of seconds the new post
			// should appear in the feed without us reloading.
			await expect(
				page.locator('article.post', { hasText: body })
			).toBeVisible({ timeout: 10_000 });

			// Sanity: the post-card count went up by exactly 1.
			await expect.poll(async () => page.locator('article.post').count(), {
				timeout: 5_000
			}).toBe(before + 1);
		} finally {
			if (plantedId) {
				try {
					await admin.from('club_posts').delete().eq('id', plantedId);
				} catch (_) {
					/* best-effort */
				}
			}
		}
	});
});
