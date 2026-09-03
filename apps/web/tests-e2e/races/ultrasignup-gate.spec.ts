import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * UltraSignup fail-closed gate (race_calendar.md / decisions §186). With
 * ULTRASIGNUP_API_KEY unset (the dev/CI default), the race-results-import probe
 * (provider='ultrasignup') returns 503 provider_not_configured, so the Settings
 * → Integrations UltraSignup card shows the unavailable explainer instead of an
 * open-the-calendar action — and the page does not crash. parkrun + manual
 * paste stay available, mirroring the RunSignUp gate.
 */

test.describe('UltraSignup gate (unconfigured key)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E UltraSignup Gate ${stamp}`;
	let listingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'ultrasignup',
			name: raceName,
			race_date: browserDate(30),
			provider_race_id: 'e2e-ultrasignup-1'
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
	});

	test('settings card shows the unavailable explainer, no open action', async ({ page }) => {
		await page.goto('/settings/integrations');

		const card = page.getByTestId('ultrasignup-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('ultrasignup-unavailable')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('ultrasignup-open')).toHaveCount(0);

		// parkrun stays available (fail-closed is scoped to the API providers).
		await expect(page.getByText('parkrun', { exact: true })).toBeVisible();
	});

	test('the race calendar import modal names UltraSignup, not RunSignUp', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);

		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		// Its OWN explainer: a runner told RunSignUp is unavailable about a
		// UltraSignup-timed race learns nothing true.
		await expect(page.getByTestId('race-ultrasignup-unavailable')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-runsignup-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('race-import-ultrasignup')).toHaveCount(0);

		// The manual paste form is the universal fallback and stays available.
		await expect(page.getByTestId('paste-save')).toBeVisible();
	});
});
