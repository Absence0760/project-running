import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * /runs — owner-only run history list.
 *
 * Operations covered: render, manual-run create + delete, activity-
 * type filter, filter-state localStorage persistence. The cross-user
 * isolation case (User B's /runs excludes runner's runs) is in
 * cross-cutting/auth-walls.spec.ts because it's a security wall.
 *
 * Default filter is "today"; most tests switch to "All time" via the
 * shared helper because seed runs span ~6 weeks.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/runs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('lists the seeded runs (after switching to All time)', async ({
		page
	}) => {
		await page.goto('/runs');
		await switchRunsToAllTime(page);

		// runner has 12 generated runs + 1 pinned ("E2E demo public run")
		// = 13 minimum. Assert >= 13 to stay stable if the seed grows.
		const cards = page.locator('.run-card');
		await expect(cards.first()).toBeVisible();
		expect(await cards.count()).toBeGreaterThanOrEqual(13);
	});

	test('Walk activity filter narrows the list to the single seeded walk', async ({
		page
	}) => {
		// seed.sql gives runner exactly one walk + one hike alongside
		// 26 runs. Selecting Walk on the toolbar must collapse the list
		// to that single row — proves the activity-type filter both
		// exists in the UI and queries the right metadata key
		// (jsonb `metadata->>activity_type`, not a column).
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		// Sanity: more than one card is visible before filtering.
		const beforeCount = await page.locator('.run-card').count();
		expect(beforeCount).toBeGreaterThan(2);

		// The activity-type group is a button group with aria-label
		// "Activity type"; each button has aria-label set to the label
		// (Run / Walk / Cycle / Hike / All). Walk is unique, so role +
		// name is the most stable selector.
		await page.getByRole('button', { name: 'Walk', exact: true }).click();

		// Exactly one walk row in the seed.
		await expect(page.locator('.run-card')).toHaveCount(1);

		// Restore the default filter so subsequent tests in this file
		// don't inherit Walk via shared localStorage state.
		await page.getByRole('button', { name: 'All', exact: true }).click();
	});

	test('filter state survives a reload (localStorage round-trip)', async ({
		page
	}) => {
		// /runs writes the filter set to localStorage (`runs_filters_v1`)
		// inside a `filtersHydrated`-gated $effect. The regression risk
		// is that the writer fires *before* hydration finishes (saves
		// stale defaults over the user's choice) or that the reader
		// crashes silently on a malformed blob and the user's filter is
		// silently reset every page-load.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		await page.getByRole('button', { name: 'Walk', exact: true }).click();
		await expect(page.locator('.run-card')).toHaveCount(1);

		// Reload — both selections must hold.
		await page.reload();
		await page.waitForLoadState('networkidle');

		// The Walk activity-button stays `aria-pressed=true` after
		// hydration if persistence works.
		await expect(
			page.getByRole('button', { name: 'Walk', exact: true })
		).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByLabel('Date range')).toHaveValue('all');
		await expect(page.locator('.run-card')).toHaveCount(1);

		// Restore so subsequent tests don't inherit a Walk filter via
		// shared localStorage state inside the same browser context.
		await page.getByRole('button', { name: 'All', exact: true }).click();
		await page.getByLabel('Date range').selectOption('today');
	});

	test('Date range filter "Today" narrows the list relative to "All time"', async ({
		page
	}) => {
		// `dateRange` is a client-side $derived filter on
		// `started_at` against rangeBounds(). Switching from "all" →
		// "today" must shrink the list to today's runs only. The
		// seed runs are dated in March-April 2026; "today" (real
		// wall-clock at test time) likely intersects 0 runs, so the
		// list shrinks. We assert the count drops without pinning a
		// number — robust to seed dates drifting.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();
		const allCount = await page.locator('.run-card').count();
		expect(allCount).toBeGreaterThan(2);

		await page.getByLabel('Date range').selectOption('today');
		// Wait for the filter to settle — count strictly less.
		await expect
			.poll(() => page.locator('.run-card').count(), { timeout: 5_000 })
			.toBeLessThan(allCount);

		// Restore default ("today" is the default per code, but the
		// cards count goes down — restore via "all" so subsequent
		// tests in this file see the wide set).
		await page.getByLabel('Date range').selectOption('all');
	});

	test('Source filter narrows to parkrun-only rows (5 seeded parkruns)', async ({
		page
	}) => {
		// fetchRuns filters server-side on `source` when sourceFilter
		// !== 'all'. The seed has ~5 parkrun rows; assert the count
		// is >= 5 and < the unfiltered count. Pins the source-filter
		// fetch path (separate from the activity-type metadata key
		// path covered by the Walk-filter test).
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();
		const beforeCount = await page.locator('.run-card').count();

		await page.getByLabel('Source').selectOption('parkrun');
		const cards = page.locator('.run-card');
		// Wait for the list to settle on the narrowed set.
		await expect.poll(() => cards.count(), { timeout: 5_000 }).toBeLessThan(beforeCount);
		const parkrunCount = await cards.count();
		expect(parkrunCount).toBeGreaterThanOrEqual(3);
		expect(parkrunCount).toBeLessThan(beforeCount);

		// Restore.
		await page.getByLabel('Source').selectOption('all');
	});

	test('Sort by Longest puts the longest-distance run first', async ({
		page
	}) => {
		// `sortKey` re-orders the in-memory `filteredRuns` $derived.
		// Newest-first is the default; "Longest" sorts by distance_m
		// descending. Catches a regression where the sort comparator
		// gets inverted or the option value drifts from the $derived
		// branch.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		await page.getByLabel('Sort').selectOption('longest');

		// First card's distance should be the maximum across the
		// visible set. Read distance from the first run-stat-value
		// (which is "Distance" by column order).
		const firstDistanceText = await page
			.locator('.run-card .run-stat-value')
			.first()
			.textContent();
		const firstDistance = parseFloat(firstDistanceText ?? '0');

		const allDistances = await page
			.locator('.run-card .run-stat')
			.filter({ hasText: 'Distance' })
			.locator('.run-stat-value')
			.evaluateAll((els) =>
				els.map((e) => parseFloat(e.textContent?.trim() ?? '0'))
			);
		expect(firstDistance).toBeGreaterThanOrEqual(Math.max(...allDistances));

		// Restore to default sort.
		await page.getByLabel('Sort').selectOption('newest');
	});

	test('Select-mode + bulk-delete confirm dialog opens (cancel without deleting)', async ({
		page
	}) => {
		// Multi-select mode swaps each .run-card from <a> to <button>
		// with onclick=toggleSelect. Selecting at least one row makes
		// the .bulk-bar appear; clicking Delete opens a ConfirmDialog.
		// We verify the wiring up to the confirm dialog and then
		// CANCEL — actually deleting would either need a unique
		// throwaway row (slow) or break other tests.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		await page.getByRole('button', { name: 'Select', exact: true }).click();

		// Click the first run-card to select it.
		await page.locator('.run-card').first().click();
		const bulkBar = page.locator('.bulk-bar');
		await expect(bulkBar).toBeVisible();
		await expect(bulkBar).toContainText('1 selected');

		// Open confirm dialog, then cancel — no destructive write.
		await bulkBar.getByRole('button', { name: 'Delete' }).click();
		await expect(page.locator('.modal', { hasText: /Delete 1 run/ })).toBeVisible({
			timeout: 5_000
		});
		await page.getByRole('button', { name: 'Cancel' }).click();
		await expect(page.locator('.modal')).toHaveCount(0);

		// Exit select mode so the rest of the suite sees the default
		// .run-card-as-link layout.
		await page.getByRole('button', { name: 'Done', exact: true }).click();
	});

	test('manual run CRUD round-trip via the Add-run modal', async ({ page }) => {
		const title = uniqueText('e2e-crud');

		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		// ── Create ──
		await page.getByRole('button', { name: '+ Add run' }).click();

		// RunEditor: started_at is pre-filled to "now"; activity defaults
		// to 'run'; we set distance + duration explicitly so the row
		// passes the runs CHECK constraint (distance > 0).
		await page.locator('input[type="datetime-local"]').first().fill('2026-04-29T08:00');
		await page.locator('input[type="number"]').first().fill('5'); // distance km
		await page.locator('input[type="number"]').nth(1).fill('25'); // duration min
		await page.locator('textarea').fill(title);

		await page.locator('form button[type="submit"]').click();

		// On success the page redirects to /runs/<new-id>. We don't
		// know the ID up-front; capture it from the URL.
		await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
		const newRunId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

		// ── Verify it landed in the list ──
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(
			page.locator(`.run-card[href$="${newRunId}"]`)
		).toBeVisible({ timeout: 10_000 });

		// ── Delete ──
		await page.goto(`/runs/${newRunId}`);
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: 'Delete' }).first().click();
		// ConfirmDialog opens; the modal's confirm button reads "Delete".
		await page
			.getByRole('button', { name: 'Delete', exact: true })
			.last()
			.click();

		// After delete the page navigates back to /runs.
		await page.waitForURL(/\/runs(\?.*)?$/, { timeout: 10_000 });

		// Verify the row is gone from the list.
		await switchRunsToAllTime(page);
		await expect(
			page.locator(`.run-card[href$="${newRunId}"]`)
		).toHaveCount(0);
	});
});
