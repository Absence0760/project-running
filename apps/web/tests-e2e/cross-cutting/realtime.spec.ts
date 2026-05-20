import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

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

	test('live spectator: INSERT into live_run_pings pushes to a subscribed /live/[id] page', async ({
		page
	}) => {
		// The /live/[id] page is the most user-visible realtime surface
		// (spectators of an in-progress run). Pin the round-trip end-
		// to-end: hydrate from one pre-planted ping → subscribe via
		// supabase.channel → INSERT a second ping via service-role →
		// assert the distance text CHANGES (without a reload) and the
		// LIVE badge surfaces. A regression in any link (channel config,
		// publication on live_run_pings, RLS on the spectator subscriber,
		// or the pushPing handler) would let the run go stale on every
		// spectator's screen.
		//
		// We assert text-changed rather than a specific km/mi value: the
		// page's formatDistance picks up from a reactive `unit` signal,
		// and an anon (or fresh) auth context can land on either side of
		// 'km' / 'mi' depending on the auth-store's profile-load timing.
		// What we *actually* care about is the realtime push, not the
		// format.
		const MELBOURNE_OOZ_A = { lat: -37.816, lng: 144.97 };
		const MELBOURNE_OOZ_B = { lat: -37.82, lng: 144.975 };
		const startedAt = new Date(Date.now() - 2 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [{ ...MELBOURNE_OOZ_A, distance_m: 1_000, elapsed_s: 300 }]
			});

			await page.goto(`/live/${runId}`);

			// Snapshot the hydrated state — first stat must be non-empty
			// (some unit-formatted distance from the 1 km ping). The
			// LIVE badge must already be active before we push (the
			// page flips to LIVE on the first hydrate ping per
			// hydrateBacklog → status='live').
			await expect(page.locator('.live-badge')).toContainText('LIVE', {
				timeout: 10_000
			});
			const before = await page.locator('.live-stat-value').first().textContent();
			expect(before).toBeTruthy();
			expect(before).not.toBe('--');

			// Push a fresh ping mid-session via service-role. The page
			// should pick it up via supabase.channel without reload —
			// 3200m is a 3.2× distance jump from the planted 1000m so
			// the rendered text MUST change regardless of unit.
			const admin = getAdminClient();
			const { error } = await admin.from('live_run_pings').insert({
				run_id: runId,
				user_id: USER_A.id,
				lat: MELBOURNE_OOZ_B.lat,
				lng: MELBOURNE_OOZ_B.lng,
				distance_m: 3_200,
				elapsed_s: 900,
				at: new Date().toISOString()
			});
			expect(error).toBeNull();

			// The realtime fan-out latency budget. expect.poll loops
			// until the stat text differs from the pre-push value.
			await expect
				.poll(
					async () => await page.locator('.live-stat-value').first().textContent(),
					{ timeout: 10_000 }
				)
				.not.toBe(before);
			await expect(page.locator('.live-badge')).toContainText('LIVE');
		} finally {
			await deleteRun(runId);
		}
	});

	test('multi-client fan-out: a single ping reaches every subscribed spectator', async ({
		browser
	}) => {
		// The realtime publication doesn't fan out to N=1 cleanly — it
		// has to broadcast to every subscriber that filtered for the
		// same run_id, regardless of who they're signed in as. Three
		// contexts (USER_A as the runner-watching-themselves, USER_B as
		// a follower spectator, and one anon visitor) subscribed to
		// the same /live/<id> must all observe a single new ping.
		// A regression in the postgres_changes publication's row-level
		// fan-out (e.g. accidentally filtering by user_id at the
		// publication layer) would surface here as one or two of the
		// three contexts going stale.
		const MELBOURNE_OOZ_A = { lat: -37.816, lng: 144.97 };
		const MELBOURNE_OOZ_B = { lat: -37.82, lng: 144.975 };
		const startedAt = new Date(Date.now() - 2 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});

		// Inherit the project's locale on each fresh context (en-GB so
		// the seeded user's km/mi format renders deterministically).
		// Without an explicit locale here, browser.newContext drops back
		// to the chromium default — different from the project's
		// playwright.config use.locale.
		const ctxOpts = { locale: 'en-GB', timezoneId: 'UTC' } as const;
		const runnerCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_A.storageStatePath
		});
		const followerCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_B.storageStatePath
		});
		const anonCtx = await browser.newContext({
			...ctxOpts,
			storageState: { cookies: [], origins: [] }
		});

		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [{ ...MELBOURNE_OOZ_A, distance_m: 1_000, elapsed_s: 300 }]
			});

			const pages = await Promise.all([
				runnerCtx.newPage(),
				followerCtx.newPage(),
				anonCtx.newPage()
			]);

			// All three navigate + snapshot the hydrated text (any
			// non-empty distance proves the planted ping landed). Run
			// in parallel so the channels open close-together; a
			// sequential walk would let the first one's subscription
			// settle while the others are still mid-handshake.
			const initialTexts = await Promise.all(
				pages.map(async (p) => {
					await p.goto(`/live/${runId}`);
					await expect(p.locator('.live-badge')).toContainText('LIVE', {
						timeout: 15_000
					});
					const t = await p.locator('.live-stat-value').first().textContent();
					expect(t).toBeTruthy();
					return t!;
				})
			);

			// One push reaches all three. 4500m is 4.5× the planted 1000m
			// so the rendered text MUST change regardless of unit.
			const admin = getAdminClient();
			const { error } = await admin.from('live_run_pings').insert({
				run_id: runId,
				user_id: USER_A.id,
				lat: MELBOURNE_OOZ_B.lat,
				lng: MELBOURNE_OOZ_B.lng,
				distance_m: 4_500,
				elapsed_s: 1_200,
				at: new Date().toISOString()
			});
			expect(error).toBeNull();

			await Promise.all(
				pages.map((p, i) =>
					expect
						.poll(
							async () =>
								await p.locator('.live-stat-value').first().textContent(),
							{ timeout: 10_000 }
						)
						.not.toBe(initialTexts[i])
				)
			);
		} finally {
			await runnerCtx.close();
			await followerCtx.close();
			await anonCtx.close();
			await deleteRun(runId);
		}
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
