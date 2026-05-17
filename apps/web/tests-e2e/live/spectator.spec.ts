import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const MELBOURNE_NEARBY_OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.8160, lng: 144.9700 },
	{ lat: -37.8175, lng: 144.9720 },
	{ lat: -37.8200, lng: 144.9750 },
	{ lat: -37.8230, lng: 144.9780 }
];

test.describe('/live/[id] — anon spectator', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('shell mounts (logo + badge + stat tiles) for a public seeded run', async ({
		page
	}) => {
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-badge')).toBeVisible();
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
	});

	test('document title reflects "Live" so a backgrounded tab reads as the spectator surface', async ({
		page
	}) => {
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');
		await expect(page).toHaveTitle(/Live|Run Onward/i);
	});

	test('in-progress run: planted live pings hydrate distance + elapsed and flip badge to LIVE', async ({
		page
	}) => {
		// Started 5 min ago, projected duration 60 min — the run is
		// still in progress so the page must NOT treat it as finished.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[1], distance_m: 2_000, elapsed_s: 600 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[2], distance_m: 3_000, elapsed_s: 900 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);
			await page.waitForLoadState('networkidle');

			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});
			await expect(page.locator('.live-badge')).toContainText('LIVE');

			await expect(page.locator('.live-runner-name')).toContainText('Jared Howard');

			await expect(page.locator('.live-stat-value').first()).toContainText('4.5');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('22:30');
			await expect(page.locator('.live-stat-value').nth(2)).not.toContainText('--');

			await expect(page.locator('.live-runner-sub')).toContainText(/Live from the runner/i);
		} finally {
			await deleteRun(runId);
		}
	});

	test('finished run: saved totals render with "Finished" badge', async ({ page }) => {
		const startedAt = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 10_000,
			duration_s: 3_000,
			is_public: true
		});
		try {
			await page.goto(`/live/${runId}`);
			await page.waitForLoadState('networkidle');

			await expect(page.locator('.live-badge')).toHaveClass(/finished/, {
				timeout: 10_000
			});
			await expect(page.locator('.live-badge')).toContainText(/Finished/i);

			await expect(page.locator('.live-stat-value').first()).toContainText('10');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('50:00');

			await expect(page.locator('.live-runner-sub')).toContainText(/Run finished/i);
		} finally {
			await deleteRun(runId);
		}
	});

	test('private run renders the not-broadcasting empty state to anon', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);
			await page.waitForLoadState('networkidle');

			await expect(page.locator('.live-badge')).toHaveClass(/not-found/, {
				timeout: 10_000
			});
			await expect(page.getByRole('heading', { name: /isn't broadcasting/i })).toBeVisible();
			await expect(page.locator('.live-stat-label')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('unknown run id renders the not-broadcasting empty state', async ({ page }) => {
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/live/${bogusId}`);
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-badge')).toHaveClass(/not-found/, {
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: /isn't broadcasting/i })).toBeVisible();
		await expect(page.getByRole('link', { name: /Back to Run Onward/ })).toHaveAttribute(
			'href',
			'/'
		);
	});
});
