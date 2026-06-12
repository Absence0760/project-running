import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The unified create hub at /plans/new — one front door with a Training /
 * Session / Gym-routine chooser that swaps in the matching editor, replacing
 * the three previously-fragmented create surfaces. `?type=` selects the initial
 * branch (used by the club Templates-tab deep links).
 */

test.describe('/plans/new — unified create hub', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the chooser swaps between the training, session, and gym editors', async ({ page }) => {
		await page.goto('/plans/new');

		// Training is the default branch — the starter-plan picker is present,
		// the session/gym editors are not.
		await expect(page.getByTestId('kind-training')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.locator('.starter-picker')).toBeVisible();
		await expect(page.locator('.session-editor')).toHaveCount(0);

		// Session branch → the SessionPlanEditor mounts, training picker gone.
		await page.getByTestId('kind-session').click();
		await expect(page.locator('.session-editor')).toBeVisible();
		await expect(page.locator('.starter-picker')).toHaveCount(0);

		// Gym branch → neither the training picker nor the session editor.
		await page.getByTestId('kind-gym').click();
		await expect(page.locator('.session-editor')).toHaveCount(0);
		await expect(page.locator('.starter-picker')).toHaveCount(0);
	});

	test('?type=session deep-links straight to the session branch', async ({ page }) => {
		await page.goto('/plans/new?type=session');
		await expect(page.getByTestId('kind-session')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.locator('.session-editor')).toBeVisible();
	});
});
