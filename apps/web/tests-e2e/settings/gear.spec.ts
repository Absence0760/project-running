import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/gear — current-gear (is_default) star toggle.
 *
 * Pins the partial-unique-default invariant from migration
 * 20260901_001: at most one non-retired gear item per (owner, kind)
 * can carry is_default = true at a time. The settings page exposes
 * this as a star button on each gear card; clicking it flips the
 * default and (if necessary) unsets the previous default of the
 * same kind. The trigger on `runs insert` then auto-tags new runs
 * with whichever gear holds the star.
 *
 * Seed shape used by the asserts:
 *   - 'Pegasus 40' (shoe, is_default=true)
 *   - 'Ghost 16'   (shoe, is_default=false)
 */
test.describe('/settings/gear — current-gear toggle', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('star toggle moves the current default to a different shoe; partial-unique invariant holds', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Pre-condition pin: seed put Pegasus 40 as the current shoe.
		const before = await admin
			.from('gear')
			.select('name, is_default')
			.eq('owner_id', USER_A.id)
			.eq('kind', 'shoe')
			.eq('is_default', true);
		expect(before.data?.length ?? 0).toBe(1);
		expect(before.data?.[0]?.name).toBe('Pegasus 40');

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		// The Pegasus row carries the "Current" pill; the Ghost row
		// does not.
		const pegasusRow = page.locator('.gear-row', { hasText: 'Pegasus 40' });
		const ghostRow = page.locator('.gear-row', { hasText: 'Ghost 16' });
		await expect(pegasusRow.locator('.default-pill')).toBeVisible();
		await expect(ghostRow.locator('.default-pill')).toHaveCount(0);

		// Click the star on the Ghost row → it becomes the new default.
		await ghostRow
			.getByRole('button', { name: /Mark Ghost 16 as current/ })
			.click();

		// UI flips: Current pill now lives on Ghost, gone from Pegasus.
		await expect(ghostRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
		await expect(pegasusRow.locator('.default-pill')).toHaveCount(0);

		// Backend: still exactly one shoe-default, and it's Ghost.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear')
						.select('name')
						.eq('owner_id', USER_A.id)
						.eq('kind', 'shoe')
						.eq('is_default', true);
					return data?.map((g) => g.name) ?? [];
				},
				{ timeout: 5_000 }
			)
			.toEqual(['Ghost 16']);

		// Restore so the rest of the suite sees the seeded default state.
		await pegasusRow
			.getByRole('button', { name: /Mark Pegasus 40 as current/ })
			.click();
		await expect(pegasusRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
	});

	test('clicking the star on the current default clears it — no default until the user re-stars one', async ({
		page
	}) => {
		const admin = getAdminClient();

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		const pegasusRow = page.locator('.gear-row', { hasText: 'Pegasus 40' });
		await pegasusRow
			.getByRole('button', { name: /Unmark Pegasus 40 as current/ })
			.click();

		// UI: no row has the Current pill anymore.
		await expect(page.locator('.default-pill')).toHaveCount(0, {
			timeout: 5_000
		});

		// Backend: no shoe-default.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear')
						.select('id')
						.eq('owner_id', USER_A.id)
						.eq('kind', 'shoe')
						.eq('is_default', true);
					return data?.length ?? 0;
				},
				{ timeout: 5_000 }
			)
			.toBe(0);

		// Restore.
		await pegasusRow
			.getByRole('button', { name: /Mark Pegasus 40 as current/ })
			.click();
		await expect(pegasusRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
	});
});
