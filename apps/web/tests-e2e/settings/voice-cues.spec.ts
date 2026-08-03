import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/preferences — the per-cue voice-cue toggles (issue #607).
 *
 * The cue map is SPARSE: an id absent from `voice_cue_types` is ON. So the
 * two things worth pinning end-to-end are (a) a fresh account renders every
 * cue checked without any stored map, and (b) turning one off survives a
 * reload — i.e. the merge write actually reached the universal bag and the
 * load path read it back — while leaving the other cues alone.
 */

const MASTER_TOGGLE = 'Spoken split announcements (mobile + watch)';

async function setMaster(page: Page, on: boolean) {
	const master = page.getByLabel(MASTER_TOGGLE);
	await expect(master).toBeVisible({ timeout: 10_000 });
	if ((await master.isChecked()) !== on) {
		await master.setChecked(on);
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
	}
}

test.describe('/settings/preferences voice cues', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('per-cue toggles default on, and turning one off round-trips', async ({ page }) => {
		await page.goto('/settings/preferences');
		await setMaster(page, true);

		const cueList = page.getByTestId('voice-cue-types');
		await expect(cueList).toBeVisible();
		// One row per cue id in the shared wire contract.
		await expect(cueList.locator('input[type="checkbox"]')).toHaveCount(8);

		const offRoute = page.getByTestId('voice-cue-off_route');
		const splits = page.getByTestId('voice-cue-splits');
		await expect(offRoute).toBeChecked();
		await expect(splits).toBeChecked();

		await offRoute.uncheck();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		try {
			await page.reload();
			await expect(page.getByTestId('voice-cue-off_route')).not.toBeChecked({ timeout: 10_000 });
			// Turning one cue off must not disturb the rest of the sparse map.
			await expect(page.getByTestId('voice-cue-splits')).toBeChecked();
			await expect(page.getByTestId('voice-cue-cutoff_catch_up')).toBeChecked();
		} finally {
			await page.goto('/settings/preferences');
			await setMaster(page, true);
			await page.getByTestId('voice-cue-off_route').check();
			await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
			await setMaster(page, false);
		}
	});

	test('the cue list is hidden until spoken cues are switched on', async ({ page }) => {
		await page.goto('/settings/preferences');
		await setMaster(page, false);
		await expect(page.getByTestId('voice-cue-types')).toBeHidden();

		await setMaster(page, true);
		await expect(page.getByTestId('voice-cue-types')).toBeVisible();

		await setMaster(page, false);
	});
});
