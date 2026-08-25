import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /routes/[id] — in-app "Send a route to a follower" (route_direct_share.md v1).
 *
 * v1 sends the public /share/route/[id] URL as a plain DM body on the existing
 * direct_messages rail — no schema change, no typed attachment (that is v2).
 *
 * Seed follow graph, which the picker's union is built on:
 *   USER_A <-> USER_B (Alex Chen)   mutual
 *   USER_A  -> USER_C (Morgan Lee)  one-way; Morgan does not follow back
 * Both are DM-eligible under the direct_messages INSERT policy, which admits a
 * follow edge in either direction.
 */

const SHARE_PATH = `/share/route/${RUNNER_PUBLIC_ROUTE_ID}`;

async function clearSentDms() {
	await getAdminClient().from('direct_messages').delete().eq('sender_id', USER_A.id);
}

test.describe('/routes/[id] — send to a follower', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await getAdminClient()
			.from('routes')
			.update({ is_public: true })
			.eq('id', RUNNER_PUBLIC_ROUTE_ID);
		await clearSentDms();
	});

	test.afterEach(async () => {
		await clearSentDms();
	});

	test('sends the share link as a DM and the recipient opens it in their thread', async ({
		page,
		browser
	}) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });

		// The union of both follow directions, name-ordered.
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toBeVisible({
			timeout: 10_000
		});
		await dialog.getByRole('button', { name: /Alex Chen/ }).click();

		await expect(page.getByTestId('send-route-sent')).toContainText('Alex Chen');

		// The row that actually landed carries the public share URL as its body.
		const { data } = await getAdminClient()
			.from('direct_messages')
			.select('body, recipient_id')
			.eq('sender_id', USER_A.id);
		expect(data).toHaveLength(1);
		expect(data?.[0].recipient_id).toBe(USER_B.id);
		expect(data?.[0].body).toContain(SHARE_PATH);

		// And the recipient can open it from their own conversation.
		const recipient = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const recipientPage = await recipient.newPage();
			await recipientPage.goto(`/messages/${USER_A.id}`);
			const bubble = recipientPage.locator('.bubble .text', { hasText: SHARE_PATH });
			await expect(bubble).toBeVisible({ timeout: 10_000 });
		} finally {
			await recipient.close();
		}
	});

	test('offers a runner the sender follows who does not follow back', async ({ page }) => {
		// The picker is the DM-eligible set, not the follower list: Morgan follows
		// nobody, so a followers-only picker would hide a send RLS accepts.
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await dialog.getByTestId('send-route-search').fill('morgan');
		await expect(dialog.getByRole('button', { name: /Morgan Lee/ })).toBeVisible({
			timeout: 10_000
		});
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toHaveCount(0);

		await dialog.getByRole('button', { name: /Morgan Lee/ }).click();
		await expect(page.getByTestId('send-route-sent')).toContainText('Morgan Lee');

		const { data } = await getAdminClient()
			.from('direct_messages')
			.select('recipient_id')
			.eq('sender_id', USER_A.id);
		expect(data?.[0].recipient_id).toBe(USER_C_PRO.id);
	});

	test('a private route confirms the public flip before the picker opens', async ({ page }) => {
		// Sending a link to one person must not silently widen the route's
		// exposure: it goes through the same confirm the copy-link share does.
		const admin = getAdminClient();
		await admin.from('routes').update({ is_public: false }).eq('id', RUNNER_PUBLIC_ROUTE_ID);

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		const confirm = page.locator('[data-testid="share-confirm-dialog"]');
		await page.getByTestId('route-send-dm-btn').click();
		await expect(confirm).toBeVisible();
		await expect(page.getByTestId('send-route-dialog')).toBeHidden();

		await confirm.getByRole('button', { name: 'Cancel' }).click();
		await expect(page.getByTestId('send-route-dialog')).toBeHidden();
		{
			const { data } = await admin
				.from('routes')
				.select('is_public')
				.eq('id', RUNNER_PUBLIC_ROUTE_ID)
				.single();
			expect(data?.is_public).toBe(false);
		}

		// Confirming flips it public and then opens the picker.
		await page.getByTestId('route-send-dm-btn').click();
		await confirm.getByRole('button', { name: 'Make public & share' }).click();
		await expect(page.getByTestId('send-route-dialog')).toBeVisible({ timeout: 10_000 });
		{
			const { data } = await admin
				.from('routes')
				.select('is_public')
				.eq('id', RUNNER_PUBLIC_ROUTE_ID)
				.single();
			expect(data?.is_public).toBe(true);
		}
	});

	test('a failed recipient load surfaces a retry, not an empty picker', async ({ page }) => {
		// "Nobody to send to" and "we could not find out" are different answers;
		// only one of them is actionable, and the honest one must not be the
		// one that disappears.
		let failedOnce = false;
		await page.route('**/rest/v1/user_follows*', async (route) => {
			if (!failedOnce) {
				failedOnce = true;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated transient failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		const loadError = dialog.getByTestId('send-route-load-error');
		await expect(loadError).toBeVisible({ timeout: 10_000 });
		await expect(dialog.getByText("You don't follow anyone yet", { exact: false })).toHaveCount(0);

		await loadError.getByRole('button', { name: 'Retry' }).click();
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toBeVisible({
			timeout: 10_000
		});
	});

	test('a refused send says so instead of reporting success', async ({ page }) => {
		await page.route('**/rest/v1/direct_messages*', async (route) => {
			if (route.request().method() !== 'POST') {
				await route.continue();
				return;
			}
			await route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({ code: '42501', message: 'permission denied' })
			});
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await dialog.getByRole('button', { name: /Alex Chen/ }).click();

		await expect(dialog.getByTestId('send-route-error')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('send-route-sent')).toHaveCount(0);
	});
});
