import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gear auto-tag end-to-end: the `auto_tag_default_gear` trigger
 * (migration 20260901_001) stamps every new run with the owner's
 * current default gear of the matching kind. The seed gives USER_A
 * two pairs of shoes — Pegasus 40 as default, Ghost 16 as rotation.
 *
 *  1. /settings/gear shows Pegasus 40 as the current default.
 *  2. /runs/new → create a manual run → land on /runs/[id] →
 *     Pegasus 40 chip is auto-tagged (no manual picker step).
 *  3. /settings/gear → flip default to Ghost 16 via the star button.
 *  4. /runs/new → create a second run → /runs/[id] → Ghost 16 is
 *     the auto-tagged chip (not Pegasus 40).
 *
 * Cleans up the two planted runs and restores Pegasus 40 as default
 * so downstream tests see the seed shape they expect.
 */

const PEGASUS_GEAR_ID = '11111111-aaaa-bbbb-cccc-222222222201';

test.describe('Gear auto-tag flow', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedRunIds: string[] = [];

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (plantedRunIds.length > 0) {
			await admin.from('runs').delete().in('id', plantedRunIds);
			plantedRunIds = [];
		}
		await admin
			.from('gear')
			.update({ is_default: false })
			.eq('owner_id', USER_A.id)
			.eq('kind', 'shoe');
		await admin
			.from('gear')
			.update({ is_default: true })
			.eq('id', PEGASUS_GEAR_ID);
	});

	test('default gear auto-tags new runs; flipping the default flips the chip', async ({
		page,
	}) => {
		await test.step('seed default (Pegasus 40) is visible on /settings/gear', async () => {
			await page.goto('/settings/gear');
			const pegasusRow = page.locator('.gear-row', { hasText: 'Pegasus 40' });
			await expect(pegasusRow).toBeVisible({ timeout: 10_000 });
			await expect(pegasusRow).toHaveClass(/is-default/);
			await expect(pegasusRow.locator('.default-pill')).toBeVisible();

			const ghostRow = page.locator('.gear-row', { hasText: 'Ghost 16' });
			await expect(ghostRow).toBeVisible();
			await expect(ghostRow).not.toHaveClass(/is-default/);
		});

		await test.step('create run #1 → auto-tagged with Pegasus 40', async () => {
			await page.goto('/runs/new');
			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill('5');
			await numberInputs.nth(1).fill('30');
			await page.getByRole('button', { name: 'Save run' }).click();
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
			const id = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
			plantedRunIds.push(id);

			const chip = page.locator('.gear-chip', { hasText: 'Pegasus 40' });
			await expect(chip).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.gear-chip', { hasText: 'Ghost 16' })).toHaveCount(0);
		});

		await test.step('flip default to Ghost 16 via the star button', async () => {
			await page.goto('/settings/gear');
			const ghostRow = page.locator('.gear-row', { hasText: 'Ghost 16' });
			await expect(ghostRow).toBeVisible({ timeout: 10_000 });
			await ghostRow.locator('.star-btn').click();
			await expect(ghostRow).toHaveClass(/is-default/, { timeout: 10_000 });
			await expect(
				page.locator('.gear-row', { hasText: 'Pegasus 40' }),
			).not.toHaveClass(/is-default/);
		});

		await test.step('create run #2 → auto-tagged with Ghost 16, not Pegasus', async () => {
			await page.goto('/runs/new');
			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill('4');
			await numberInputs.nth(1).fill('25');
			await page.getByRole('button', { name: 'Save run' }).click();
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
			const id = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
			plantedRunIds.push(id);

			await expect(
				page.locator('.gear-chip', { hasText: 'Ghost 16' }),
			).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.gear-chip', { hasText: 'Pegasus 40' })).toHaveCount(0);
		});
	});
});
