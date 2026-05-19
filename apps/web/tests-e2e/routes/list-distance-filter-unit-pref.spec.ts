import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Regression net for the /routes (and the Explore subtab's
 * `RouteExplorer`) distance-filter dropdowns.
 *
 * Before the unit-pref sweep, both surfaces hardcoded "km" labels
 * AND interpreted bucket boundaries in km regardless of the user's
 * `preferred_unit`. An mi-mode user picking "< 5" got "< 5 km" labels
 * (~3.1 mi) but expected "< 5 mi". The fix: labels read the user's
 * unit, and the bucket comparison applies the threshold in that unit.
 *
 * Verifying the actual filter math requires planted routes at the
 * right boundary distances. This spec scopes to the LABEL contract
 * (cheap to verify, the bug bait the audit surfaced) and the
 * negative-shape pin that no metric label leaks into mi-mode (or
 * vice versa). The bucket-comparison math is covered by a node:test
 * suite on the helper module.
 */

test.describe('/routes — distance-filter labels honour user unit pref', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		// Reset to default so other specs don't see a dirty pref.
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);
	});

	test('mi-mode: My-routes distance dropdown labels read "5 mi" / "10 mi" / "20 mi"', async ({
		page
	}) => {
		await setUserSetting(USER_A.id, 'preferred_unit', 'mi');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'mi' })
			.eq('id', USER_A.id);

		await page.goto('/routes');
		await page.waitForLoadState('networkidle');

		const select = page.getByLabel('Distance');
		await expect(select).toBeVisible({ timeout: 10_000 });
		// Pin each option's label. The values stay as 'lt5' / '5to10'
		// etc. so URL state survives the unit flip, but the visible
		// labels switch.
		await expect(select.locator('option[value="lt5"]')).toHaveText(
			/< 5 mi/,
		);
		await expect(select.locator('option[value="5to10"]')).toHaveText(
			/5–10 mi/,
		);
		await expect(select.locator('option[value="10to20"]')).toHaveText(
			/10–20 mi/,
		);
		await expect(select.locator('option[value="gt20"]')).toHaveText(
			/20\+ mi/,
		);
		// Negative shape — no "km" leaks into the bucketed options.
		await expect(
			select.locator('option[value="lt5"]', { hasText: /km/ }),
		).toHaveCount(0);
	});

	test('km-mode: My-routes distance dropdown labels read "5 km" / "10 km" / "20 km"', async ({
		page
	}) => {
		// Negative-shape on the default pref.
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);

		await page.goto('/routes');
		await page.waitForLoadState('networkidle');

		const select = page.getByLabel('Distance');
		await expect(select).toBeVisible({ timeout: 10_000 });
		await expect(select.locator('option[value="lt5"]')).toHaveText(
			/< 5 km/,
		);
		await expect(select.locator('option[value="5to10"]')).toHaveText(
			/5–10 km/,
		);
		await expect(select.locator('option[value="gt20"]')).toHaveText(
			/20\+ km/,
		);
		// Negative — no "mi" in the metric path.
		await expect(
			select.locator('option', { hasText: /\bmi\b/ }),
		).toHaveCount(0);
	});

	test('mi-mode: Explore subtab dropdown uses imperial buckets (3 / 6 / 13 mi)', async ({
		page
	}) => {
		// RouteExplorer has its OWN bucket ladder — 5/10/21 km maps to
		// 3/6/13 mi (the canonical race ladder in each system). Pin
		// the imperial labels so a regression that left them hardcoded
		// would fail loud.
		await setUserSetting(USER_A.id, 'preferred_unit', 'mi');
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ preferred_unit: 'mi' })
			.eq('id', USER_A.id);

		await page.goto('/routes?tab=explore');
		await page.waitForLoadState('networkidle');

		// The Explore tab has its own Distance dropdown — find it by
		// the surrounding label rather than aria-label since the
		// component uses a different markup.
		const dropdowns = page.locator('select');
		// One of the selects holds the distance options. Locate by
		// the presence of the "Any distance" option.
		const distSelect = dropdowns.filter({
			has: page.locator('option', { hasText: 'Any distance' })
		}).first();
		await expect(distSelect).toBeVisible({ timeout: 10_000 });
		await expect(distSelect).toContainText(/Under 3 mi/);
		await expect(distSelect).toContainText(/3-6 mi/);
		await expect(distSelect).toContainText(/6-13 mi/);
		await expect(distSelect).toContainText(/13 mi\+/);
		// Negative — no metric option remains.
		await expect(distSelect).not.toContainText(/Under 5 km/);
	});
});
