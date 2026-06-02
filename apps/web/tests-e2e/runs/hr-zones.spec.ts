import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — Heart Rate Zones section.
 *
 * Three rendering branches in `+page.svelte` (lines 1163-1210):
 *
 *   1. Track carries per-point `bpm` → renders `hr-stats` (avg/min/
 *      max), a 5-segment `hr-bar`, and a `hr-legend` with per-zone
 *      labels + percentages.
 *   2. No per-point bpm but `metadata.avg_bpm` is set → empty-state
 *      copy that quotes the average: "Only the run's average heart
 *      rate was captured (N bpm)."
 *   3. Neither per-point bpm NOR `metadata.avg_bpm` → bare empty
 *      state: "No heart-rate data on this run."
 *
 * The pure zone math has unit-test parity (`hr_zones_test.dart`, 8
 * tests). What this spec pins is the rendered surface — that the
 * page actually picks the right branch for each run shape, and that
 * the bar segments cap at 100% sum. A regression that flipped the
 * branch order (rendered "No HR data" even when avg_bpm was set)
 * would surface here.
 */

test.describe('/runs/[id] — Heart Rate Zones section', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('track with per-point bpm renders hr-stats + 5-segment hr-bar', async ({ page }) => {
		// Plant 10 track points whose bpm values span Zone 1 (default
		// cutoff 114) through Zone 4 (171). Default cutoffs in the
		// page: [114, 133, 152, 171, 190] = 60/70/80/90/100% of
		// HRmax=190. Pick samples in 110 / 120 / 145 / 165 to cover
		// four zones (Recovery / Easy / Aerobic / Threshold).
		const baseLat = -37.8136;
		const baseLng = 144.9631;
		const startedAt = new Date('2026-04-10T08:00:00Z').toISOString();
		const tBase = new Date('2026-04-10T08:00:00Z').getTime();
		const bpmSamples = [110, 110, 120, 120, 120, 145, 145, 165, 165, 110];
		const track = bpmSamples.map((bpm, i) => ({
			lat: baseLat + i * 0.0001,
			lng: baseLng + i * 0.0001,
			ts: new Date(tBase + i * 60_000).toISOString(),
			bpm
		}));

		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 1_000,
			duration_s: 600,
			is_public: false,
			metadata: { activity_type: 'run', avg_bpm: 130 },
			track
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
				.toBeVisible({ timeout: 10_000 });

			// hr-stats: avg / min / max all populated.
			const stats = page.locator('.hr-stat-value');
			await expect(stats).toHaveCount(3);
			// Min sample is 110, max is 165 — pin both ends.
			await expect(page.locator('.hr-stat-label', { hasText: 'Min' })
				.locator('+ .hr-stat-value')).toHaveText('110');
			await expect(page.locator('.hr-stat-label', { hasText: 'Max' })
				.locator('+ .hr-stat-value')).toHaveText('165');
			// Avg of [110,110,120,120,120,145,145,165,165,110] = 131.
			// Allow ±1 for the round-half-to-even behaviour on .toFixed
			// elsewhere — page uses Math.round which is half-to-up.
			const avgText = await page
				.locator('.hr-stat-label', { hasText: 'Avg' })
				.locator('+ .hr-stat-value')
				.innerText();
			const avgNum = parseInt(avgText, 10);
			expect(avgNum).toBeGreaterThanOrEqual(130);
			expect(avgNum).toBeLessThanOrEqual(132);

			// hr-bar segments — five zones each render their own
			// segment, including 0% ones. A regression that omitted
			// empty zones would reduce the count below 5.
			const segments = page.locator('.hr-segment');
			await expect(segments).toHaveCount(5);

			// hr-legend lists all five zone names by default.
			for (const label of ['Recovery', 'Easy', 'Aerobic', 'Threshold', 'Max']) {
				await expect(
					page.locator('.hr-legend .hr-zone-name', { hasText: label })
				).toBeVisible();
			}

			// Percentages on the legend sum to ~100 (allow ±1 for
			// integer rounding on each row).
			const pctTexts = await page
				.locator('.hr-legend .hr-zone-pct')
				.allInnerTexts();
			const total = pctTexts
				.map((t) => parseInt(t.replace(/[^0-9]/g, ''), 10))
				.reduce((a, b) => a + b, 0);
			expect(total).toBeGreaterThanOrEqual(99);
			expect(total).toBeLessThanOrEqual(101);
		} finally {
			await deleteRun(runId);
		}
	});

	test('metadata.avg_bpm without per-point bpm renders the "Only average" empty state', async ({
		page
	}) => {
		// Historical-row shape: imported Strava activities that
		// surface avg_bpm but no per-point samples (or the import
		// dropped them). The page must report this honestly rather
		// than render fake zone bars from the single average.
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			metadata: { activity_type: 'run', avg_bpm: 142 }
			// No track planted -> page falls into the empty-state branch.
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
				.toBeVisible({ timeout: 10_000 });

			// hr-empty copy quotes the average. Pin the literal `142`
			// so a refactor that lost the `{avgBpm}` interpolation
			// would fail (the contract is "tell the user WHAT
			// average we have, not just that we have one").
			await expect(page.locator('.hr-empty')).toBeVisible();
			await expect(page.locator('.hr-empty')).toContainText(
				/Only the run.s average heart rate/i
			);
			await expect(page.locator('.hr-empty')).toContainText(/142/);

			// Zone bar + legend must NOT render — empty state path.
			await expect(page.locator('.hr-segment')).toHaveCount(0);
			await expect(page.locator('.hr-legend')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('no track + no avg_bpm renders the "No heart-rate data" empty state', async ({
		page
	}) => {
		// Most common shape today: manually-entered run with no
		// recorder pipe-through. The empty-state copy is the bare
		// fallback — no average to quote.
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			metadata: { activity_type: 'run' }
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
				.toBeVisible({ timeout: 10_000 });

			await expect(page.locator('.hr-empty')).toContainText(
				/No heart-rate data on this run/
			);
			// And specifically: no "average" copy this time — the
			// branch must NOT spill into the avg_bpm path on
			// metadata={} input.
			await expect(page.locator('.hr-empty')).not.toContainText(
				/Only the run.s average/
			);
			await expect(page.locator('.hr-segment')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('trackless indoor run renders zones from the HR sidecar (decisions §116)', async ({
		page
	}) => {
		// Treadmill shape: no GPS track, but an hr_series sidecar carries the
		// per-point bpm. The page must fall back to the sidecar and render the
		// zone bar instead of the "only average" / "no data" empty state.
		const bpmSamples = [110, 110, 120, 120, 145, 145, 165, 165, 120, 110];
		const tBase = new Date('2026-04-11T08:00:00Z').getTime();
		const hrSeries = bpmSamples.map((bpm, i) => ({
			bpm,
			ts: new Date(tBase + i * 60_000).toISOString()
		}));
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-11T08:00:00Z').toISOString(),
			distance_m: 5_000,
			duration_s: 1_800,
			is_public: false,
			metadata: { activity_type: 'run', avg_bpm: 130, indoor: true },
			hrSeries
			// No `track` → the GPS-track bpm path is empty; the sidecar drives it.
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
				.toBeVisible({ timeout: 10_000 });

			// The zone bar must render (sidecar fed the breakdown), NOT the
			// empty state that would show if the sidecar were ignored.
			await expect(page.locator('.hr-segment')).toHaveCount(5);
			await expect(page.locator('.hr-empty')).toHaveCount(0);

			// min 110 / max 165 come from the sidecar, proving it was read.
			await expect(page.locator('.hr-stat-label', { hasText: 'Min' })
				.locator('+ .hr-stat-value')).toHaveText('110');
			await expect(page.locator('.hr-stat-label', { hasText: 'Max' })
				.locator('+ .hr-stat-value')).toHaveText('165');
		} finally {
			await deleteRun(runId);
		}
	});

	test('per-point bpm with one sample only still renders the bar (no NaN / no crash)', async ({
		page
	}) => {
		// Edge case: a sub-1-minute run with a single bpm sample.
		// Avg = Min = Max = the single value, and 100% of time-in-zone
		// falls in whichever zone it lands. Pin that the page doesn't
		// NaN out on the divide-by-N path when N=1.
		const track = [
			{
				lat: -37.8136,
				lng: 144.9631,
				ts: '2026-04-10T08:00:00Z',
				bpm: 140
			}
		];
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 20,
			duration_s: 5,
			is_public: false,
			metadata: { activity_type: 'run' },
			track
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Heart Rate Zones' }))
				.toBeVisible({ timeout: 10_000 });

			// avg / min / max all = 140
			for (const label of ['Avg', 'Min', 'Max']) {
				await expect(
					page.locator('.hr-stat-label', { hasText: label })
						.locator('+ .hr-stat-value')
				).toHaveText('140');
			}
			// hr-bar still renders 5 segments — no NaN width.
			const segments = page.locator('.hr-segment');
			await expect(segments).toHaveCount(5);
			// No segment has a width: NaN% — read the inline style.
			const widths = await segments.evaluateAll((els) =>
				els.map((el) => (el as HTMLElement).style.width)
			);
			for (const w of widths) {
				expect(w).not.toContain('NaN');
				expect(w).toMatch(/^\d+(\.\d+)?%$/);
			}
		} finally {
			await deleteRun(runId);
		}
	});
});
