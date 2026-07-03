import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — parkrun regional-availability note.
 *
 * parkrun operates in ~20 countries; the card used to present it as
 * universal. lib/integrations/parkrun_regions.ts gates a "may not have
 * events near you" note on navigator.language's region: shown outside
 * the footprint, hidden inside it (and hidden for a region-less
 * locale, so no false warning). The card itself stays connectable
 * everywhere — an expat with a parkrun athlete ID must not be blocked
 * (audit regional-availability, Medium).
 *
 * Locale is overridden per browser context, which drives
 * navigator.language — the exact value the helper reads.
 */

test.describe('parkrun region note', () => {
	test('es-ES (outside the parkrun footprint) shows the note', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'es-ES'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/integrations');
			const parkrunCard = page.locator('.integration-card', { hasText: 'parkrun' });
			await expect(parkrunCard).toBeVisible({ timeout: 10_000 });
			await expect(parkrunCard.locator('.sync-note')).toBeVisible();
			// The connect/disconnect affordance stays — the note is a
			// disclosure, not a gate.
			await expect(parkrunCard.getByRole('button')).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test('en-GB (a parkrun country) shows no note', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-GB'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/integrations');
			const parkrunCard = page.locator('.integration-card', { hasText: 'parkrun' });
			await expect(parkrunCard).toBeVisible({ timeout: 10_000 });
			await expect(parkrunCard.locator('.sync-note')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
