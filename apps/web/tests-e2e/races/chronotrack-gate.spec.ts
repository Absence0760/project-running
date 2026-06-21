import { expect, test } from '@playwright/test';

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

	test('settings card shows the unavailable explainer, no open action', async ({ page }) => {
		await page.goto('/settings/integrations');

		const card = page.getByTestId('chronotrack-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('chronotrack-unavailable')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('chronotrack-open')).toHaveCount(0);

		// parkrun stays available (fail-closed is scoped to the API providers).
		await expect(page.getByText('parkrun', { exact: true })).toBeVisible();
	});
});
