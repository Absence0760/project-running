import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/gear — post-create backfill.
 *
 * A runner almost never registers a pair of shoes the day they buy them, so
 * the mileage the app is about to track is already wrong at creation. When the
 * new gear carries a past `purchased_at`, the page offers the runs since then
 * and attaches the gear to the ones the runner picks.
 *
 * What this pins, beyond "the modal shows up":
 *
 *  1. The offer only lists runs on/after the purchase date, newest-first
 *     (`gearBackfillCandidates`).
 *  2. The write is ADDITIVE — `addGearToRuns`, not `setRunGear`. The planted
 *     run is auto-tagged with the owner's current pair by the
 *     `auto_tag_default_gear` trigger at insert; backfilling a second item
 *     must leave that first chip in place. A `setRunGear` regression here
 *     silently untags gear with no error and no undo, which is why the
 *     before/after run_gear set is compared rather than just counted.
 *  3. The gear row's accrued distance reflects the attached run afterwards.
 */

// Distinctive so the candidate row is unambiguous among whatever else USER_A
// has run recently: 9321 m renders as "9.32 km".
const PLANTED_DISTANCE_M = 9321;

function isoDate(d: Date): string {
	const y = d.getFullYear();
	const mo = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${mo}-${day}`;
}

test.describe('/settings/gear — backfill past runs onto newly-registered gear', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedRunId: string | null = null;
	let plantedGearId: string | null = null;

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
		if (plantedRunId) await admin.from('runs').delete().eq('id', plantedRunId);
		if (plantedGearId) await admin.from('gear').delete().eq('id', plantedGearId);
		plantedRunId = null;
		plantedGearId = null;
	});

	test('a new pair with a past purchase date offers its runs and attaches them additively', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const shoeName = `E2E Backfill Pair ${Date.now()}`;

		// A run "now" — comfortably inside a window that opens at yesterday's
		// local midnight, whatever hour the suite runs at.
		const { data: run } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				duration_s: 2700,
				distance_m: PLANTED_DISTANCE_M,
				source: 'app',
				activity_type: 'run',
			})
			.select('id')
			.single();
		plantedRunId = run!.id;

		// Whatever the auto-tag trigger stamped on it at insert. The backfill
		// must ADD to this set, never replace it.
		const { data: gearBefore } = await admin
			.from('run_gear')
			.select('gear_id')
			.eq('run_id', plantedRunId);
		const beforeIds = (gearBefore ?? []).map((r) => r.gear_id).sort();

		const yesterday = new Date();
		yesterday.setDate(yesterday.getDate() - 1);

		await test.step('register a pair bought yesterday', async () => {
			await page.goto('/settings/gear');
			await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: /New shoes/, exact: false }).first().click();
			await page.locator('input[placeholder="Pegasus 39"]').fill(shoeName);
			await page.locator('input[type="date"]').fill(isoDate(yesterday));
			await page.locator('input[type="number"]').fill('500');
			await page.getByRole('button', { name: 'Add', exact: true }).click();
		});

		const modal = page.getByTestId('gear-backfill-modal');
		const candidate = modal.locator('.candidate', { hasText: '9.32' });

		await test.step('the backfill offer lists the run from since the purchase', async () => {
			await expect(modal).toBeVisible({ timeout: 10_000 });
			await expect(candidate).toHaveCount(1);
			// Everything starts checked.
			await expect(candidate.locator('input[type="checkbox"]')).toBeChecked();
		});

		await test.step('deselect everything, then attach only the planted run', async () => {
			// "Select none" makes the assertion independent of whatever else
			// USER_A ran in the last day.
			await modal.getByText('Select none', { exact: true }).click();
			await expect(page.getByTestId('gear-backfill-count')).toContainText('0 of');
			await candidate.locator('input[type="checkbox"]').check();
			await expect(page.getByTestId('gear-backfill-count')).toContainText('1 of');

			await modal.getByRole('button', { name: /^Attach 1$/ }).click();
			await expect(modal).toBeHidden({ timeout: 10_000 });
		});

		const { data: created } = await admin
			.from('gear')
			.select('id')
			.eq('owner_id', USER_A.id)
			.eq('name', shoeName)
			.single();
		plantedGearId = created!.id;

		await test.step('the run now carries the new pair AND whatever it already had', async () => {
			const { data: gearAfter } = await admin
				.from('run_gear')
				.select('gear_id')
				.eq('run_id', plantedRunId!);
			const afterIds = (gearAfter ?? []).map((r) => r.gear_id).sort();
			expect(afterIds).toContain(plantedGearId);
			// Additive: every gear id the run carried before is still there.
			for (const id of beforeIds) expect(afterIds).toContain(id);
			expect(afterIds.length).toBe(beforeIds.length + 1);
		});

		await test.step('the gear row shows the backfilled distance', async () => {
			const row = page.locator('.gear-row', { hasText: shoeName });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row.locator('.gear-meta')).toContainText('9.3 / 500');
			await expect(row.locator('.gear-meta')).toContainText('1 run');
		});
	});

	test('a new pair with no purchase date prompts nothing', async ({ page }) => {
		// Reason: the window has no lower bound without a purchase date, so
		// there is nothing honest to propose — the prompt must not appear (and
		// must certainly not offer the runner's entire history).
		const admin = getAdminClient();
		const shoeName = `E2E No Date Pair ${Date.now()}`;

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /New shoes/, exact: false }).first().click();
		await page.locator('input[placeholder="Pegasus 39"]').fill(shoeName);
		await page.getByRole('button', { name: 'Add', exact: true }).click();

		await expect(page.locator('.gear-row', { hasText: shoeName })).toBeVisible({
			timeout: 10_000,
		});
		await expect(page.getByTestId('gear-backfill-modal')).toHaveCount(0);

		const { data: created } = await admin
			.from('gear')
			.select('id')
			.eq('owner_id', USER_A.id)
			.eq('name', shoeName)
			.single();
		plantedGearId = created!.id;
	});
});
