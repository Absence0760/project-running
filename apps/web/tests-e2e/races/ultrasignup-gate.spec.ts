import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * UltraSignup fail-closed gate (race_calendar.md / decisions §186). With
 * ULTRASIGNUP_API_KEY unset (the dev/CI default), the race-listings-sync probe
 * (provider='ultrasignup') returns 503 provider_not_configured, so the Settings
 * → Integrations UltraSignup card shows the unavailable explainer instead of an
 * open-the-calendar action — and the page does not crash. parkrun + manual
 * paste stay available, mirroring the RunSignUp gate.
 */

test.describe('UltraSignup gate (unconfigured key)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('settings card shows the unavailable explainer, no open action', async ({ page }) => {
		await page.goto('/settings/integrations');

		const card = page.getByTestId('ultrasignup-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('ultrasignup-unavailable')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('ultrasignup-open')).toHaveCount(0);

		// parkrun stays available (fail-closed is scoped to the API providers).
		await expect(page.getByText('parkrun', { exact: true })).toBeVisible();
	});
});
