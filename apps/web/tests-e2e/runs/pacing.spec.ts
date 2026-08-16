import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — the pacing summary above the splits table.
 *
 * `pace_analysis.test.ts` pins the maths. What this spec pins is the rendered
 * behaviour it can't reach: which verdict the halves resolve to on a real run
 * row, that the grade-adjusted second opinion only appears when it disagrees
 * with raw pace, and that the splits table grows its grade-adjusted column
 * only when a split's terrain actually moves the number.
 */

const DEG_PER_M_LAT = 1 / 111_320;

/// A meridian-aligned track, points 10 m apart. `firstStepS` / `secondStepS`
/// are the seconds between fixes in each half, so a 10 m step at 6 s is
/// 600 s/km. `secondClimbM` lifts each second-half point by that many metres
/// (1 m over 10 m horizontal = a 10 % grade); the first half is always flat.
function track(opts: {
	points: number;
	firstStepS: number;
	secondStepS: number;
	withElevation: boolean;
	secondClimbM?: number;
}) {
	const half = opts.points / 2;
	const t0 = new Date('2026-04-12T08:00:00Z').getTime();
	const out = [];
	let tMs = t0;
	for (let i = 0; i < opts.points; i++) {
		const climb = Math.max(0, i - half + 1) * (opts.secondClimbM ?? 0);
		out.push({
			lat: 40 + i * 10 * DEG_PER_M_LAT,
			lng: -105,
			...(opts.withElevation ? { ele: 1500 + climb } : {}),
			ts: new Date(tMs).toISOString(),
		});
		tMs += (i < half ? opts.firstStepS : opts.secondStepS) * 1000;
	}
	return out;
}

test.describe('/runs/[id] — pacing summary', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a faster second half reads as a negative split, with no terrain caveat', async ({
		page,
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-12T08:00:00Z').toISOString(),
			distance_m: 990,
			duration_s: 6500,
			is_public: false,
			metadata: { activity_type: 'run' },
			track: track({ points: 100, firstStepS: 7, secondStepS: 6, withElevation: true }),
		});
		try {
			await page.goto(`/runs/${runId}`);
			const pacing = page.locator('.pacing');
			await expect(pacing).toBeVisible({ timeout: 15_000 });
			// The card names itself rather than borrowing the Splits heading.
			await expect(pacing.getByRole('heading', { name: 'Pacing' })).toBeVisible();
			await expect(pacing.locator('.pacing-verdict')).toHaveText('Negative split');
			await expect(pacing.locator('.pacing-summary')).toContainText('faster over the second half');
			// Flat ground: grade-adjusted pace is raw pace, so the second
			// opinion would restate the first and must stay hidden.
			await expect(pacing.locator('.pacing-gap')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a climbing second half reads as a fade, with an effort-even caveat', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-12T09:00:00Z').toISOString(),
			distance_m: 1990,
			duration_s: 1600,
			is_public: false,
			metadata: { activity_type: 'run' },
			track: track({
				points: 200,
				firstStepS: 6,
				secondStepS: 10,
				withElevation: true,
				secondClimbM: 1,
			}),
		});
		try {
			await page.goto(`/runs/${runId}`);
			const pacing = page.locator('.pacing');
			await expect(pacing).toBeVisible({ timeout: 15_000 });
			await expect(pacing.locator('.pacing-verdict')).toHaveText('Positive split');
			await expect(pacing.locator('.pacing-summary')).toContainText('slower over the second half');
			await expect(pacing.locator('.pacing-gap')).toContainText(
				'your effort was even across both halves',
			);
			// The climbing split moves far enough off its raw pace to earn the column.
			await expect(page.locator('.splits-table th', { hasText: 'Grade-adj.' })).toBeVisible();
			await expect(page.locator('.splits-hint')).toBeVisible();
		} finally {
			await deleteRun(runId);
		}
	});

	test('a run with no elevation shows the pacing summary but no grade-adjusted column', async ({
		page,
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-12T10:00:00Z').toISOString(),
			distance_m: 990,
			duration_s: 594,
			is_public: false,
			metadata: { activity_type: 'run' },
			track: track({ points: 100, firstStepS: 6, secondStepS: 6, withElevation: false }),
		});
		try {
			await page.goto(`/runs/${runId}`);
			const pacing = page.locator('.pacing');
			await expect(pacing).toBeVisible({ timeout: 15_000 });
			await expect(pacing.locator('.pacing-verdict')).toHaveText('Even split');
			await expect(pacing.locator('.pacing-gap')).toHaveCount(0);
			await expect(page.locator('.splits-table th', { hasText: 'Grade-adj.' })).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});
});
