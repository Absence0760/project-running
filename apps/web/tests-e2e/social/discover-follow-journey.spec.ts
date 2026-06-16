import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const SAGA_PASSWORD = 'sagatest123';

/**
 * Social cross-surface journey #2 — a SEEDED actor discovering a runner
 * they have never followed, walked end-to-end:
 *   search a not-yet-followed stranger → follow them from the People row
 *   → their public run lands in the follow-scoped feed → engage (kudos +
 *   comment) → backend cross-check.
 *
 * This is deliberately a different shape from
 * follow-and-engage-journey.spec.ts, which mints BOTH the actor (Alpha)
 * AND the target (Bravo) as ephemeral saga users with an empty follow
 * graph between them. Here the actor is the SEEDED USER_A (runner@), so
 * the journey exercises the real-account discovery path: a logged-in
 * seeded user finds someone outside their follow graph via the People
 * name search and pulls them into their feed for the first time.
 *
 * Why USER_A needs a freshly-minted stranger as the target: the seed
 * wires runner→alex (USER_B) and runner→morgan (USER_C) as MUTUAL follow
 * edges (seed.sql). So there is no seeded user USER_A doesn't already
 * follow — a "clean discovery target" can't be carved out of the seed
 * without unfollowing (then having to restore) a shared edge the other
 * social specs depend on. So the target is ONE ephemeral stranger user
 * (with a unique display name and a fresh PUBLIC run) minted directly
 * via the admin client — NOT through createSagaUsers, because that
 * fixture also drives a nested-browser UI sign-in to capture a
 * storageState file, and this journey never acts AS the stranger (USER_A
 * does every action: search, follow, kudos, comment). The stranger only
 * needs to EXIST as a profile with a recent public run, so the expensive
 * UI sign-in is pure waste and was blowing the beforeAll hook budget.
 *
 * The follow graph between USER_A and the stranger starts empty;
 * deleting the stranger's auth.users row on teardown CASCADE-cleans the
 * follow edge USER_A made + USER_A's kudos + comment + the run, so no
 * shared-seed follow edge is ever touched. The only edge that exists
 * during the test is the one this journey creates, and it dies with the
 * stranger.
 *
 * The journey:
 *   1. USER_A opens /social People, searches the Stranger by name. The
 *      row's follow toggle reads "Follow" (no pre-existing edge) — proof
 *      this is a genuine discovery, not a re-follow.
 *   2. USER_A follows from the People row (the .follow-btn toggle); it
 *      flips to "Following" optimistically and the user_follows edge
 *      lands server-side.
 *   3. USER_A opens /social Feed → the Stranger's planted public run now
 *      surfaces (the feed is follow-scoped, so it appears ONLY because of
 *      step 2).
 *   4. USER_A engages: kudos on the feed card (pill flips to given,
 *      count → 1, persisted), then opens the run's public share page and
 *      posts a comment (RunSocial composer). The feed card's comment
 *      count then reads 1.
 *
 * NB: the feed/people surfaces hold an open Supabase realtime socket —
 * never waitForLoadState('networkidle') on them; rely on auto-waiting
 * assertions. RunSocial (/share/run) is the only surface a non-owner can
 * comment on (/runs/[id] is owner-scoped via fetchRunById, so a follower
 * viewing it 404s — the public-run social surface is /share/run/[id],
 * which mounts the same RunSocial composer the feed modal renders).
 */

test.describe('social journey — seeded actor discovers a stranger, follows + engages', () => {
	// The journey walks search → follow → feed → kudos → comment across two
	// surfaces — past the 30 s default. (The beforeAll itself is now just a
	// couple of fast admin calls, but the body is long.)
	test.describe.configure({ timeout: 90_000 });
	test.use({ storageState: USER_A.storageStatePath });

	let strangerId: string;
	let strangerName: string;
	let runId: string | null = null;
	let runTitle: string;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const stamp = Date.now().toString(36);
		// A unique display name so the People search is unambiguous and the
		// search_user_profiles RPC returns exactly this row.
		strangerName = `DiscoverSaga Stranger ${stamp}`;

		// Mint the stranger directly via the admin client — auth.users row +
		// a user_profiles row. No UI sign-in / storageState: USER_A is the
		// only actor in this journey, so the stranger never needs a session.
		const { data, error } = await admin.auth.admin.createUser({
			email: `saga-${stamp}@test.com`,
			password: SAGA_PASSWORD,
			email_confirm: true,
		});
		if (error || !data?.user) {
			throw new Error(
				`discover-follow-journey: failed to create stranger: ${error?.message ?? 'no user returned'}`
			);
		}
		strangerId = data.user.id;

		// onboarded_at set so the stranger isn't a redirect target for the
		// /onboarding gate; unique display_name keeps the People search exact.
		const { error: profileError } = await admin.from('user_profiles').upsert({
			id: strangerId,
			display_name: strangerName,
			preferred_unit: 'km',
			subscription_tier: 'free',
			onboarded_at: new Date().toISOString(),
		});
		if (profileError) {
			throw new Error(
				`discover-follow-journey: failed to upsert stranger profile: ${profileError.message}`
			);
		}

		// A fresh public run for the stranger, inside the 14-day feed window,
		// with a unique title so the feed card is addressable among any other
		// entries and the share page renders it.
		runTitle = `E2E discover-journey ${Date.now()}`;
		runId = await insertRun({
			user_id: strangerId,
			started_at: new Date(Date.now() - 45 * 60 * 1000).toISOString(),
			distance_m: 8_000,
			duration_s: 2_400,
			is_public: true,
			metadata: { activity_type: 'run', title: runTitle },
		});
	});

	test.afterAll(async () => {
		// Deleting the stranger's auth.users row CASCADE-strips the run, the
		// follow edge USER_A created, USER_A's kudos, and USER_A's comment —
		// so nothing seeded (incl. USER_A's seed follow edges to alex/morgan)
		// is touched. The follow edge that existed during the test pointed AT
		// the stranger, so it dies with him.
		if (strangerId) {
			const admin = getAdminClient();
			try {
				await admin.auth.admin.deleteUser(strangerId);
			} catch (e) {
				console.warn(`discover-follow-journey: failed to delete stranger ${strangerId}:`, e);
			}
		}
	});

	test('USER_A searches a not-yet-followed runner, follows, then kudos + comments their public run', async ({
		page,
	}) => {
		const admin = getAdminClient();

		// Pre-accept the GDPR cookie banner so it doesn't float over the
		// People row and intercept pointer events on the follow / kudos /
		// comment affordances. Inject before the first navigation (the
		// consent module reads localStorage once on import).
		await page.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});

		// Sanity: USER_A does NOT already follow the Stranger going in
		// (proves the search result's "Follow" state is real, not stale).
		await test.step('precondition: no pre-existing follow edge', async () => {
			const { data } = await admin
				.from('user_follows')
				.select('follower_id')
				.eq('follower_id', USER_A.id)
				.eq('followee_id', strangerId)
				.maybeSingle();
			expect(data).toBeNull();
		});

		// ── 1. Discover the Stranger via the People-tab name search ──
		await test.step('USER_A finds the Stranger in People search', async () => {
			await page.goto('/social?tab=people');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Social' })
			).toBeVisible({ timeout: 10_000 });

			// The People search input (SocialPeople.svelte) — match by the
			// stable placeholder text the en catalogue pins.
			const search = page.getByPlaceholder('Search runners by name');
			await expect(search).toBeVisible({ timeout: 10_000 });
			await search.fill(strangerName);

			const strangerRow = page.locator('.person-row', {
				hasText: strangerName,
			});
			await expect(strangerRow).toBeVisible({ timeout: 5_000 });
			// The row toggle starts at Follow (no pre-existing edge) — discovery,
			// not a re-follow.
			await expect(strangerRow.locator('.follow-btn')).toContainText('Follow');
			await expect(strangerRow.locator('.follow-btn')).not.toContainText('Following');
		});

		// ── 2. Follow from the People row ───────────────────────────
		await test.step('USER_A follows the Stranger from the People row', async () => {
			const strangerRow = page.locator('.person-row', {
				hasText: strangerName,
			});
			const followBtn = strangerRow.locator('.follow-btn');
			await followBtn.click();
			// Optimistic flip → Following.
			await expect(followBtn).toContainText('Following', { timeout: 5_000 });

			// The edge must land server-side before the follow-scoped feed
			// can read it.
			await expect(async () => {
				const { data } = await admin
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', USER_A.id)
					.eq('followee_id', strangerId)
					.maybeSingle();
				expect(data).toBeTruthy();
			}).toPass({ timeout: 5_000 });
		});

		// ── 3. The Stranger's run surfaces in USER_A's feed ─────────
		await test.step("the Stranger's public run appears in the follow-scoped feed", async () => {
			await page.goto('/social?tab=feed');
			const card = page.locator('article.entry').filter({ hasText: runTitle });
			await expect(card).toBeVisible({ timeout: 10_000 });
		});

		// ── 4a. Give kudos on the feed card ─────────────────────────
		await test.step('USER_A gives kudos on the feed card', async () => {
			const card = page.locator('article.entry').filter({ hasText: runTitle });
			const pill = card.locator('.kudos-pill');
			await expect(pill).not.toHaveClass(/given/);
			await expect(pill).toContainText('0');
			await pill.click();
			await expect(pill).toHaveClass(/given/, { timeout: 5_000 });
			await expect(pill).toContainText('1');

			// The optimistic flip must reflect a real run_kudos write.
			await expect(async () => {
				const { count } = await admin
					.from('run_kudos')
					.select('*', { count: 'exact', head: true })
					.eq('run_id', runId!)
					.eq('user_id', USER_A.id);
				expect(count).toBe(1);
			}).toPass({ timeout: 5_000 });
		});

		// ── 4b. Comment on the run via its public share page ────────
		// /runs/[id] is owner-scoped (fetchRunById), so a follower must
		// use the public share surface, which mounts the same RunSocial
		// composer the feed modal renders.
		const commentBody = `Strong run! ${Date.now()}`;
		await test.step('USER_A comments on the run via /share/run', async () => {
			await page.goto(`/share/run/${runId}`);
			// Target the composer textarea by its container class rather than
			// the i18n placeholder text (RunSocial.svelte form.composer) — the
			// placeholder is locale-dependent and the class is stable.
			const composer = page.locator('.composer textarea');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(commentBody);
			await page.getByRole('button', { name: 'Post', exact: true }).click();
			// The posted comment renders back in the thread.
			await expect(page.getByText(commentBody)).toBeVisible({ timeout: 10_000 });

			// And it persisted server-side.
			await expect(async () => {
				const { count } = await admin
					.from('run_comments')
					.select('*', { count: 'exact', head: true })
					.eq('run_id', runId!)
					.eq('author_id', USER_A.id);
				expect(count).toBe(1);
			}).toPass({ timeout: 5_000 });
		});

		// ── 5. The engagement survives a round-trip back to the feed ─
		await test.step('the feed card reflects the kudos + comment after a reload', async () => {
			await page.goto('/social?tab=feed');
			const cardAgain = page.locator('article.entry').filter({ hasText: runTitle });
			await expect(cardAgain.locator('.comment-pill')).toContainText('1', {
				timeout: 10_000,
			});
			// The kudos give also survived (proves it wasn't a paint-only flip).
			await expect(cardAgain.locator('.kudos-pill')).toHaveClass(/given/, {
				timeout: 10_000,
			});
			await expect(cardAgain.locator('.kudos-pill')).toContainText('1');
		});
	});
});
