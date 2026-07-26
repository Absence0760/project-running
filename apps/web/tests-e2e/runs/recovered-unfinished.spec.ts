import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — the "Incomplete" chip for a boot-recovered watch run.
 *
 * The custom watch checkpoints a run in progress to flash. A reset mid-run
 * means boot reconciliation recovers that checkpoint and the phone ingests it
 * (decisions §316(c) — refusing it would destroy the only copy of the run), so
 * the run's totals are its totals-so-far. `metadata.recovered_unfinished`
 * carries that truth through ingest (§323); without the chip the page presents
 * a reboot at mile 60 as the runner's whole day.
 *
 * The key is public-safe on purpose, so this pins presence AND absence: an
 * ordinary run must never wear the chip.
 */

test.describe('/runs/[id] — recovered-unfinished chip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const runIds: string[] = [];

	test.afterEach(async () => {
		while (runIds.length) {
			const id = runIds.pop()!;
			try {
				await deleteRun(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a recovered run shows the chip and an ordinary run does not', async ({ page }) => {
		const partialId = await insertRun({
			user_id: USER_A.id,
			distance_m: 96_000,
			duration_s: 54_000,
			is_public: false,
			metadata: {
				activity_type: 'run',
				title: 'Reboot at mile 60',
				recovered_unfinished: true
			}
		});
		runIds.push(partialId);

		const wholeId = await insertRun({
			user_id: USER_A.id,
			distance_m: 10_000,
			duration_s: 3_000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'Ordinary watch run' }
		});
		runIds.push(wholeId);

		await page.goto(`/runs/${partialId}`);
		await expect(page.getByRole('heading', { name: 'Reboot at mile 60' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('incomplete-chip')).toBeVisible();
		await expect(page.getByTestId('incomplete-chip')).toContainText('Incomplete');

		await page.goto(`/runs/${wholeId}`);
		await expect(page.getByRole('heading', { name: 'Ordinary watch run' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('incomplete-chip')).toHaveCount(0);
	});
});
