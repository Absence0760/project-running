import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — "Mark as DNF" owner write path (persona round-5 ultra).
 *
 * `runs.metadata.is_dnf` already excludes a run from personal-records
 * scoring server-side (migration 20260530000001), but pre-fix there was
 * no write path to SET it — so a DNF ultra still scored as a PR. The
 * owner edit form now carries a "Mark as DNF" checkbox that patches
 * `metadata.is_dnf` through a read-merge-write mirroring
 * `updateRunMetadata` (whose title/notes normaliser drops unknown keys).
 *
 * This pins the round-trip:
 *   1. Toggling DNF on sets the runs.is_dnf column true + shows the chip.
 *   2. Toggling it back off clears the column to false so the PR trigger
 *      treats it as "not a DNF". (is_dnf was promoted from metadata to a
 *      real column in migration 20261207_001.)
 */

test.describe('/runs/[id] — Mark as DNF', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('owner toggles DNF on then off — is_dnf column round-trips true → false', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 42_000,
			duration_s: 18_000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'DNF at mile 26' }
		});
		const admin = getAdminClient();

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'DNF at mile 26' })).toBeVisible({
			timeout: 10_000
		});
		// Chip absent to start.
		await expect(page.getByTestId('dnf-chip')).toHaveCount(0);

		// Open edit form, tick DNF, save.
		await page.getByRole('button', { name: 'Edit title and notes' }).click();
		const dnfToggle = page.getByTestId('dnf-toggle');
		await expect(dnfToggle).toBeVisible();
		await expect(dnfToggle).not.toBeChecked();
		await dnfToggle.check();
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		// Chip shows + DB row carries is_dnf = true.
		await expect(page.getByTestId('dnf-chip')).toBeVisible({ timeout: 5_000 });
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('runs')
					.select('is_dnf')
					.eq('id', runId!)
					.single();
				return data?.is_dnf;
			}, { timeout: 5_000 })
			.toBe(true);

		// Toggle back off — the is_dnf column must go back to false.
		await page.getByRole('button', { name: 'Edit title and notes' }).click();
		const dnfToggleAgain = page.getByTestId('dnf-toggle');
		await expect(dnfToggleAgain).toBeChecked();
		await dnfToggleAgain.uncheck();
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(page.getByTestId('dnf-chip')).toHaveCount(0, { timeout: 5_000 });
		// Toggling DNF off clears the is_dnf column back to false (the PR
		// refresher filters on is_dnf = false since 20261207_001).
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('runs')
					.select('is_dnf')
					.eq('id', runId!)
					.single();
				return data?.is_dnf;
			}, { timeout: 5_000 })
			.toBe(false);
	});
});
