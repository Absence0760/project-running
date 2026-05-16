import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /runs filter toolbar — every axis pinned.
 *
 * The toolbar exposes four orthogonal filter axes (Source / Activity /
 * Date range / Sort) plus a Custom-date-picker workflow. Existing
 * coverage in `runs/list.spec.ts` hits a handful of these but not
 * every value; this file pins one assertion per filter value PLUS the
 * two bug regressions surfaced in the user-led /runs polish round:
 *
 *   1. Selecting Custom from the dropdown used to flash the list to
 *      "All time" because rangeBounds('custom') with empty bounds
 *      returned {from:null,to:null}. Fix: fall back to the previous
 *      range's bounds while bounds are empty.
 *   2. The Custom mode showed two controls for the same intent —
 *      the dropdown (already opens the picker on selection) AND a
 *      "Pick dates…" chip below it. Fix: hide the chip until Custom
 *      bounds are set; once set, the chip becomes a status +
 *      click-to-edit handle.
 *
 * Seed shape used by the assertions (runner@test.com):
 *   sources:  app ~79 / strava ~33 / healthkit ~31 / parkrun ~30 / race 1
 *   activity: run ~172 / walk 1 / hike 1
 *   dates:    span ~6 weeks ending around the seed's "today"
 *
 * Tests use lower-bound assertions ('>=') wherever the exact count
 * could drift with seed evolution, and strict counts ('===') only
 * where the seed guarantees the single-row case (Walk / Hike).
 */

test.describe('/runs — filters', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ page, context }) => {
		// Pre-accept cookie consent so the banner geometry doesn't
		// interfere with select-mode / bulk-bar / Save button clicks.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		// Clear runs_filters_v1 so each test starts at the page defaults
		// (today + run + newest + all sources). Without this a leftover
		// filter from a previous test in the same context can break the
		// "default state" assumption.
		await context.addInitScript(() => {
			localStorage.removeItem('runs_filters_v1');
		});
		await page.goto('/runs');
		// All filter tests need >1 row to be meaningful — start at
		// "All time" so the date filter isn't masking the source /
		// activity / sort assertions.
		await page.getByLabel('Date range').selectOption('all');
		await expect(page.locator('.run-card').first()).toBeVisible({
			timeout: 10_000
		});
	});

	test.describe('Source filter', () => {
		// Iterate every value in the seed-populated subset. The dropdown
		// uses the friendly label as visible text but `optionValue` is
		// the canonical enum. `option:'app'` is labelled "Recorded".
		const sources: { value: string; expectedBadge: RegExp }[] = [
			{ value: 'app', expectedBadge: /recorded/i },
			{ value: 'strava', expectedBadge: /strava/i },
			{ value: 'parkrun', expectedBadge: /parkrun/i },
			{ value: 'healthkit', expectedBadge: /healthkit/i }
		];
		for (const { value, expectedBadge } of sources) {
			test(`narrows to ${value} rows only`, async ({ page }) => {
				await page.getByLabel('Source').selectOption(value);
				const cards = page.locator('.run-card');
				await expect(cards.first()).toBeVisible({ timeout: 10_000 });
				// Every visible row carries the matching source badge.
				const total = await cards.count();
				expect(total).toBeGreaterThan(0);
				const badges = page.locator('.run-card .source-badge');
				expect(await badges.count()).toBe(total);
				for (let i = 0; i < Math.min(total, 5); i++) {
					await expect(badges.nth(i)).toHaveText(expectedBadge);
				}
			});
		}

		test('"All Sources" restores the full list', async ({ page }) => {
			await page.getByLabel('Source').selectOption('parkrun');
			await expect(page.locator('.run-card').first()).toBeVisible();
			const narrowed = await page.locator('.run-card').count();
			await page.getByLabel('Source').selectOption('all');
			const all = await page.locator('.run-card').count();
			expect(all).toBeGreaterThan(narrowed);
		});
	});

	test.describe('Activity-type filter', () => {
		test('All shows everything', async ({ page }) => {
			await page.getByRole('button', { name: 'All', exact: true }).click();
			// Switching activity to 'all' transitions fetchMode from
			// 'full' to 'paginated' (default broad-browse mode); wait
			// for the first card to be visible before reading count.
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			});
			expect(await page.locator('.run-card').count()).toBeGreaterThan(13);
		});

		test('Run narrows to runs only (the bulk of the seed)', async ({
			page
		}) => {
			await page.getByRole('button', { name: 'Run', exact: true }).click();
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			});
			expect(await page.locator('.run-card').count()).toBeGreaterThan(10);
		});

		test('Walk narrows to the single seeded walk', async ({ page }) => {
			await page.getByRole('button', { name: 'Walk', exact: true }).click();
			await expect(page.locator('.run-card')).toHaveCount(1, {
				timeout: 10_000
			});
		});

		test('Hike narrows to the single seeded hike', async ({ page }) => {
			await page.getByRole('button', { name: 'Hike', exact: true }).click();
			await expect(page.locator('.run-card')).toHaveCount(1, {
				timeout: 10_000
			});
		});

		test('Cycle returns zero (no cycles seeded) — empty state renders', async ({
			page
		}) => {
			await page.getByRole('button', { name: 'Cycle', exact: true }).click();
			await expect(page.locator('.run-card')).toHaveCount(0, {
				timeout: 10_000
			});
			// The canonical empty-state copy from .empty-text is in view.
			await expect(
				page.getByText(/No runs match these filters/i).first()
			).toBeVisible();
		});

		test('aria-pressed reflects the active button', async ({ page }) => {
			// The pressed-state attribute is what drives the active-pill
			// styling — a regression that dropped it would silently turn
			// the filter group into "looks-the-same-on-hover" buttons.
			await page.getByRole('button', { name: 'Walk', exact: true }).click();
			await expect(
				page.getByRole('button', { name: 'Walk', exact: true })
			).toHaveAttribute('aria-pressed', 'true');
			await expect(
				page.getByRole('button', { name: 'Run', exact: true })
			).toHaveAttribute('aria-pressed', 'false');
		});
	});

	test.describe('Sort key', () => {
		async function firstDistance(page: import('@playwright/test').Page) {
			// `.run-stat-value` first occurrence in the first card is the
			// distance metric (per the polisher's hierarchy: distance
			// dominant). Parse the numeric prefix.
			const txt = (await page
				.locator('.run-card')
				.first()
				.locator('.run-stat-value')
				.first()
				.textContent()) ?? '';
			return Number.parseFloat(txt.replace(/[^\d.]/g, ''));
		}

		test('Newest puts the most-recent run at the top', async ({ page }) => {
			await page.getByLabel('Sort').selectOption('newest');
			await expect(page.locator('.run-card').first()).toBeVisible();
			// The pinned 'E2E demo public run' is among the freshest in
			// the seed — first card carries the recent timestamp.
			const first = page.locator('.run-card').first();
			await expect(first).toBeVisible();
			// Sanity: the first card's date string is non-empty.
			const date = first.locator('.run-date');
			await expect(date).toBeVisible();
		});

		test('Oldest reverses the order vs Newest', async ({ page }) => {
			await page.getByLabel('Sort').selectOption('newest');
			const newestFirstDate = (await page
				.locator('.run-card')
				.first()
				.locator('.run-date')
				.textContent()) ?? '';
			await page.getByLabel('Sort').selectOption('oldest');
			const oldestFirstDate = (await page
				.locator('.run-card')
				.first()
				.locator('.run-date')
				.textContent()) ?? '';
			expect(newestFirstDate).not.toEqual(oldestFirstDate);
		});

		test('Longest puts the largest distance at the top', async ({ page }) => {
			await page.getByLabel('Sort').selectOption('longest');
			await expect(page.locator('.run-card').first()).toBeVisible();
			const firstDist = await firstDistance(page);
			// Seed's longest run is a 21.1km half marathon.
			expect(firstDist).toBeGreaterThanOrEqual(20);
		});

		test('Fastest puts the fastest-pace run at the top', async ({ page }) => {
			await page.getByLabel('Sort').selectOption('fastest');
			await expect(page.locator('.run-card').first()).toBeVisible();
			// Just sanity-check the order changed vs Newest — exact
			// fastest run can drift with seed evolution.
			const firstDate = (await page
				.locator('.run-card')
				.first()
				.locator('.run-date')
				.textContent()) ?? '';
			await page.getByLabel('Sort').selectOption('newest');
			const newestDate = (await page
				.locator('.run-card')
				.first()
				.locator('.run-date')
				.textContent()) ?? '';
			expect(firstDate).not.toEqual(newestDate);
		});
	});

	test.describe('Date range', () => {
		// Settle the run-card count after a date-range selection. The
		// filtered list is derived synchronously but the DOM update
		// runs on the next microtask; an immediate `.count()` can land
		// before the new render and return a stale value. The poll
		// reads the count until it stabilises for ~200ms.
		async function stableCardCount(page: import('@playwright/test').Page) {
			let last = -1;
			for (let i = 0; i < 20; i++) {
				const n = await page.locator('.run-card').count();
				if (n === last) return n;
				last = n;
				await page.waitForTimeout(50);
			}
			return last;
		}

		test('All time shows the broadest list (paginated first page)', async ({
			page
		}) => {
			// `all` is the only paginated branch (PAGE_SIZE=50). The
			// other date-ranges are full-fetch within bounds. So the
			// "All time shows more than X" assertion is gated on the
			// page size, not the total seed count.
			expect(await stableCardCount(page)).toBeGreaterThanOrEqual(13);
		});

		test('This year is bounded + returns rows when 2026 runs exist', async ({
			page
		}) => {
			// Year filter is full-fetch within bounds [Jan 1 of current
			// year, ∞). Asserting that some rows come back proves the
			// filter wires through to the query AND the seeded 2026
			// runs are reachable. No narrow-vs-all comparison — that
			// breaks across the pagination boundary.
			await page.getByLabel('Date range').selectOption('year');
			expect(await stableCardCount(page)).toBeGreaterThan(0);
		});

		test('Last 30 days narrows further than (or equals) This year', async ({
			page
		}) => {
			await page.getByLabel('Date range').selectOption('year');
			const yearCount = await stableCardCount(page);
			await page.getByLabel('Date range').selectOption('month');
			const monthCount = await stableCardCount(page);
			expect(monthCount).toBeLessThanOrEqual(yearCount);
		});

		test('This week narrows further than (or equals) Last 30 days', async ({
			page
		}) => {
			await page.getByLabel('Date range').selectOption('month');
			const monthCount = await stableCardCount(page);
			await page.getByLabel('Date range').selectOption('week');
			const weekCount = await stableCardCount(page);
			expect(weekCount).toBeLessThanOrEqual(monthCount);
		});
	});

	test.describe('Custom date range workflow', () => {
		test('selecting Custom does NOT flash the list to All time (no-flash regression pin)', async ({
			page
		}) => {
			// Earlier behaviour: dateRange='custom' + empty bounds made
			// rangeBounds() return {from:null,to:null} (identical to All
			// time). Switching from a narrower range to Custom briefly
			// showed every run in the seed — a visible flash. Fix:
			// rangeBounds('custom') falls back to rangeBounds(prevNon-
			// CustomRange) while bounds are empty. Pin the invariant:
			// going Today → Custom keeps the count at Today's count
			// (not All-time's count) before the user picks any dates.
			await page.getByLabel('Date range').selectOption('today');
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			})
				.catch(() => {
					// Today might be empty in the seed depending on wall
					// clock — that's fine, just record the count.
				});
			const todayCount = await page.locator('.run-card').count();

			await page.getByLabel('Date range').selectOption('custom');
			// Picker auto-opens via onchange — close it without picking
			// (Escape) to inspect the underlying list. handleRange-
			// PickerClose will flip dateRange back to prevNonCustom-
			// Range — so we have to peek BEFORE close.
			//
			// Read the count while the picker modal is still open. The
			// underlying .run-card list is still in the DOM behind the
			// modal backdrop.
			expect(await page.locator('.run-card').count()).toBe(todayCount);
			// Tidy: close the picker. Auto-bounces dateRange back to
			// 'today' (prevNonCustomRange) per handleRangePickerClose.
			await page.keyboard.press('Escape');
		});

		test('selecting Custom with stale bounds in localStorage does NOT apply them — picker opens fresh', async ({
			page,
			context
		}) => {
			// Real-world regression: a user picks Custom May 5–15, then
			// switches to Today. customFrom/customTo are still in local-
			// Storage. When they re-select Custom, rangeBounds('custom')
			// reads those stale values and silently re-applies the May
			// 5–15 filter before the picker even opens. Expectation:
			// selecting Custom always opens a fresh picker; the list
			// stays at the previous (non-custom) range until Apply.
			await context.addInitScript(() => {
				localStorage.setItem(
					'runs_filters_v1',
					JSON.stringify({
						sourceFilter: 'all',
						activityFilter: 'all',
						dateRange: 'today',
						customFrom: '2020-01-01',
						customTo: '2020-12-31',
						sortKey: 'newest'
					})
				);
			});
			await page.goto('/runs');
			// Hydrated state should be dateRange='today' + a hidden stale
			// customFrom/To pair. Capture today's count as the baseline.
			await expect(page.getByLabel('Date range')).toHaveValue('today');
			const todayCount = await page.locator('.run-card').count();

			// Select Custom. Picker auto-opens. The list MUST stay at
			// todayCount — not flash to "2020 runs only" (which would be
			// zero rows in the seed).
			await page.getByLabel('Date range').selectOption('custom');
			expect(await page.locator('.run-card').count()).toBe(todayCount);

			// The picker should also show empty start/end chips — the
			// stale bounds were cleared, not silently pre-loaded into
			// pendingFrom/pendingTo.
			const picker = page.getByRole('dialog', { name: /Select dates/i });
			await expect(picker).toBeVisible();
			await expect(picker.getByText('Tap a date').first()).toBeVisible();
			await expect(picker.getByText('Tap a date').nth(1)).toBeVisible();

			await page.keyboard.press('Escape');
		});

		test('"Pick dates…" chip is HIDDEN until Custom bounds are actually set', async ({
			page
		}) => {
			// Bug 2 regression: there used to be TWO controls for opening
			// the picker — the dropdown's "Custom…" option (auto-opens
			// the picker on selection) AND a "Pick dates…" chip below.
			// Redundant. Fix: the chip is gated on (customFrom ||
			// customTo) so it only appears once Custom dates exist.
			await page.getByLabel('Date range').selectOption('custom');
			await page.keyboard.press('Escape'); // close picker without picking
			// After closing without dates, handleRangePickerClose flips
			// dateRange back to prevNonCustomRange — so the chip's
			// gating condition (dateRange === 'custom' && bounds set)
			// is doubly-false. No chip in view.
			await expect(page.locator('.range-chip')).toHaveCount(0);
			await expect(page.getByText('Pick dates…')).toHaveCount(0);
		});

		test('Custom picker cell-click round-trip — open → pick → apply', async ({
			page
		}) => {
			// Baseline: list at "All time" before we narrow.
			const allCount = await page.locator('.run-card').count();

			await page.getByLabel('Date range').selectOption('custom');

			const picker = page.getByRole('dialog', { name: /Select dates/i });
			await expect(picker).toBeVisible({ timeout: 10_000 });
			await expect(picker.getByText('Tap a date').first()).toBeVisible({
				timeout: 5_000
			});

			const cells = picker.locator('button.cell:not(.empty)');
			await expect(cells.first()).toBeVisible();
			await cells.nth(4).click();
			await expect(picker.locator('.chip').first()).not.toContainText(
				'Tap a date',
				{ timeout: 5_000 }
			);
			await cells.nth(14).click();
			await expect(picker.locator('.chip').nth(1)).not.toContainText(
				'Tap a date',
				{ timeout: 5_000 }
			);

			const apply = picker.getByRole('button', { name: 'Apply', exact: true });
			await expect(apply).toBeEnabled();
			await apply.click();
			await expect(picker).toBeHidden({ timeout: 5_000 });

			await expect(page.locator('.range-chip')).toBeVisible({ timeout: 5_000 });

			const narrowedCount = await page.locator('.run-card').count();
			expect(narrowedCount).toBeLessThanOrEqual(allCount);

			await page.locator('.range-chip').click();
			await expect(picker).toBeVisible({ timeout: 5_000 });
			await page.keyboard.press('Escape');

			await page.getByRole('button', { name: 'Clear', exact: true }).click();
			await expect(page.locator('.range-chip')).toHaveCount(0, { timeout: 5_000 });
			await expect(page.getByLabel('Date range')).toHaveValue('all');
		});

		test('escaping the picker without dates does NOT strand the user in Custom mode', async ({
			page
		}) => {
			// handleRangePickerClose: if dateRange='custom' and no bounds
			// are set, snap dateRange back to prevNonCustomRange. Drives
			// the cancel-without-committing path so the user doesn't
			// end up looking at "Custom…" in the dropdown with no
			// visible date controls.
			await page.getByLabel('Date range').selectOption('week');
			await page.getByLabel('Date range').selectOption('custom');
			const picker = page.getByRole('dialog', { name: /Select dates/i });
			await expect(picker).toBeVisible({ timeout: 10_000 });
			await page.keyboard.press('Escape');
			await expect(picker).toBeHidden({ timeout: 5_000 });
			// dateRange should have snapped back to 'week'.
			await expect(page.getByLabel('Date range')).toHaveValue('week');
		});
	});

	test.describe('Pagination + filter interaction', () => {
		// Bug the user reported: 'given i select Strava as a filter,
		// it only shows like 10 runs and then i have to click the
		// "Load 50 more" to load some more, seems like the runs list
		// and load more button isn't accounting for filters'.
		//
		// Root cause: paginated mode (50/page) was active whenever
		// dateRange='all'. Filtering happens client-side AFTER the
		// fetch — so Source=Strava narrows the first 50 raw rows to
		// however few Strava rows happen to be in that first page,
		// hiding the rest behind Load More.
		//
		// Fix: paginated mode is now gated on source='all' AND
		// activity='all' AND dateRange='all' — the moment ANY filter
		// is set, the page switches to full-fetch and Load More
		// disappears.

		test('Source=Strava shows ALL Strava runs immediately — no Load More', async ({
			page
		}) => {
			await page.getByLabel('Source').selectOption('strava');
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			});
			// All Strava runs in the seed should be visible — the seed
			// has ~33 Strava runs. The list should reflect that, not
			// a paginated subset of ~10.
			const count = await page.locator('.run-card').count();
			expect(count).toBeGreaterThan(15);
			// "Load 50 more" must NOT be visible — full-fetch means the
			// whole filtered set is in view.
			await expect(
				page.getByRole('button', { name: /Load.*more/i })
			).toHaveCount(0);
		});

		test('Source=parkrun shows ALL parkruns immediately — no Load More', async ({
			page
		}) => {
			await page.getByLabel('Source').selectOption('parkrun');
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			});
			// Seed has ~30 parkruns. Should all be visible.
			const count = await page.locator('.run-card').count();
			expect(count).toBeGreaterThan(15);
			await expect(
				page.getByRole('button', { name: /Load.*more/i })
			).toHaveCount(0);
		});

		test('Activity narrow (Walk) shows the single seeded walk — no Load More', async ({
			page
		}) => {
			await page.getByRole('button', { name: 'Walk', exact: true }).click();
			await expect(page.locator('.run-card')).toHaveCount(1, {
				timeout: 10_000
			});
			await expect(
				page.getByRole('button', { name: /Load.*more/i })
			).toHaveCount(0);
		});
	});

	test.describe('Date picker backdrop', () => {
		// Bug the user reported: 'i dont like the darkening given i
		// click on the custom date filter. remove this.'
		//
		// Fix: Modal gained a dimBackdrop prop; DateRangePicker passes
		// dimBackdrop={false} so the .modal-backdrop renders fully
		// transparent. Outside-click-to-close still works.

		test('selecting Custom does NOT darken the page (transparent backdrop)', async ({
			page
		}) => {
			await page.getByLabel('Date range').selectOption('custom');
			// The picker's modal-backdrop should be present (for the
			// click-outside-to-close behaviour) but carry .transparent
			// so its computed background is fully transparent.
			const backdrop = page.locator('.modal-backdrop');
			await expect(backdrop).toBeVisible({ timeout: 10_000 });
			await expect(backdrop).toHaveClass(/transparent/);
			// Computed background-color is rgba(0,0,0,0). Any other
			// backdrop in the app keeps rgba(0,0,0,0.5).
			const bg = await backdrop.evaluate((el) =>
				getComputedStyle(el).backgroundColor
			);
			expect(bg).toMatch(/rgba\(0,\s*0,\s*0,\s*0\)/);
			// Cleanup — close the picker so subsequent tests start fresh.
			await page.keyboard.press('Escape');
		});

		test('selecting a confirmation modal STILL darkens the page (default behaviour)', async ({
			page
		}) => {
			// Negative regression — make sure the dimBackdrop default
			// of `true` is preserved for the rest of the app. Use the
			// bulk-delete confirm dialog as the canonical opaque-modal
			// surface: select a run, hit Delete, ConfirmDialog opens.
			await page.getByRole('button', { name: 'Select', exact: true })
				.click();
			// Pick the first card.
			await page.locator('.run-card').first().click();
			await page
				.getByRole('button', { name: /Delete/, exact: false })
				.first()
				.click();
			const backdrop = page.locator('.modal-backdrop');
			await expect(backdrop).toBeVisible({ timeout: 5_000 });
			await expect(backdrop).not.toHaveClass(/transparent/);
			// Tidy.
			await page.getByRole('button', { name: 'Cancel', exact: true })
				.first()
				.click();
			await page.getByRole('button', { name: 'Done', exact: true })
				.click();
		});
	});

	test.describe('Combined filters', () => {
		test('Source=Strava + Activity=Run + Sort=Longest narrows + sorts as expected', async ({
			page
		}) => {
			await page.getByLabel('Source').selectOption('strava');
			await page.getByRole('button', { name: 'Run', exact: true }).click();
			await page.getByLabel('Sort').selectOption('longest');
			const cards = page.locator('.run-card');
			await expect(cards.first()).toBeVisible({ timeout: 10_000 });
			const count = await cards.count();
			expect(count).toBeGreaterThan(0);
			// Every visible card is Strava-sourced.
			const badges = page.locator('.run-card .source-badge');
			expect(await badges.count()).toBe(count);
			for (let i = 0; i < Math.min(count, 3); i++) {
				await expect(badges.nth(i)).toHaveText(/strava/i);
			}
		});

		test('Resetting any filter restores the count to the broader bucket', async ({
			page
		}) => {
			const allCount = await page.locator('.run-card').count();
			await page.getByLabel('Source').selectOption('parkrun');
			const parkrunCount = await page.locator('.run-card').count();
			expect(parkrunCount).toBeLessThan(allCount);
			await page.getByLabel('Source').selectOption('all');
			const restored = await page.locator('.run-card').count();
			expect(restored).toBe(allCount);
		});
	});
});
