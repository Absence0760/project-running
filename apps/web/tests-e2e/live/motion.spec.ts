import { expect, test } from '@playwright/test';

import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /live/[id] — the stopped-runner readout (`lib/safety/live_motion.ts`).
 *
 * Staleness honesty covers the runner we CANNOT see. This covers the one we
 * can: a phone still pinging every few seconds from the same spot used to
 * render as a fresh green LIVE dot with no pace readout at all (the delta is
 * zero, so the derived pace returned null and the stat vanished) — "not
 * moving" and "no data" looked identical.
 *
 * Geometry: a fixed point at lat -37.80 (Melbourne, clear of the Sydney seed
 * privacy zone, so the `live_run_pings_drop_in_zone` trigger keeps the rows).
 */

const SPOT = { lat: -37.8, lng: 144.96 };

/// Pings every 30 s across `spanS`, ending `freshS` ago so the last fix is
/// inside the 90 s staleness window.
function pingSeries(opts: {
	spanS: number;
	freshS: number;
	metresPerStep: number;
	startDistanceM: number;
}) {
	const steps = Math.floor(opts.spanS / 30);
	const endMs = Date.now() - opts.freshS * 1000;
	return Array.from({ length: steps + 1 }, (_, i) => ({
		...SPOT,
		distance_m: opts.startDistanceM + i * opts.metresPerStep,
		elapsed_s: 600 + i * 30,
		at: new Date(endMs - (steps - i) * 30_000).toISOString(),
	}));
}

async function seedLiveRun(): Promise<string> {
	return insertRun({
		user_id: USER_A.id,
		started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
		distance_m: 4_400,
		duration_s: 3_600,
		is_public: true,
	});
}

test.describe('/live/[id] — stopped-runner readout (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('fresh pings from one spot report how long the runner has been there', async ({
		page,
	}) => {
		const runId = await seedLiveRun();
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				// 5 minutes of pings, odometer frozen, last fix 10 s old.
				points: pingSeries({
					spanS: 300,
					freshS: 10,
					metresPerStep: 0,
					startDistanceM: 900,
				}),
			});

			await page.goto(`/live/${runId}`);

			const chip = page.getByTestId('motion-stopped');
			await expect(chip).toBeVisible({ timeout: 10_000 });
			// The stop fills the whole buffer, so the duration is a floor.
			await expect(chip).toContainText('at least 5 min');
		} finally {
			await deleteRun(runId);
		}
	});

	test('a runner covering ground shows no stopped readout', async ({ page }) => {
		const runId = await seedLiveRun();
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				// Same span + freshness, but 90 m per 30 s step (~5:33 /km).
				points: pingSeries({
					spanS: 300,
					freshS: 10,
					metresPerStep: 90,
					startDistanceM: 900,
				}),
			});

			await page.goto(`/live/${runId}`);

			// The live strip has rendered (so the absence below is a real
			// verdict, not an unloaded page).
			await expect(page.getByTestId('recent-pace')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('motion-stopped')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a stale fix reports neither motion nor a current recent pace', async ({ page }) => {
		const runId = await seedLiveRun();
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				// Identical stopped shape, but the newest fix is 10 min old:
				// the runner may have walked out of signal, so "not moving"
				// is unknowable and must not be claimed.
				points: pingSeries({
					spanS: 300,
					freshS: 600,
					metresPerStep: 0,
					startDistanceM: 900,
				}),
			});

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge.stale')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('motion-stopped')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a stale fix relabels the recent pace as the pace when last seen', async ({ page }) => {
		const runId = await seedLiveRun();
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: pingSeries({
					spanS: 300,
					freshS: 600,
					metresPerStep: 90,
					startDistanceM: 900,
				}),
			});

			await page.goto(`/live/${runId}`);

			const pace = page.getByTestId('recent-pace');
			await expect(pace).toBeVisible({ timeout: 10_000 });
			await expect(pace).toContainText('When last seen');
			await expect(pace).not.toContainText('Recent');
		} finally {
			await deleteRun(runId);
		}
	});
});
