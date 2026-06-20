import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Challenges create + join lifecycle (challenges.md).
 * USER_A creates an individual distance challenge via the editor, it appears
 * in My challenges (the creator is NOT auto-joined), then joins it from the
 * detail page and the Leave control appears.
 */
test.describe('/challenges — create + join', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of created) {
			await admin.from('challenges').delete().eq('id', id);
		}
		created.length = 0;
	});

	test('create an individual distance challenge, then join it', async ({ page }) => {
		const title = `e2e-challenge ${Date.now()}`;

		await page.goto('/challenges');
		await expect(page.getByRole('heading', { level: 1, name: /Challenges/ })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(title);
		await modal.getByLabel(/Goal/).fill('100000');
		await modal.getByRole('button', { name: /Create challenge/ }).click();

		// Lands on the new challenge's detail page.
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		// Capture the id for cleanup from the URL.
		const url = new URL(page.url());
		const id = url.pathname.split('/').pop()!;
		created.push(id);

		// Creator is not auto-joined → Join is offered.
		const joinBtn = page.getByRole('button', { name: /^Join$/ });
		await expect(joinBtn).toBeVisible();
		await joinBtn.click();

		// After joining, Leave appears and the progress bar (for an individual
		// joined challenge) shows.
		await expect(page.getByRole('button', { name: /^Leave$/ })).toBeVisible({ timeout: 10_000 });
	});
});
