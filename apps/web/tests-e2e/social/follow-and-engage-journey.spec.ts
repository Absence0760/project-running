import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Social cross-surface journey — discover → follow → feed → engage →
 * unfollow, walked end-to-end as one continuous flow rather than the
 * per-slice contracts the focused specs pin.
 *
 * The focused specs each test one seam:
 *   - people-follow.spec.ts / people.spec.ts → the People-tab follow
 *     toggle (optimistic flip, rollback, DB persistence).
 *   - feed-engagement.spec.ts → the feed kudos pill + comment count.
 *   - feed.spec.ts → the feed window / visibility predicate.
 * This one chains all of them through a SINGLE actor and a SINGLE
 * target so a break anywhere in the discover→follow→feed→engage→
 * unfollow pipeline (the resolveFollowedAuthorIds → feed seam, the
 * feed→share-run engagement seam, the unfollow→feed-removal seam)
 * surfaces as one failing journey.
 *
 * The journey:
 *   1. Alpha opens /social People, searches Bravo by name, opens Bravo's
 *      profile /u/[id] (Follow button reads "Follow", not "Following").
 *   2. Alpha follows Bravo from the profile → button flips to Following,
 *      follower count increments; the user_follows edge lands server-side.
 *   3. Alpha opens /social Feed → Bravo's planted public run surfaces
 *      (the feed is follow-scoped, so it appears only because of step 2).
 *   4. Alpha engages: gives kudos on the feed card (pill flips to given,
 *      count → 1, persisted), then opens the run's public share page and
 *      posts a comment (RunSocial composer). The feed card's comment
 *      count then reads 1.
 *   5. Alpha unfollows Bravo from the profile → button reverts to Follow,
 *      follower count decrements, the edge is gone server-side.
 *   6. The feed is follow-scoped, so Bravo's run no longer appears after
 *      the unfollow.
 *
 * SEEDED-vs-SAGA: the seed wires runner→alex, runner→morgan, and
 * alex→runner (seed.sql:1048). So USER_A already follows BOTH seeded
 * candidates — there is no seeded user USER_A doesn't already follow, and
 * a "clean follow target" can't be carved out of the seed without mutating
 * (then having to restore) the shared follow graph that the other social
 * specs depend on. So this journey mints two EPHEMERAL saga users — Alpha
 * (the actor) and Bravo (the target) — with unique display names. Bravo
 * gets a fresh PUBLIC run via insertRun. The follow graph between them
 * starts empty, the names are unambiguous for search, and deleteSagaUsers
 * CASCADE-cleans the follow edge + kudos + comment + run on teardown, so
 * no shared-seed state is touched.
 *
 * NB: the feed/people/profile surfaces hold an open Supabase realtime
 * socket — never waitForLoadState('networkidle') here; rely on
 * auto-waiting assertions. RunSocial (/share/run) is a one-shot load and
 * the only surface a non-owner can comment on (/runs/[id] is owner-scoped
 * via fetchRunById, so a follower viewing it 404s — the public-run social
 * surface is /share/run/[id], which mounts the same RunSocial composer the
 * feed modal renders).
 */

test.describe('social journey — discover → follow → feed → engage → unfollow', () => {
	// Saga setup signs in two ephemeral users via the UI, then the journey
	// walks discover → follow → feed → kudos → comment → unfollow across two
	// surfaces — well past the 30 s default. Match the saga convention used by
	// every spec under cross-user/sagas/.
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];
	let alpha: SagaUser;
	let bravo: SagaUser;
	let runId: string | null = null;
	let runTitle: string;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`FollowSaga Alpha ${stamp}`, `FollowSaga Bravo ${stamp}`],
		});
		[alpha, bravo] = users;

		// A fresh public run for Bravo, inside the 14-day feed window, with
		// a unique title so the feed card is addressable among any other
		// entries and the share page renders it.
		runTitle = `E2E follow-journey ${Date.now()}`;
		runId = await insertRun({
			user_id: bravo.id,
			started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
			distance_m: 9_000,
			duration_s: 2_700,
			is_public: true,
			metadata: { activity_type: 'run', title: runTitle },
		});
	});

	test.afterAll(async () => {
		// deleteSagaUsers CASCADE-strips the run, the follow edge, kudos,
		// and comments along with the auth.users rows — but the run is
		// owned by Bravo (a saga user), so it goes with him. Nothing here
		// touches seeded state.
		if (users) await deleteSagaUsers(users);
	});

	test('Alpha discovers Bravo, follows, kudos + comments his run, then unfollows and it leaves the feed', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: alpha.storageStatePath });
		// Pre-accept the GDPR cookie banner so it doesn't float over the
		// surface and intercept pointer events on the follow / kudos /
		// comment affordances. The saga sign-in captures auth state but not
		// this consent choice, so inject it before the first navigation (the
		// consent module reads localStorage once on import) — same pattern as
		// helpers.signIn.
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		const admin = getAdminClient();
		try {
			// ── 1. Discover Bravo via the People tab, open his profile ──
			await page.goto('/social?tab=people');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Social' })
			).toBeVisible({ timeout: 10_000 });

			const search = page.getByPlaceholder('Search runners by name');
			await expect(search).toBeVisible({ timeout: 10_000 });
			await search.fill(bravo.displayName);

			const bravoRow = page.locator('.person-row', { hasText: bravo.displayName });
			await expect(bravoRow).toBeVisible({ timeout: 5_000 });
			// The row toggle starts at Follow (no pre-existing edge).
			await expect(bravoRow.locator('.follow-btn')).toContainText('Follow');
			await expect(bravoRow.locator('.follow-btn')).not.toContainText('Following');

			// Open Bravo's public profile. The whole .person-row IS the
			// <a href="/u/{id}"> (SocialPeople.svelte), with the follow button
			// nested inside it — click the name span (a non-button child of
			// the link) to navigate without hitting the follow toggle.
			await bravoRow.locator('.person-name').click();
			await page.waitForURL(new RegExp(`/u/${bravo.id}$`), { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { level: 1, name: bravo.displayName })
			).toBeVisible({ timeout: 10_000 });

			// ── 2. Follow from the profile header ───────────────────────
			const followBtn = page.locator('.btn-follow');
			await expect(followBtn).toContainText('Follow');
			await expect(followBtn).not.toContainText('Following');
			// The follower count is the second count button (Runs · Followers
			// · Following). Bravo starts with zero followers.
			const followerCount = page
				.locator('.count', { hasText: 'Followers' })
				.locator('.count-num');
			await expect(followerCount).toHaveText('0');

			await followBtn.click();
			// Optimistic flip → Following + count increments to 1.
			await expect(followBtn).toContainText('Following', { timeout: 5_000 });
			await expect(followerCount).toHaveText('1', { timeout: 5_000 });

			// The edge must land server-side before the follow-scoped feed
			// can read it.
			await expect(async () => {
				const { data } = await admin
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', alpha.id)
					.eq('followee_id', bravo.id)
					.maybeSingle();
				expect(data).toBeTruthy();
			}).toPass({ timeout: 5_000 });

			// ── 3. Bravo's run surfaces in Alpha's feed ─────────────────
			await page.goto('/social?tab=feed');
			const card = page.locator('article.entry').filter({ hasText: runTitle });
			await expect(card).toBeVisible({ timeout: 10_000 });

			// ── 4a. Give kudos on the feed card ─────────────────────────
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
					.eq('user_id', alpha.id);
				expect(count).toBe(1);
			}).toPass({ timeout: 5_000 });

			// ── 4b. Comment on the run via its public share page ────────
			// /runs/[id] is owner-scoped (fetchRunById), so a follower must
			// use the public share surface, which mounts the same RunSocial
			// composer the feed modal renders.
			const commentBody = `Great effort! ${Date.now()}`;
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
					.eq('author_id', alpha.id);
				expect(count).toBe(1);
			}).toPass({ timeout: 5_000 });

			// Back on the feed the card's comment count now reads 1.
			await page.goto('/social?tab=feed');
			const cardAgain = page.locator('article.entry').filter({ hasText: runTitle });
			await expect(cardAgain.locator('.comment-pill')).toContainText('1', {
				timeout: 10_000,
			});
			// The kudos give also survived the round-trip (proves it wasn't a
			// paint-only flip).
			await expect(cardAgain.locator('.kudos-pill')).toHaveClass(/given/, {
				timeout: 10_000,
			});
			await expect(cardAgain.locator('.kudos-pill')).toContainText('1');

			// ── 5. Unfollow from the profile ────────────────────────────
			await page.goto(`/u/${bravo.id}`);
			const unfollowBtn = page.locator('.btn-follow');
			await expect(unfollowBtn).toContainText('Following', { timeout: 10_000 });
			const followerCountAfter = page
				.locator('.count', { hasText: 'Followers' })
				.locator('.count-num');
			await expect(followerCountAfter).toHaveText('1');

			await unfollowBtn.click();
			await expect(unfollowBtn).toContainText('Follow', { timeout: 5_000 });
			await expect(unfollowBtn).not.toContainText('Following');
			await expect(followerCountAfter).toHaveText('0', { timeout: 5_000 });

			// The edge is gone server-side.
			await expect(async () => {
				const { data } = await admin
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', alpha.id)
					.eq('followee_id', bravo.id)
					.maybeSingle();
				expect(data).toBeNull();
			}).toPass({ timeout: 5_000 });

			// ── 6. The follow-scoped feed drops Bravo's run ─────────────
			await page.goto('/social?tab=feed');
			await expect(page.getByText(runTitle)).toHaveCount(0, { timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});
});
