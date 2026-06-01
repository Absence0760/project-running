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
 *   1. Toggling DNF on writes `is_dnf: true` to the row + shows the chip.
 *   2. Toggling it back off DELETES the key (not `false`) — matching the
 *      metadata-bag convention so the PR trigger treats it as "not a DNF".
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

	test('owner toggles DNF on then off — metadata.is_dnf round-trips true → absent', async ({
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
					.select('metadata')
					.eq('id', runId!)
					.single();
				return (data?.metadata as Record<string, unknown> | null)?.['is_dnf'];
			}, { timeout: 5_000 })
			.toBe(true);

		// Toggle back off — the key must be REMOVED, not set to false.
		await page.getByRole('button', { name: 'Edit title and notes' }).click();
		const dnfToggleAgain = page.getByTestId('dnf-toggle');
		await expect(dnfToggleAgain).toBeChecked();
		await dnfToggleAgain.uncheck();
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(page.getByTestId('dnf-chip')).toHaveCount(0, { timeout: 5_000 });
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('runs')
					.select('metadata')
					.eq('id', runId!)
					.single();
				const meta = (data?.metadata as Record<string, unknown> | null) ?? {};
				return Object.prototype.hasOwnProperty.call(meta, 'is_dnf');
			}, { timeout: 5_000 })
			.toBe(false);
	});
});
