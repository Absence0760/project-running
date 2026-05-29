import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	clearNotifications,
	deleteRun,
	insertComment,
	insertKudos,
	insertRun
} from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

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
