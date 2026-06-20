import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * RunSignUp fail-closed gate (race_calendar.md). With RUNSIGNUP_API_KEY unset
 * (the dev/CI default), the race-listings-sync probe returns 503
 * provider_not_configured, so the Settings → Integrations RunSignUp card shows
 * the unavailable explainer instead of an open-the-calendar action — and the
 * page does not crash. parkrun + manual paste stay available.
 */

test.describe('RunSignUp gate (unconfigured key)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('settings card shows the unavailable explainer, no open action', async ({ page }) => {
		await page.goto('/settings/integrations');

		const card = page.getByTestId('runsignup-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('runsignup-unavailable')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('runsignup-open')).toHaveCount(0);

		// parkrun stays available (fail-closed is scoped to RunSignUp).
		await expect(page.getByText('parkrun', { exact: true })).toBeVisible();
	});

	test('races import modal offers manual paste even when RunSignUp is gated', async ({ page }) => {
		await page.goto('/races');
		// The page loads without crashing despite the 503 probe.
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-submit')).toBeVisible();
	});
});
