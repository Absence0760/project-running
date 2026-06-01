import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — Laps section.
 *
 * When a run carries `metadata.laps` (set by a recording client when
 * the user marks laps mid-run), the detail page renders a "Laps"
 * section with a per-lap table: Lap / Distance / Time / Pace. Web is
 * the canonical surface (decisions §24) and mobile already renders
 * laps — these tests close the parity gap and pin the render.
 *
 * The renderer is `apps/web/src/routes/runs/[id]/+page.svelte`. The
 * Dart parity is `run_detail_screen.dart` (`_buildLaps`). `distance_m`
 * and `duration_s` are per-lap deltas (docs/backend/metadata.md § laps);
 * `metadata` is null entirely when there are no laps, so both the
 * absent-bag and absent-key cases must hide the section.
 */

const PLANNED_M = 5000;

function lap(opts: {
	index: number;
	start_offset_s: number;
	distance_m: number;
	duration_s: number;
}): Record<string, unknown> {
	return {
		index: opts.index,
		start_offset_s: opts.start_offset_s,
		distance_m: opts.distance_m,
		duration_s: opts.duration_s
	};
}

test.describe('/runs/[id] — Laps section', () => {
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

	test('section is HIDDEN when metadata is absent (no laps)', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		await page.goto(`/runs/${runId}`);
		await expect(page.locator('section.laps')).toHaveCount(0);
	});

	test('section is HIDDEN when metadata.laps is an empty array', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({ metadata: { activity_type: 'run', laps: [] } })
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		await expect(page.locator('section.laps')).toHaveCount(0);
	});

	test('per-lap rows render with one row per lap', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					laps: [
						lap({ index: 1, start_offset_s: 0, distance_m: 1000, duration_s: 300 }),
						lap({ index: 2, start_offset_s: 300, distance_m: 1000, duration_s: 315 }),
						lap({ index: 3, start_offset_s: 615, distance_m: 1000, duration_s: 320 })
					]
				}
			})
			.eq('id', runId);

		await page.goto(`/runs/${runId}`);
		const section = page.locator('section.laps');
		await expect(section).toBeVisible({ timeout: 10_000 });
		await expect(section.getByRole('heading', { name: 'Laps' })).toBeVisible();
		await expect(section.locator('tbody tr')).toHaveCount(3);
		// 1-based lap index renders in the first column.
		await expect(section.locator('tbody tr').first().locator('td').first()).toHaveText('1');
	});

	test('table header carries the canonical column labels', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					laps: [lap({ index: 1, start_offset_s: 0, distance_m: 1000, duration_s: 300 })]
				}
			})
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		const headers = page.locator('table.laps-table thead th');
		await expect(headers).toHaveText(['Lap', 'Distance', 'Time', 'Pace']);
	});
});
