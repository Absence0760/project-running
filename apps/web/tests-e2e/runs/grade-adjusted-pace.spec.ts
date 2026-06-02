import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — Grade-Adjusted Pace key-stat (decisions §116 sibling, §114).
 *
 * The pure Minetti model has TS↔Dart unit parity (grade_adjusted_pace.test.ts
 * ↔ grade_adjusted_pace_test.dart). What this spec pins is the rendered
 * behaviour the unit tests can't reach:
 *   - a hilly run (GAP diverges from raw pace by ≥2 s/km) shows the
 *     "Grade-Adj. Pace" cell;
 *   - a flat run (GAP == raw pace) hides it — the show-threshold + the
 *     keyStatsCount parity bump are exercised end-to-end.
 * A regression that flipped the threshold sign or broke the $derived wiring
 * would surface here, the same way hr-zones.spec.ts guards that sibling cell.
 */

const LABEL = 'Grade-Adj. Pace';
const DEG_PER_M_LAT = 1 / 111_320;

/// 30 points ~10 m apart, one per 6 s. `climbPerPointM` sets the grade
/// (1 m over 10 m horizontal = 10 %); 0 = dead flat.
function track(climbPerPointM: number) {
	const t0 = new Date('2026-04-12T08:00:00Z').getTime();
	return Array.from({ length: 30 }, (_, i) => ({
		lat: 40 + i * 10 * DEG_PER_M_LAT,
		lng: -105,
		ele: 1500 + i * climbPerPointM,
		ts: new Date(t0 + i * 6_000).toISOString(),
	}));
}

test.describe('/runs/[id] — Grade-Adjusted Pace cell', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('hilly run shows the Grade-Adj. Pace cell, faster than raw pace', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-12T08:00:00Z').toISOString(),
			distance_m: 290,
			duration_s: 174,
			is_public: false,
			metadata: { activity_type: 'run' },
			track: track(1), // 10 % climb
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.locator('.key-stats')).toBeVisible({ timeout: 10_000 });

			const gapCell = page
				.locator('.key-stat', { has: page.locator('.key-stat-label', { hasText: LABEL }) })
				.locator('.key-stat-value');
			await expect(gapCell).toBeVisible({ timeout: 5_000 });

			// Uphill GAP is the effort-equivalent FLAT pace, i.e. faster (smaller
			// mm:ss) than the raw average pace shown in the Avg Pace cell.
			const paceToSec = (s: string) => {
				const m = s.match(/(\d+):(\d{2})/);
				return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : NaN;
			};
			const gapSec = paceToSec(await gapCell.innerText());
			const avgSec = paceToSec(
				await page
					.locator('.key-stat', { has: page.locator('.key-stat-label', { hasText: 'Avg Pace' }) })
					.locator('.key-stat-value')
					.innerText(),
			);
			expect(gapSec).toBeLessThan(avgSec);
		} finally {
			await deleteRun(runId);
		}
	});

	test('flat run hides the Grade-Adj. Pace cell (GAP == raw pace)', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-12T09:00:00Z').toISOString(),
			distance_m: 290,
			duration_s: 174,
			is_public: false,
			metadata: { activity_type: 'run' },
			track: track(0), // dead flat
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(page.locator('.key-stats')).toBeVisible({ timeout: 10_000 });
			// Avg Pace renders, but the Grade-Adj. Pace cell must be absent.
			await expect(
				page.locator('.key-stat-label', { hasText: 'Avg Pace' }),
			).toBeVisible();
			await expect(page.locator('.key-stat-label', { hasText: LABEL })).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});
});
