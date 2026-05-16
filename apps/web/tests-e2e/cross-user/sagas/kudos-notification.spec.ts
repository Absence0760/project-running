import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../../fixtures/seeded-data';
import {
	clearNotifications,
	insertKudos
} from '../../fixtures/simulate';
import { getAdminClient } from '../../fixtures/local-supabase';
import { USER_A, USER_B } from '../../fixtures/users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * Cross-user kudos saga: USER_B (alex) gives kudos to USER_A's public
 * run via the UI. The `notify_run_kudos` trigger fires and inserts a
 * notification row for USER_A. USER_A then opens the inbox at
 * /u/[me]?tab=notifications and confirms the row + bell badge + the
 * click-through deep link.
 *
 * The bell-popover-only assertion lives in cross-user/notifications.spec.ts;
 * this saga pins the fuller end-to-end: write through the UI, inbox row,
 * navigation on click, mark-all-read clears.
 */

const KUDOS_VERB = /Alex Chen gave kudos to your 9\.0 km/;

test.describe('saga: alex kudos runner → runner inbox row + bell + click-through', () => {
	test.describe.configure({ timeout: 90_000 });

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		// Defence in depth: if a prior failed run left alex's kudos on
		// the pinned run, the UI click would rescind it instead of giving
		// fresh kudos, and no trigger would fire.
		await getAdminClient()
			.from('run_kudos')
			.delete()
			.eq('run_id', RUNNER_PUBLIC_RUN_ID)
			.eq('user_id', USER_B.id);
	});

	test.afterEach(async () => {
		await getAdminClient()
			.from('run_kudos')
			.delete()
			.eq('run_id', RUNNER_PUBLIC_RUN_ID)
			.eq('user_id', USER_B.id);
		await clearNotifications(USER_A.id);
	});

	test('inbox shows the row, badge flips to 1, row click navigates to the run + auto-marks read (clears badge)', async ({
		browser
	}) => {
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		// Dismiss the consent banner up-front in each context — without
		// it the fixed-position dialog intercepts pointer events on the
		// kudos button + inbox rows we click below.
		await ctxAlex.addInitScript(setConsentAccepted);
		await ctxRunner.addInitScript(setConsentAccepted);
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

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
			await expect(kudosBtn).not.toHaveClass(/given/);
			await kudosBtn.click();
			await expect(kudosBtn).toHaveClass(/given/, { timeout: 10_000 });

			await runner.goto(`/u/${USER_A.id}?tab=notifications`);
			await expect(runner.getByRole('heading', { level: 1 })).toBeVisible({
				timeout: 10_000
			});

			const row = runner
				.locator('.item-wrap')
				.filter({ hasText: KUDOS_VERB });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row).toHaveClass(/unread/);

			const badge = runner.locator('.bell-wrap .badge');
			await expect(badge).toBeVisible({ timeout: 5_000 });
			await expect(badge).toHaveText('1');

			await row.locator('.item-main').click();
			await runner.waitForURL(`**/runs/${RUNNER_PUBLIC_RUN_ID}`, {
				timeout: 10_000
			});

			// Clicking the row called markNotificationRead under the hood
			// (see NotificationsList.svelte open()) — back on the inbox
			// the row is now read and the bell badge has cleared. The
			// Mark-all-read button only renders while unread items exist
			// so we don't reuse the inbox test's bulk-clear assertion
			// here; instead pin the per-row read transition.
			await runner.goto(`/u/${USER_A.id}?tab=notifications`);
			await expect(runner.locator('.item-wrap').first()).toBeVisible({
				timeout: 10_000
			});
			await expect(runner.locator('.item-wrap.unread')).toHaveCount(0);
			await expect(runner.locator('.bell-wrap .badge')).toHaveCount(0);
		} finally {
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});

	test('service-role kudos plant still produces an inbox row (trigger-level coverage)', async ({
		browser
	}) => {
		// Companion to the UI path above: pins the trigger itself in
		// isolation, so a regression where the UI write path stops hitting
		// run_kudos (e.g. an RPC shim added between the client and the
		// table) is still distinguishable from a regression in the
		// trigger function. Same assertion surface — inbox row + verb.
		await insertKudos(RUNNER_PUBLIC_RUN_ID, USER_B.id);

		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		await ctxRunner.addInitScript(setConsentAccepted);
		const runner = await ctxRunner.newPage();
		try {
			await runner.goto(`/u/${USER_A.id}?tab=notifications`);
			const row = runner
				.locator('.item-wrap')
				.filter({ hasText: KUDOS_VERB });
			await expect(row).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctxRunner.close();
		}
	});
});
