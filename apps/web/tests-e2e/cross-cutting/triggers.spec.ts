import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { getAdminClient } from '../fixtures/local-supabase';
import { clearNotifications } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Database triggers, exercised through the UI and verified via
 * service-role inspection of the rows the triggers should have
 * planted. This is the seam between "the trigger is correct in SQL"
 * (pgtap can pin that) and "the canonical UI flow actually fires
 * the trigger" — a regression where the data layer drops a column,
 * uses the wrong table, or skips an insert would silently break
 * the side-effect even if the trigger itself stayed correct.
 *
 * Two triggers covered today:
 *   - `enroll_club_owner` (migration 20260416_001) — auto-inserts
 *     the creator into club_members with role='owner', status='active'
 *     when a clubs row is INSERTed.
 *   - `notify_run_kudos` (migration 20260528_001) — inserts a
 *     notifications row for the run's owner when a run_kudos row is
 *     INSERTed by anyone except the owner themselves.
 */

test.describe('database triggers via UI', () => {
	test('enroll_club_owner fires when /clubs/new submits — owner row planted', async () => {
		const admin = getAdminClient();
		// Drive the trigger via service-role club insert (the canonical
		// UI route /clubs/new also fires it). We avoid the UI here so
		// the test is fast + tightly scoped to the trigger's effect;
		// the UI-side create-club path is exercised by clubs-journey.
		const slug = `e2e-trigger-${Date.now()}`;
		const { data: club, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `e2e trigger club ${Date.now()}`,
				slug,
				description: 'e2e enroll_club_owner trigger',
				is_public: true,
				join_policy: 'open'
			})
			.select('id')
			.single();
		expect(error).toBeNull();
		const clubId = (club as { id: string }).id;

		try {
			// The trigger should have planted exactly one club_members
			// row with role='owner' status='active'. A regression that
			// drops the trigger leaves the owner without admin access
			// to their own club.
			const { data: rows } = await admin
				.from('club_members')
				.select('user_id, role, status')
				.eq('club_id', clubId);
			expect(rows?.length).toBe(1);
			expect(rows?.[0]?.user_id).toBe(USER_A.id);
			expect(rows?.[0]?.role).toBe('owner');
			expect(rows?.[0]?.status).toBe('active');
		} finally {
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});

	test('notify_run_kudos fires when alex kudos via UI — runner gets a kudos notification', async ({
		browser
	}) => {
		// Same path as cross-user/notifications.spec.ts but the
		// assertion is at the DB layer, not the bell badge. This pins
		// the SHAPE of the notifications row (kind=kudos, run_id set,
		// actor_id=alex, user_id=runner, read_at null) rather than
		// just the bell counter.
		const admin = getAdminClient();
		// Wipe runner's notifications so we can isolate the row the
		// trigger creates from this kudos action.
		await clearNotifications(USER_A.id);

		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const alex = await ctxAlex.newPage();
		try {
			await alex.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const kudosBtn = alex.locator('.kudos-btn');
			await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
			// If a prior failed run left alex's kudos in place, rescind
			// first so the click below is the "give kudos" branch.
			if (await kudosBtn.evaluate((el) => el.classList.contains('given'))) {
				await kudosBtn.click();
				await expect(kudosBtn).not.toHaveClass(/given/);
			}
			await kudosBtn.click();
			await expect(kudosBtn).toHaveClass(/given/);

			// Trigger ran on the run_kudos INSERT; runner should now
			// have a notifications row with kind='kudos'.
			// Allow a moment for the AFTER-INSERT trigger to settle —
			// it's synchronous within the txn but the supabase-js
			// optimistic ack returns before we read.
			await expect.poll(async () => {
				const { data } = await admin
					.from('notifications')
					.select('kind, run_id, actor_id, user_id, read_at')
					.eq('user_id', USER_A.id)
					.eq('kind', 'kudos');
				return data?.length ?? 0;
			}, { timeout: 5_000 }).toBeGreaterThanOrEqual(1);

			const { data: rows } = await admin
				.from('notifications')
				.select('kind, run_id, actor_id, user_id, read_at')
				.eq('user_id', USER_A.id)
				.eq('kind', 'kudos');
			const row = rows?.[0];
			expect(row?.actor_id).toBe(USER_B.id);
			expect(row?.run_id).toBe(RUNNER_PUBLIC_RUN_ID);
			expect(row?.read_at).toBeNull();

			// Cleanup — rescind so the seed shape is preserved.
			await alex.locator('.kudos-btn').click();
			await expect(alex.locator('.kudos-btn')).not.toHaveClass(/given/);
		} finally {
			await ctxAlex.close();
		}
	});
});
