import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /dashboard/period/[type]/[date] — standalone period summary deep link.
 *
 * The dashboard's "This Week" stat tile opens a PeriodSummary modal
 * (covered in dashboard.spec.ts). This standalone route is the
 * deep-linkable version of that modal — used by external links and
 * by users who want a permanent URL for a specific week's summary.
 */

test.describe('/dashboard/period/[type]/[date]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('week deep-link mounts PeriodSummary against the seeded date', async ({
		page
	}) => {
		// Pin a week within the seeded run range so the page renders
		// against real data, not an empty state. Seeded runs are dated
		// in March-April 2026.
		await page.goto('/dashboard/period/week/2026-04-01');

		// PeriodSummary mounts its own week/month toggle inside the
		// page body; that's the most stable signal that the body
		// loaded past the loading shell.
		await expect(
			page.getByRole('button', { name: 'Week' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('month deep-link with type=month mounts the same surface', async ({
		page
	}) => {
		// `type` is a narrow union (week / month). A regression that
		// silently fell through to week for any non-week input would
		// surface here as the Month button missing.
		await page.goto('/dashboard/period/month/2026-04-01');

		await expect(
			page.getByRole('button', { name: 'Month' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('all-time deep-link with type=all mounts the summary', async ({
		page
	}) => {
		// `all` is the third period type — no date filter, lifetime totals.
		// The date segment is irrelevant for all-time but must still parse;
		// the "All time" toggle being active is the signal it mounted.
		await page.goto('/dashboard/period/all/2026-04-01');

		await expect(
			page.getByRole('button', { name: 'All time' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('invalid date string falls back to today (no crash)', async ({
		page
	}) => {
		// parsePeriodDate returns `new Date()` on a non-finite parse.
		// Pin the fallback so a stale link with a malformed date
		// doesn't crash the page. The Week/Month toggle being visible
		// is the signal that PeriodSummary mounted past the parse.
		await page.goto('/dashboard/period/week/not-a-date');
		await expect(
			page.getByRole('button', { name: 'Week' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('page chrome is localised (kicker + heading + back link render, not raw keys)', async ({
		page
	}) => {
		// The page was fully hardcoded English; it now resolves every
		// string through m(). A missing/broken key renders the raw dotted
		// key ("period.heading") instead of the copy — pin the resolved
		// text so that regression is caught (default locale = en).
		await page.goto('/dashboard/period/week/2026-04-01');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Period summary' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Weekly summary')).toBeVisible();
		await expect(
			page.getByRole('link', { name: /Back to dashboard/ })
		).toBeVisible();
	});
});
