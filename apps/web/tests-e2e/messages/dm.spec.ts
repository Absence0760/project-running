import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /messages — direct messages (very-social persona #55).
 *
 * USER_A (runner) and USER_B follow each other in the seed, so the
 * follow-graph send gate is satisfied. Sends a DM and asserts it lands
 * in the conversation + the thread list. afterEach clears the test
 * messages so the seed shape is intact.
 */

test.describe('/messages — direct messages', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await getAdminClient()
			.from('direct_messages')
			.delete()
			.eq('sender_id', USER_A.id)
			.eq('recipient_id', USER_B.id);
	});

	test('sends a DM to a followed runner and it appears in the thread', async ({ page }) => {
		const body = `e2e hello ${Date.now()}`;
		await page.goto(`/messages/${USER_B.id}`);

		const composer = page.getByPlaceholder('Message…');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(body);
		await page.getByRole('button', { name: 'Send' }).click();

		// The sent message renders as a bubble in the conversation. Match the
		// body EXACTLY: the thread-list preview also contains it as "You: <body>",
		// so a substring getByText resolves to two elements (strict-mode
		// violation) once that preview has rendered.
		await expect(page.getByText(body, { exact: true })).toBeVisible({ timeout: 10_000 });

		// And the conversation shows in the thread list with a "You:" preview.
		await expect(page.locator('.thread', { hasText: /You:/ }).first()).toBeVisible();
	});

	test('a failed thread-list load surfaces a retry instead of "no conversations"', async ({
		page
	}) => {
		// Pin the unswallowed-failure contract: a transient dm_threads RPC
		// failure must render the error + Retry state, NOT the empty-inbox
		// copy (which stranded users — and flaked CI, run 28838002281 —
		// when fetchDmThreads returned [] on error). First call 500s, the
		// retry goes through.
		let failedOnce = false;
		await page.route('**/rest/v1/rpc/dm_threads*', async (route) => {
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

		await page.goto('/messages');
		const errorNote = page.locator('.threads [role="alert"]');
		await expect(errorNote).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('No conversations yet', { exact: false })).toHaveCount(0);

		await errorNote.getByRole('button', { name: 'Retry' }).click();
		// The retry hits the real RPC: either threads render or the honest
		// empty state does — the error note is gone either way.
		await expect(errorNote).toHaveCount(0, { timeout: 10_000 });
	});

	test('anon is prompted to sign in', async ({ page, context }) => {
		await context.clearCookies();
		await page.context().addInitScript(() => {
			try {
				localStorage.clear();
			} catch (_) {
				/* ignore */
			}
		});
		await page.goto('/messages');
		// Either the in-page sign-in prompt or a redirect to login.
		await expect(
			page.getByText(/Sign in to see your messages|Sign in/i).first()
		).toBeVisible({ timeout: 10_000 });
	});
});
