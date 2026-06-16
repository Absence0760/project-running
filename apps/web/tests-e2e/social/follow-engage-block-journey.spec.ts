import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { clearNotifications, insertRun } from '../fixtures/simulate';

/**
 * Social cross-surface journey — the full follow → engage → block arc
 * across TWO ephemeral saga users, walked end-to-end as one story:
 *
 *   A follows B (from B's profile)
 *     → B posts a public run (planted)
 *     → B's run lands in A's follow-scoped feed
 *     → A engages: kudos on the feed card + a comment on the run's
 *       public share page
 *     → B receives both: an inbox row + a lit bell badge for each
 *     → A blocks B from B's profile (the destructive ConfirmDialog gate)
 *     → the relationship + content visibility SEVER on both sides:
 *         • the A→B follow edge is drained server-side by block_user
 *         • B's run drops out of A's feed (the feed is follow-scoped, and
 *           the edge is gone)
 *         • A can no longer kudos/comment B's run — the run_kudos /
 *           run_comments INSERT is rejected by the is_blocked_either_way
 *           RLS gate (42501), not silently dropped
 *         • B's profile is hidden from A via public_profile_by_id (the
 *           share-page unfurl path) returning empty for a blocked target
 *
 * Why this is a NEW slice and not a dup of the existing specs:
 *   - cross-user/sagas/kudos-notification.spec.ts + comment-notification
 *     pin the engagement→notification leg ON A SEEDED RUN, isolated.
 *   - cross-user/blocks.spec.ts pins the Block button's aria toggle +
 *     ConfirmDialog gate, isolated, and explicitly leaves the DB-layer
 *     "what a block severs" to pgtap (user_blocks_test.sql).
 *   - social/discover-follow-journey.spec.ts walks discover→follow→engage
 *     but STOPS at engagement — it never blocks, never severs.
 *   This spec is the first to walk the WHOLE arc as one cross-user
 *   journey and assert the sever at the UI + DB level: that the block
 *   actually unwinds the follow graph, drops the run from the feed, and
 *   fails-closed on a post-block engagement attempt. The block-severs-
 *   the-loop transition is the uncovered seam.
 *
 * Two ephemeral saga users (createSagaUsers(2)) so the whole graph —
 * follow edge, run, kudos, comment, notifications, block row — wipes
 * cleanly on teardown (deleteSagaUsers CASCADEs auth.users children;
 * user_blocks / user_follows / run_kudos / run_comments / notifications
 * all carry ON DELETE CASCADE). Each user drives its own browser
 * context loaded from its captured storageState, the established
 * two-context pattern from cross-user/sagas/*.
 *
 * NB: the feed/people surfaces hold an open Supabase realtime socket —
 * never waitForLoadState('networkidle') on them; rely on auto-waiting
 * assertions. A non-owner comments on a run via /share/run/[id] (the
 * RunSocial composer); /runs/[id] is owner-scoped (fetchRunById), so a
 * follower viewing it 404s.
 */

const BLOCK_VERB_FOLLOW = /started following you/;

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('social journey — follow → engage → block severs the loop across two users', () => {
	// The arc spans search/follow, feed, kudos, comment, two inboxes, a
	// block confirm, and the post-block sever checks across two contexts —
	// well past the 30 s default.
	test.describe.configure({ timeout: 120_000 });

	let users: SagaUser[] = [];
	let actor: SagaUser; // A — follows, engages, then blocks
	let poster: SagaUser; // B — posts the public run, receives notifications
	let runId: string | null = null;
	let runTitle: string;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`Actor Saga ${stamp}`, `Poster Saga ${stamp}`],
		});
		actor = users[0];
		poster = users[1];

		// B's fresh PUBLIC run, inside the 14-day feed window, unique title
		// so the feed card + share page are addressable.
		runTitle = `E2E follow-block journey ${Date.now()}`;
		runId = await insertRun({
			user_id: poster.id,
			started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
			distance_m: 8_000,
			duration_s: 2_400,
			is_public: true,
			metadata: { activity_type: 'run', title: runTitle },
		});

		// Deterministic notification start state for B — the bell-badge
		// count assertions need to count only what THIS journey produces.
		await clearNotifications(poster.id);
	});

	test.afterAll(async () => {
		// Deleting both auth.users rows CASCADE-strips the run + the follow
		// edge + kudos + comment + notifications + the block row. Nothing
		// seeded is touched (these users never existed before this test).
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('A follows B, kudos + comments, B is notified, then A blocks B and the relationship + content visibility sever', async ({
		browser,
	}) => {
		const admin = getAdminClient();

		const ctxActor = await browser.newContext({ storageState: actor.storageStatePath });
		const ctxPoster = await browser.newContext({ storageState: poster.storageStatePath });
		// Dismiss the consent banner up-front in each context — the fixed
		// dialog otherwise intercepts pointer events on the follow / kudos /
		// comment / block affordances.
		await ctxActor.addInitScript(setConsentAccepted);
		await ctxPoster.addInitScript(setConsentAccepted);
		const aPage = await ctxActor.newPage();
		const bPage = await ctxPoster.newPage();

		// The share/run track clip fetch isn't relevant to this journey —
		// short-circuit it so the page never blocks on the edge function.
		const stubClip = (p: typeof aPage) =>
			p.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] }),
				})
			);

		const commentBody = `Strong work! ${Date.now()}`;

		try {
			await stubClip(aPage);

			// ── precondition: no follow edge, no block between A and B ──
			await test.step('precondition: empty follow graph + no block', async () => {
				const { data: edge } = await admin
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', actor.id)
					.eq('followee_id', poster.id)
					.maybeSingle();
				expect(edge).toBeNull();
				const { data: block } = await admin
					.from('user_blocks')
					.select('blocker_id')
					.eq('blocker_id', actor.id)
					.eq('blocked_id', poster.id)
					.maybeSingle();
				expect(block).toBeNull();
			});

			// ── 1. A follows B from B's profile ────────────────────────
			await test.step('A follows B from the profile Follow toggle', async () => {
				await aPage.goto(`/u/${poster.id}`);
				const heading = aPage.getByRole('heading', { level: 1, name: poster.displayName });
				await expect(heading).toBeVisible({ timeout: 10_000 });

				const followBtn = aPage.locator('button.btn-follow');
				await expect(followBtn).toBeVisible({ timeout: 10_000 });
				// Fresh edge → the toggle reads "Follow", not "Following".
				await expect(followBtn).toHaveAttribute('aria-label', 'Follow');
				await followBtn.click();
				// Optimistic flip → Following.
				await expect(followBtn).toHaveAttribute('aria-label', 'Unfollow', { timeout: 5_000 });

				// Edge must land server-side before the follow-scoped feed reads it.
				await expect(async () => {
					const { data } = await admin
						.from('user_follows')
						.select('follower_id')
						.eq('follower_id', actor.id)
						.eq('followee_id', poster.id)
						.maybeSingle();
					expect(data).toBeTruthy();
				}).toPass({ timeout: 5_000 });
			});

			// ── 2. B's public run surfaces in A's follow-scoped feed ────
			await test.step("B's public run appears in A's feed", async () => {
				await aPage.goto('/social?tab=feed');
				const card = aPage.locator('article.entry').filter({ hasText: runTitle });
				await expect(card).toBeVisible({ timeout: 10_000 });
			});

			// ── 3a. A gives kudos on the feed card ──────────────────────
			await test.step('A gives kudos on the feed card', async () => {
				const card = aPage.locator('article.entry').filter({ hasText: runTitle });
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
						.eq('user_id', actor.id);
					expect(count).toBe(1);
				}).toPass({ timeout: 5_000 });
			});

			// ── 3b. A comments on the run via its public share page ─────
			await test.step('A comments on B\'s run via /share/run', async () => {
				await aPage.goto(`/share/run/${runId}`);
				const composer = aPage.locator('form.composer textarea');
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill(commentBody);
				await aPage.locator('form.composer button[type="submit"]').click();
				await expect(composer).toHaveValue('', { timeout: 10_000 });

				await expect(async () => {
					const { count } = await admin
						.from('run_comments')
						.select('*', { count: 'exact', head: true })
						.eq('run_id', runId!)
						.eq('author_id', actor.id);
					expect(count).toBe(1);
				}).toPass({ timeout: 5_000 });
			});

			// ── 4. B is notified — bell badge + two inbox rows ──────────
			await test.step('B sees the follow + kudos + comment notifications', async () => {
				await bPage.goto(`/u/${poster.id}?tab=notifications`);
				await expect(bPage.getByRole('heading', { level: 1 })).toBeVisible({
					timeout: 10_000,
				});

				// The follow, kudos and comment triggers all fired → three
				// fresh unread rows naming A.
				const followRow = bPage
					.locator('.item-wrap')
					.filter({ hasText: actor.displayName })
					.filter({ hasText: BLOCK_VERB_FOLLOW });
				await expect(followRow).toBeVisible({ timeout: 10_000 });
				await expect(followRow).toHaveClass(/unread/);

				const kudosRow = bPage
					.locator('.item-wrap')
					.filter({ hasText: actor.displayName })
					.filter({ hasText: /gave kudos to your/ });
				await expect(kudosRow).toBeVisible({ timeout: 10_000 });

				const commentRow = bPage
					.locator('.item-wrap')
					.filter({ hasText: actor.displayName })
					.filter({ hasText: /commented on your/ });
				await expect(commentRow).toBeVisible({ timeout: 10_000 });
				await expect(commentRow.locator('.excerpt')).toContainText(commentBody);

				// The bell badge lit — three unread.
				const badge = bPage.locator('.bell-wrap .badge');
				await expect(badge).toBeVisible({ timeout: 5_000 });
				await expect(badge).toHaveText('3');
			});

			// ── 5. A blocks B from B's profile (the ConfirmDialog gate) ──
			await test.step('A blocks B via the destructive confirm', async () => {
				await aPage.goto(`/u/${poster.id}`);
				await expect(
					aPage.getByRole('heading', { level: 1, name: poster.displayName })
				).toBeVisible({ timeout: 10_000 });

				const blockBtn = aPage.locator('button.btn-block');
				await expect(blockBtn).toBeVisible({ timeout: 10_000 });
				await expect(blockBtn).toHaveAttribute('aria-pressed', 'false');
				await blockBtn.click();

				// Block drains follows on both sides → destructive → confirm.
				const confirmBtn = aPage.getByRole('button', { name: 'Block', exact: true });
				await expect(confirmBtn).toBeVisible({ timeout: 5_000 });
				await confirmBtn.click();

				await expect(blockBtn).toHaveAttribute('aria-pressed', 'true', { timeout: 5_000 });

				// block_user persisted + drained the A→B follow edge.
				await expect(async () => {
					const { data } = await admin
						.from('user_blocks')
						.select('blocker_id')
						.eq('blocker_id', actor.id)
						.eq('blocked_id', poster.id)
						.maybeSingle();
					expect(data).toBeTruthy();
				}).toPass({ timeout: 5_000 });
			});

			// ── 6. The follow edge is gone — block subsumes unfollow ────
			await test.step('the A→B follow edge was drained by the block', async () => {
				const { data } = await admin
					.from('user_follows')
					.select('follower_id')
					.eq('follower_id', actor.id)
					.eq('followee_id', poster.id)
					.maybeSingle();
				expect(data).toBeNull();
			});

			// ── 7. B's run drops out of A's feed (follow-scoped) ────────
			await test.step("B's run no longer appears in A's feed", async () => {
				await aPage.goto('/social?tab=feed');
				// Wait for the feed surface to settle (heading present), then
				// assert the card is gone. The feed is scoped to followees; the
				// edge is drained, so the run can't surface.
				await expect(aPage.getByRole('heading', { level: 1 })).toBeVisible({
					timeout: 10_000,
				});
				await expect(
					aPage.locator('article.entry').filter({ hasText: runTitle })
				).toHaveCount(0, { timeout: 10_000 });
			});

			// ── 8. A can no longer engage — the RLS block gate fails closed ─
			await test.step('a post-block kudos write is rejected by RLS (42501)', async () => {
				// Drive the write through a REAL user JWT (anon-key client
				// signed in as A) so this exercises the actual RLS block gate,
				// not the service-role bypass. getUserClient is the fixture
				// built for exactly this — verifying RLS against a real JWT.
				//
				// Delete A's pre-block kudos via service role first, so the
				// retry is a genuine fresh INSERT (not a 23505 dup-key that
				// would mask the 42501 we're testing for).
				await admin
					.from('run_kudos')
					.delete()
					.eq('run_id', runId!)
					.eq('user_id', actor.id);

				const asActor = await getUserClient({
					email: actor.email,
					password: actor.password,
				});
				const { error } = await asActor
					.from('run_kudos')
					.insert({ run_id: runId!, user_id: actor.id });
				// is_blocked_either_way denies the INSERT → RLS check failure.
				expect(error).toBeTruthy();
				expect(error?.code).toBe('42501');

				// And no kudos row leaked in past the gate.
				const { count } = await admin
					.from('run_kudos')
					.select('*', { count: 'exact', head: true })
					.eq('run_id', runId!)
					.eq('user_id', actor.id);
				expect(count).toBe(0);
			});

			// ── 9. B's profile is hidden from A via public_profile_by_id ─
			await test.step("B's profile unfurl is hidden from A (public_profile_by_id empty)", async () => {
				// public_profile_by_id returns empty for a blocked target —
				// the share-page unfurl path. Call it as A (real-JWT client)
				// to confirm the row disappears for the blocker.
				const asActor = await getUserClient({
					email: actor.email,
					password: actor.password,
				});
				const { data } = await asActor.rpc('public_profile_by_id', { p_id: poster.id });
				expect(Array.isArray(data) ? data.length : 0).toBe(0);
			});
		} finally {
			await ctxActor.close();
			await ctxPoster.close();
		}
	});
});
