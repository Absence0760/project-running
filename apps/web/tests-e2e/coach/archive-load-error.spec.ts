import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /coach — opening a saved archive and returning to the active thread are
 * network calls that can fail on a flaky connection. They must surface a
 * visible error (like every other Supabase call in CoachChat), not
 * silently console.error and leave the user staring at a stale view.
 * Pins issue #356: viewArchive → coachChat.errorLoadArchive,
 * backToActive's loadThread → coachChat.errorLoad.
 */

const ARCHIVED_AT = '2026-05-02T12:00:00.000Z';

async function clearArchive() {
	await getAdminClient()
		.from('coach_messages')
		.delete()
		.eq('user_id', USER_A.id)
		.is('plan_id', null);
}

async function seedArchive() {
	await getAdminClient()
		.from('coach_messages')
		.insert([
			{
				user_id: USER_A.id,
				plan_id: null,
				role: 'user',
				content: 'What should I run tomorrow?',
				archived_at: ARCHIVED_AT,
				created_at: '2026-05-02T11:59:00.000Z'
			},
			{
				user_id: USER_A.id,
				plan_id: null,
				role: 'assistant',
				content: 'An easy 5k to shake out the legs.',
				archived_at: ARCHIVED_AT,
				created_at: '2026-05-02T11:59:30.000Z'
			}
		]);
}

test.describe('/coach — archive-load / back-to-active failures are visible', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await clearArchive();
		await seedArchive();
	});

	test.afterEach(clearArchive);

	test('a failed viewArchive shows the load-archive error', async ({ page }) => {
		// Fail only the archive-detail select (archived_at=eq.<ts>); the
		// initial active-thread load (is.null) and archive list (not.is.null)
		// still succeed so the sidebar renders.
		await page.route('**/rest/v1/coach_messages**', async (route) => {
			const url = route.request().url();
			if (route.request().method() === 'GET' && url.includes('archived_at=eq.')) {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' })
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/coach?plan=none');
		await expect(page.getByPlaceholder(/Ask about/i)).toBeVisible({ timeout: 15_000 });
		await page.getByRole('button', { name: /Show conversations|Hide conversations/i }).click();

		const archiveRow = page.locator('.archive-row', { hasText: 'What should I run tomorrow?' });
		await expect(archiveRow).toBeVisible({ timeout: 10_000 });

		await archiveRow.click();

		await expect(page.locator('.error')).toHaveText(
			"Couldn't open that saved conversation. Try again.",
			{ timeout: 10_000 }
		);
	});

	test('a failed back-to-active load shows the load error', async ({ page }) => {
		let failActiveLoad = false;
		await page.route('**/rest/v1/coach_messages**', async (route) => {
			const url = route.request().url();
			// loadThread's select is archived_at=is.null; loadArchives is
			// archived_at=not.is.null, which does NOT contain that substring.
			if (
				route.request().method() === 'GET' &&
				failActiveLoad &&
				url.includes('archived_at=is.null')
			) {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' })
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/coach?plan=none');
		await expect(page.getByPlaceholder(/Ask about/i)).toBeVisible({ timeout: 15_000 });
		await page.getByRole('button', { name: /Show conversations|Hide conversations/i }).click();

		const archiveRow = page.locator('.archive-row', { hasText: 'What should I run tomorrow?' });
		await expect(archiveRow).toBeVisible({ timeout: 10_000 });

		// Open the archive successfully, then arm the active-thread load to fail.
		await archiveRow.click();
		await expect(page.getByText('Viewing archive')).toBeVisible({ timeout: 10_000 });

		failActiveLoad = true;
		await page.getByRole('button', { name: 'Back to active' }).click();

		await expect(page.locator('.error')).toHaveText(
			"Couldn't load your conversation. Try again.",
			{ timeout: 10_000 }
		);
	});
});
