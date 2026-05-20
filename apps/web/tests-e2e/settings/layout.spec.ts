import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings — settings-nav structure. The 7 sub-pages are grouped
 * under three section labels in the sidebar nav (Profile / Apps &
 * data / Account & legal). Pins that grouping so future routes
 * land in the right bucket and don't get accidentally orphaned
 * outside any section.
 */
test.describe('/settings — side-nav structure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('side-nav groups the 7 pages under three section headers', async ({
		page
	}) => {
		await page.goto('/settings/account');

		const nav = page.locator('.settings-nav');
		await expect(nav).toBeVisible({ timeout: 10_000 });

		// Three section headers in the documented order.
		const sectionLabels = nav.locator('.nav-section-label');
		await expect(sectionLabels).toHaveCount(3);
		await expect(sectionLabels.nth(0)).toHaveText(/Profile/);
		await expect(sectionLabels.nth(1)).toHaveText(/Apps & data/);
		await expect(sectionLabels.nth(2)).toHaveText(/Account & legal/);

		// Every existing tab is still present + each routes correctly.
		const expected = [
			{ href: '/settings/account', label: 'Account' },
			{ href: '/settings/preferences', label: 'Preferences' },
			{ href: '/settings/integrations', label: 'Integrations' },
			{ href: '/settings/devices', label: 'Devices' },
			{ href: '/settings/gear', label: 'Gear' },
			{ href: '/settings/upgrade', label: 'Pro & support' },
			{ href: '/settings/licenses', label: 'Licenses' },
		];
		for (const { href, label } of expected) {
			const link = nav.locator(`a[href="${href}"]`);
			await expect(link).toBeVisible();
			await expect(link).toContainText(label);
		}

		// Clicking a tab routes to it + applies the active class.
		await nav.locator('a[href="/settings/gear"]').click();
		await expect(page).toHaveURL(/\/settings\/gear$/);
		await expect(nav.locator('a[href="/settings/gear"]')).toHaveClass(
			/active/
		);
	});
});
