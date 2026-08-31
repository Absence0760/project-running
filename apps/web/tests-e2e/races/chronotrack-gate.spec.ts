import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * ChronoTrack fail-closed gate (race_calendar.md). With CHRONOTRACK_CLIENT_ID /
 * CHRONOTRACK_USER_ID / CHRONOTRACK_PASSWORD unset (the dev/CI default), the
 * race-results-import probe returns 503 provider_not_configured, so the
 * Settings → Integrations ChronoTrack card shows the unavailable explainer
 * instead of an open-the-calendar action — and the page does not crash.
 * parkrun + manual paste stay available.
 */

test.describe('ChronoTrack gate (unconfigured credentials)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E ChronoTrack Gate ${stamp}`;
	let listingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'chronotrack',
			name: raceName,
			race_date: browserDate(30),
			provider_race_id: 'e2e-chronotrack-1'
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
	});

	test('settings card shows the unavailable explainer, no open action', async ({ page }) => {
		await page.goto('/settings/integrations');

		const card = page.getByTestId('chronotrack-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('chronotrack-unavailable')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('chronotrack-open')).toHaveCount(0);

		// parkrun stays available (fail-closed is scoped to the API providers).
		await expect(page.getByText('parkrun', { exact: true })).toBeVisible();
	});

	test('the race calendar import modal names ChronoTrack, not RunSignUp', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);

		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		// Its OWN explainer: a runner told RunSignUp is unavailable about a
		// ChronoTrack-timed race learns nothing true.
		await expect(page.getByTestId('race-chronotrack-unavailable')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-runsignup-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('race-import-chronotrack')).toHaveCount(0);

		// The manual paste form is the universal fallback and stays available.
		await expect(page.getByTestId('paste-save')).toBeVisible();
	});
});
