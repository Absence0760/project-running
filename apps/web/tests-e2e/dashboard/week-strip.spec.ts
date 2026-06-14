import { expect, test } from '@playwright/test';

import { deleteRun, insertRun, withCleanCurrentWeek } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard — the "This Week" calendar-week activity ribbon
 * (ThisWeekStrip.svelte over lib/training/current_week.ts).
 *
 * The strip anchors on the REAL calendar week (now = new Date()), so the
 * test inserts a run dated to *today* — guaranteed inside the current week
 * on any run day — and asserts the ribbon surfaces it. Cleans up the run
 * afterwards so the rest of the dashboard suite sees the seeded baseline.
 */

test.describe('/dashboard This Week strip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the week ribbon and folds in a run logged today', async ({ page }) => {
		// The seed plants a now()-relative "Morning easy 8K" run for runner,
		// so the current week isn't empty out of the box. Clear it (restored
		// in finally so the /nutrition + readiness specs still see it) so the
		// strip total + today's cell reflect ONLY our inserted run.
		const restoreWeek = await withCleanCurrentWeek(USER_A.id);

		// 06:00 local today, 7.50 km — well inside the current calendar week.
		const today = new Date();
		today.setHours(6, 0, 0, 0);
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: today.toISOString(),
			duration_s: 35 * 60,
			distance_m: 7500,
		});

		try {
			await page.goto('/dashboard');

			// The strip's section is labelled "This Week" (also the stat-card
			// label) — scope to the region whose accessible name is the strip
			// title and whose role is region (the <section aria-label>).
			const strip = page.getByRole('region', { name: 'This Week' });
			await expect(strip).toBeVisible();

			// The 7.5 km appears twice — once in the header total, once in
			// today's day cell. Both must be present (proves the strip both
			// summed the week and bucketed the run onto its day).
			await expect(strip.getByText('7.5 km').first()).toBeVisible();
			await expect(strip.getByText('7.5 km')).toHaveCount(2);
		} finally {
			await deleteRun(runId);
			await restoreWeek();
		}
	});
});
