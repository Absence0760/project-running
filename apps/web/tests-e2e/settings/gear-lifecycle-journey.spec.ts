import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gear-lifecycle journey — the full cradle-to-grave life of a single
 * pair of shoes, walked through every surface it touches. Heavier than
 * settings/gear.spec.ts's per-action CRUD round-trips and
 * cross-cutting/gear-auto-tag-flow.spec.ts's default-chip flip because
 * it threads ONE gear id through create → run-picker → tag-onto-run →
 * mileage roll-up → retire → post-retirement survival, exercising the
 * seams between the gear settings page, the run-detail gear picker, the
 * `gear_with_distance` mileage view, and the retirement filter rather
 * than any single screen.
 *
 *   1. USER_A creates a NON-default shoe via the /settings/gear modal
 *      (createGear). Non-default on purpose: the auto_tag_default_gear
 *      trigger (migration 20260901_001) would otherwise stamp it onto
 *      every new run and muddy the "I tagged it myself" assertion in
 *      step 3. Fresh gear has total = 0 km / 0 runs.
 *   2. The new pair shows up in the run-detail gear PICKER. RunGearChips
 *      lists `myGear.filter((g) => !g.retired_at)` — an active pair is
 *      offered. We assert it via the picker checkbox, not the settings
 *      list (that's step 1's surface).
 *   3. USER_A tags the pair onto a run via the picker (setRunGear →
 *      run_gear insert). The `.gear-chip` for the pair renders on the
 *      run-detail strip.
 *   4. Mileage accrues: /settings/gear now reads the run's distance as
 *      the pair's accumulated total + a "1 run" count. Cross-checked in
 *      the backend against the `gear_with_distance` view (the same
 *      sum(distance_m) / count the UI reads).
 *   5. USER_A retires the pair (Retire button → retireGear). It drops
 *      out of the active list into the "Retired" section, and out of
 *      the run-detail picker (the `!retired_at` filter), so it can't be
 *      tagged onto NEW runs.
 *   6. History survives: the ALREADY-tagged run still renders the pair's
 *      `.gear-chip` (fetchRunGear → public_run_gear RPC has no retired
 *      filter), and the retired row in settings still shows its accrued
 *      distance. Backend cross-check: the run_gear link + the
 *      gear_with_distance total are both intact post-retirement.
 *
 * No rate-limit reset needed: neither createGear nor createManualRun
 * has a per-user bucket (only create_club / create_route are throttled,
 * see migration 20260907_001).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('gear lifecycle journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('create shoe → offered in picker → tag onto run → mileage accrues → retire → hidden from picker but history intact', async ({
		page
	}) => {
		const admin = getAdminClient();
		const shoeName = uniqueText('e2e-gear-journey-shoe');

		// Captured across surfaces so every step addresses the SAME gear +
		// run, and so teardown sweeps exactly what this test planted.
		let gearId = '';
		let runId = '';

		// The seed gives USER_A a current shoe (Pegasus 40, is_default).
		// Clear it for the duration so the auto-tag trigger doesn't stamp
		// step-3's run with Pegasus alongside our pair; restored in finally.
		await admin
			.from('gear')
			.update({ is_default: false })
			.eq('owner_id', USER_A.id)
			.eq('kind', 'shoe');

		try {
			// ── 1. Create a NON-default shoe via the gear modal ─────────
			await test.step('USER_A creates a new (non-default) shoe with a 500 km target', async () => {
				await page.goto('/settings/gear');
				await expect(page.locator('.gear-list')).toBeVisible({
					timeout: 10_000
				});

				await page
					.getByRole('button', { name: /New shoes/, exact: false })
					.first()
					.click();
				await page.locator('input[placeholder="Pegasus 39"]').fill(shoeName);
				// Retirement target (km tab default) → 500 km = 500_000 m, so a
				// single 6 km run later reads as 6.0 / 500 km and stays 'ok'.
				await page.locator('input[type="number"]').fill('500');
				await page.getByRole('button', { name: 'Add', exact: true }).click();

				const row = page.locator('.gear-row', { hasText: shoeName });
				await expect(row).toBeVisible({ timeout: 10_000 });
				// Fresh gear: 0.0 / 500 km and "0 runs" (the view's coalesced
				// sum / count for a pair with no run_gear links yet).
				await expect(row.locator('.gear-meta')).toContainText('0.0 / 500');
				await expect(row.locator('.gear-meta')).toContainText('0 runs');

				// Capture the id for the picker step + teardown. It must be
				// non-default so the auto-tag trigger leaves new runs alone.
				const { data: created } = await admin
					.from('gear')
					.select('id, is_default, target_distance_m')
					.eq('owner_id', USER_A.id)
					.eq('name', shoeName)
					.single();
				gearId = created!.id;
				expect(created?.is_default).toBe(false);
				expect(created?.target_distance_m).toBe(500_000);
			});

			// ── 2 + 3. Tag the pair onto a fresh run via the picker ─────
			await test.step('USER_A creates a run, and the new pair is offered in the run-detail picker', async () => {
				// A manual run with no default gear set → the auto-tag trigger
				// stamps nothing, so the picker starts empty and the only chip
				// after step 3 is the one we add.
				await page.goto('/runs/new');
				const numberInputs = page.locator('input[type="number"]');
				await numberInputs.nth(0).fill('6'); // distance km
				await numberInputs.nth(1).fill('35'); // duration min
				await page.getByRole('button', { name: 'Save run' }).click();
				await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
				runId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

				// No default gear → no auto-tagged chip to start.
				await expect(page.locator('.gear-chip')).toHaveCount(0);

				// Open the picker. canManage (owner) → the "+ Tag gear" button
				// renders; the picker lists only non-retired gear.
				await page
					.getByRole('button', { name: /Tag gear/, exact: false })
					.click();
				const dialog = page.locator('.modal');
				await expect(dialog).toBeVisible({ timeout: 5_000 });

				// The pair is offered (active gear shows in the picker list).
				const option = dialog.locator('li', { hasText: shoeName });
				await expect(option).toBeVisible({ timeout: 5_000 });
				await option.locator('input[type="checkbox"]').check();
				await dialog
					.getByRole('button', { name: 'Save', exact: true })
					.click();

				// save() awaits setRunGear + re-fetches; the chip lands on the
				// run-detail strip.
				await expect(
					page.locator('.gear-chip', { hasText: shoeName })
				).toBeVisible({ timeout: 10_000 });

				// Backend: exactly one run_gear link for this run, to our pair.
				const { data: links } = await admin
					.from('run_gear')
					.select('gear_id')
					.eq('run_id', runId);
				expect(links?.length ?? 0).toBe(1);
				expect(links?.[0]?.gear_id).toBe(gearId);
			});

			// ── 4. Mileage accrues on the gear page ─────────────────────
			await test.step("the run's distance rolls up onto the pair's accumulated mileage", async () => {
				await page.goto('/settings/gear');
				const row = page.locator('.gear-row', { hasText: shoeName });
				await expect(row).toBeVisible({ timeout: 10_000 });
				// 6 km run → "6.0 / 500 km" + "1 run" (the gear_with_distance
				// sum(distance_m) / count(run_gear) the UI reads).
				await expect(row.locator('.gear-meta')).toContainText('6.0 / 500');
				await expect(row.locator('.gear-meta')).toContainText('1 run');

				// Backend cross-check against the same view the UI consumes.
				const { data: rollup } = await admin
					.from('gear_with_distance')
					.select('total_distance_m, run_count')
					.eq('id', gearId)
					.single();
				expect(Number(rollup?.total_distance_m ?? 0)).toBe(6000);
				expect(Number(rollup?.run_count ?? 0)).toBe(1);
			});

			// ── 5. Retire the pair → gone from active list + picker ─────
			await test.step('USER_A retires the pair; it leaves the active list and the run picker', async () => {
				await page.goto('/settings/gear');
				const row = page.locator('.gear-row', { hasText: shoeName });
				await expect(row).toBeVisible({ timeout: 10_000 });
				await expect(row).not.toHaveClass(/retired/);

				await row.getByRole('button', { name: 'Retire', exact: true }).click();

				// The pair drops into the "Retired" section with a Restore
				// button — and is no longer an active row.
				const retiredRow = page.locator('.gear-row.retired', {
					hasText: shoeName
				});
				await expect(retiredRow).toBeVisible({ timeout: 10_000 });
				await expect(
					page.getByRole('heading', { name: 'Retired', level: 3 })
				).toBeVisible();

				// Backend: retired_at is now set.
				const { data: g } = await admin
					.from('gear')
					.select('retired_at')
					.eq('id', gearId)
					.single();
				expect(g?.retired_at).not.toBeNull();

				// The run-detail picker filters `!retired_at`, so a retired pair
				// can't be tagged onto a NEW run. Open the picker on our run and
				// assert the pair is absent from the options.
				//
				// Scope the opener to the RunGearChips strip: the run-detail
				// action toolbar carries an "Edit title and notes" icon button
				// whose accessible name also matches /Edit/, so an unscoped
				// .first() lands on it instead and opens the inline title editor
				// (no .modal). The pair is still tagged here, so the strip's
				// opener reads exactly "Edit" (runGearChips.edit), not "Tag gear".
				await page.goto(`/runs/${runId}`);
				await expect(
					page.locator('.gear-chip', { hasText: shoeName })
				).toBeVisible({ timeout: 10_000 });
				await page
					.locator('.gear-strip')
					.getByRole('button', { name: 'Edit', exact: true })
					.click();
				const dialog = page.locator('.modal');
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await expect(
					dialog.locator('li', { hasText: shoeName })
				).toHaveCount(0);
				// Close without changing the existing assignment.
				await dialog
					.getByRole('button', { name: 'Cancel', exact: true })
					.click();
			});

			// ── 6. History survives the retirement ──────────────────────
			await test.step('the already-tagged run keeps the chip + the retired row keeps its mileage', async () => {
				// The chip on the existing run still renders: fetchRunGear goes
				// through public_run_gear (no retired filter), so retiring a pair
				// never rewrites the history of runs it was worn on.
				await page.goto(`/runs/${runId}`);
				await expect(
					page.locator('.gear-chip', { hasText: shoeName })
				).toBeVisible({ timeout: 10_000 });

				// The retired row still shows its accrued distance in settings.
				await page.goto('/settings/gear');
				const retiredRow = page.locator('.gear-row.retired', {
					hasText: shoeName
				});
				await expect(retiredRow).toBeVisible({ timeout: 10_000 });
				await expect(retiredRow.locator('.gear-meta')).toContainText('6.0');

				// Backend: the run_gear link + the rolled-up total are intact
				// even though the gear is retired.
				const { data: links } = await admin
					.from('run_gear')
					.select('gear_id')
					.eq('run_id', runId);
				expect(links?.length ?? 0).toBe(1);
				const { data: rollup } = await admin
					.from('gear_with_distance')
					.select('total_distance_m, run_count')
					.eq('id', gearId)
					.single();
				expect(Number(rollup?.total_distance_m ?? 0)).toBe(6000);
				expect(Number(rollup?.run_count ?? 0)).toBe(1);
			});
		} finally {
			// Sweep the planted run (cascades its run_gear link) + the gear,
			// then restore the seed's Pegasus-40-as-default so downstream
			// gear specs see the shape they expect.
			if (runId) await admin.from('runs').delete().eq('id', runId);
			if (gearId) await admin.from('gear').delete().eq('id', gearId);
			await admin
				.from('gear')
				.update({ is_default: true })
				.eq('id', '11111111-aaaa-bbbb-cccc-222222222201');
		}
	});
});
