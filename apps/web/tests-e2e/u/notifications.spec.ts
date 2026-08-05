import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	clearNotifications,
	deleteClub,
	deleteRun,
	insertComment,
	insertKudos,
	insertRun
} from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /u/[me]?tab=notifications — full inbox surface.
 *
 * The cross-user/notifications.spec.ts test pins the bell badge in the
 * sidebar; this one pins the inbox page itself (NotificationsList
 * component) which renders under the Notifications tab on the
 * own-profile route. Distinct surface, distinct fetch path
 * (`fetchNotifications(100)` here vs `fetchNotifications(15)` in the
 * bell), distinct mark-all-read codepath.
 *
 * The bell test clears runner's notifications in its beforeEach so
 * we can't rely on seeded items being present. Plant a fresh run +
 * kudos + comment via service-role so the trigger fan-out gives us
 * exactly two known notifications.
 */

test.describe('/u/[me]?tab=notifications — inbox', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		// Each insert fires a notify_* trigger that creates an unread
		// notification for the run owner.
		await insertKudos(runId, USER_B.id);
		await insertComment({
			run_id: runId,
			author_id: USER_B.id,
			body: 'e2e-inbox — strong session!'
		});
	});

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('inbox renders planted notifications, Mark all read empties the Unread filter', async ({
		page
	}) => {
		await page.goto(`/u/${USER_A.id}?tab=notifications`);

		// Profile header rendered → page mounted.
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		// Notifications tab is selected via the ?tab= deep link; the
		// NotificationsList wrapper is `.wrap` from the component's
		// own scoped style. Items render as `.item-wrap`.
		const items = page.locator('.item-wrap');
		await expect(items.first()).toBeVisible({ timeout: 10_000 });
		const totalBefore = await items.count();
		expect(totalBefore).toBeGreaterThanOrEqual(2);

		// At least one item should be unread (purple background) since
		// the seed kudos/comment fire trigger inserts with read_at=null.
		const unreadBefore = await page.locator('.item-wrap.unread').count();
		expect(unreadBefore).toBeGreaterThanOrEqual(1);

		// Click "Mark all read". The button only renders while there
		// are unread items.
		await page.getByRole('button', { name: 'Mark all read' }).click();

		// Filter to Unread → should be the empty state.
		await page.getByRole('button', { name: /Unread/ }).click();
		await expect(page.locator('.empty', { hasText: "You're all caught up" }))
			.toBeVisible({ timeout: 5_000 });

		// Back to All → all items still listed (count unchanged), none
		// retain the .unread class.
		await page.getByRole('button', { name: 'All', exact: true }).click();
		await expect(items).toHaveCount(totalBefore);
		await expect(page.locator('.item-wrap.unread')).toHaveCount(0);
	});
});

/**
 * run_completed render (persona #38). The recipient here is a FOLLOWER,
 * not the run owner — so the inbox must resolve the actor's run distance
 * through `public_runs` (the bare `runs` table is owner-only SELECT since
 * migration 20260701_001). This test would fail with "Alice completed a
 * run" (no distance) if fetchNotifications read `runs` alone, which is the
 * exact RLS gap that bit the first cut of this feature.
 */
test.describe('/u/[me]?tab=notifications — run_completed render (persona #38)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await clearNotifications(USER_B.id);
		// USER_B follows USER_A so a fresh public run by A notifies B.
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_B.id)
			.eq('followee_id', USER_A.id);
		await admin
			.from('user_follows')
			.insert({ follower_id: USER_B.id, followee_id: USER_A.id });
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_B.id)
			.eq('followee_id', USER_A.id);
	});

	test('follower sees the completed-run notification WITH the run distance', async ({
		page
	}) => {
		await page.goto(`/u/${USER_B.id}?tab=notifications`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const verb = page.locator('.item-wrap .verb', { hasText: /completed a/ });
		await expect(verb.first()).toBeVisible({ timeout: 10_000 });
		// The distance must render — "completed a 5.0 km run", not the
		// distance-less "completed a run" fallback. A unit-agnostic match
		// (km or mi) so the test survives USER_B's unit preference.
		await expect(verb.first()).toHaveText(/completed a [\d.]+\s*(km|mi) run/i);
	});
});

/**
 * club_post render (persona #38). Guards the clubs join in
 * fetchNotifications (verb needs the club name, link needs the slug) and
 * the tap navigation into /clubs/[slug].
 */
test.describe('/u/[me]?tab=notifications — club_post render (persona #38)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let clubId: string | null = null;
	const clubName = 'E2E Notify Harriers';
	const clubSlug = `e2e-notify-harriers-${Date.now()}`;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await clearNotifications(USER_B.id);
		// USER_A owns the club (auto-enrolled active); USER_B is an active
		// member. A post by USER_A fans out a club_post notification to B.
		const { data: club } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: clubName,
				slug: clubSlug,
				is_public: true,
				join_policy: 'open'
			})
			.select('id')
			.single();
		clubId = (club as { id: string }).id;
		await admin
			.from('club_members')
			.insert({ club_id: clubId, user_id: USER_B.id, role: 'member', status: 'active' });
		await admin
			.from('club_posts')
			.insert({ club_id: clubId, author_id: USER_A.id, body: 'e2e weather call' });
	});

	test.afterEach(async () => {
		if (clubId) {
			try {
				await deleteClub(clubId);
			} catch (_) {
				/* best-effort — cascade clears members/posts/notifications */
			}
			clubId = null;
		}
	});

	test('member sees the club_post notification and it links to the club', async ({ page }) => {
		await page.goto(`/u/${USER_B.id}?tab=notifications`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const verb = page.locator('.item-wrap .verb', { hasText: /posted in/ });
		await expect(verb.first()).toBeVisible({ timeout: 10_000 });
		// Verb resolves the club NAME (not a bare "a club you're in"
		// fallback) — proves the clubs join in fetchNotifications worked.
		await expect(verb.first()).toHaveText(new RegExp(`posted in ${clubName}`));

		// Tapping the row navigates to the club home via the resolved slug.
		await verb.first().click();
		await expect(page).toHaveURL(new RegExp(`/clubs/${clubSlug}`));
	});
});

/**
 * Undo on the inbox dismiss (decisions § 514, round 12).
 *
 * A notification is a system-minted row the user cannot re-create, so a
 * stray tap on Dismiss was unrecoverable. It now goes through the
 * deferred-commit queue: the row leaves the list at once, the DELETE is
 * held for the undo window, and Undo cancels it — so the backend row must
 * still be there while the offer stands.
 *
 * The group leg is the bulk case. One collapsed group is ONE intent, so it
 * takes ONE undo slot and one restore of all its rows — not N stacked
 * offers, which is why the queue's one-slot rule needed no change.
 */
test.describe('/u/[me]?tab=notifications — undo a dismiss', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 6_000,
			duration_s: 1_800,
			is_public: true
		});
	});

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('dismissing one row offers undo; Undo restores it and the server row never went', async ({
		page
	}) => {
		const admin = getAdminClient();
		await insertComment({
			run_id: runId!,
			author_id: USER_B.id,
			body: 'e2e-undo — one row'
		});

		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const items = page.locator('.item-wrap');
		await expect(items.first()).toBeVisible({ timeout: 10_000 });
		await expect(items).toHaveCount(1);

		await items.first().getByRole('button', { name: 'Dismiss' }).click();
		await expect(items).toHaveCount(0);
		await expect(page.getByTestId('undo-bar')).toBeVisible();

		await page.getByTestId('undo-action').click();
		await expect(items).toHaveCount(1, { timeout: 5_000 });

		// Asserted AFTER the undo so it cannot race the window: the delete
		// was never performed, so there is nothing for the restore to fake.
		const { count } = await admin
			.from('notifications')
			.select('*', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(count).toBe(1);
	});

	test('dismissing a collapsed group is one intent: one undo brings every row back', async ({
		page
	}) => {
		const admin = getAdminClient();
		// Two kudos on the SAME run from two actors collapse into one group
		// (same kind, same target, inside the 24 h window).
		await insertKudos(runId!, USER_B.id);
		await insertKudos(runId!, USER_C_PRO.id);

		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const groups = page.locator('.item-wrap:not(.sub)');
		await expect(groups.first()).toBeVisible({ timeout: 10_000 });
		await expect(groups).toHaveCount(1);
		await expect(groups.first()).toContainText('and 1 other');

		await groups.first().getByRole('button', { name: 'Dismiss' }).click();
		await expect(page.locator('.item-wrap')).toHaveCount(0);
		// One bar for the whole group, and it says how many rows it covers.
		const bar = page.getByTestId('undo-bar');
		await expect(bar).toBeVisible();
		await expect(bar).toContainText('2 notifications dismissed');

		await page.getByTestId('undo-action').click();
		await expect(groups).toHaveCount(1, { timeout: 5_000 });
		await expect(groups.first()).toContainText('and 1 other');

		const { count } = await admin
			.from('notifications')
			.select('*', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(count).toBe(2);
	});

	test('an untouched window expires and the held delete lands on its own', async ({ page }) => {
		const admin = getAdminClient();
		await insertComment({
			run_id: runId!,
			author_id: USER_B.id,
			body: 'e2e-undo — expiry'
		});

		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const items = page.locator('.item-wrap');
		await expect(items.first()).toBeVisible({ timeout: 10_000 });

		await items.first().getByRole('button', { name: 'Dismiss' }).click();
		await expect(page.getByTestId('undo-bar')).toBeVisible();
		// Do not hover, focus or click anything — hover/focus PAUSES the
		// window (WCAG 2.2.2), which would stall this assertion forever.
		await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 20_000 });
		await expect
			.poll(
				async () => {
					const { count } = await admin
						.from('notifications')
						.select('*', { count: 'exact', head: true })
						.eq('user_id', USER_A.id);
					return count ?? -1;
				},
				{ timeout: 10_000 }
			)
			.toBe(0);
	});
});
