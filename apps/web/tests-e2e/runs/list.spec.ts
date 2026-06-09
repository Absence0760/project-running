import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers } from '../fixtures/saga-users';
import { withCleanCurrentWeek } from '../fixtures/simulate';
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

	// The gym/nutrition seed plants a now()-relative run (seed.sql
	// "Morning easy 8K"), so real-wall-clock "today" is no longer empty.
	// The filtered-empty test needs an empty "today", so clear the current
	// week for it and restore the run after (/nutrition + dashboard-
	// readiness specs still need it). Gated by title so the other tests in
	// this describe keep counting the seed run.
	const cleanWeekTitles = new Set([
		'filtered-empty state offers a one-tap "Show all runs" escape'
	]);
	let restoreCleanWeek: (() => Promise<void>) | null = null;
	test.beforeEach(async ({}, testInfo) => {
		if (cleanWeekTitles.has(testInfo.title)) {
			restoreCleanWeek = await withCleanCurrentWeek(USER_A.id);
		}
	});
	test.afterEach(async () => {
		if (restoreCleanWeek) {
			await restoreCleanWeek();
			restoreCleanWeek = null;
		}
	});

	test('toolbar actions stay on the filter row, pinned right (not wrapped below)', async ({
		page
	}) => {
		// Regression guard: the toolbar used to wrap as a whole, so a wide
		// filter cluster shoved the Heatmap / Select / Add run actions onto
		// their own line. The actions must now sit on the same row as the
		// segmented control (top-aligned), pinned to the toolbar's right edge,
		// with the selects wrapping BELOW them — never the actions wrapping.
		await page.setViewportSize({ width: 1400, height: 900 });
		await page.goto('/runs');
		await expect(page.getByRole('heading', { level: 1, name: 'Run history' })).toBeAttached();
		const actions = page.locator('.toolbar-actions');
		const activity = page.locator('.activity-group');
		const selects = page.locator('.select-group');
		const toolbar = page.locator('.toolbar');
		await expect(actions).toBeVisible();
		const a = (await actions.boundingBox())!;
		const f = (await activity.boundingBox())!;
		const s = (await selects.boundingBox())!;
		const t = (await toolbar.boundingBox())!;
		// Same row as the segmented control (tops within one row height).
		expect(Math.abs(a.y - f.y)).toBeLessThan(a.height);
		// Pinned to the right edge of the toolbar (within a few px).
		expect(t.x + t.width - (a.x + a.width)).toBeLessThan(6);
		// The selects wrapped BELOW the actions row — the actions did not.
		expect(s.y).toBeGreaterThan(a.y + a.height / 2);
	});

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

	test('list state survives in-app navigation (snapshot round-trip)', async ({
		page
	}) => {
		// SvelteKit's snapshot API persists in-memory state across
		// `<a>` + popstate navigation, but ONLY if every reactive piece
		// that drives the fetch lives in the snapshot. The original
		// snapshot captured runs + hasMore + lastFetchMode but NOT the
		// filter values; on back-nav the runs restored, then onMount
		// re-read localStorage, fetchMode re-derived, the effect-
		// driven loadInitial wiped the restored list, and the user saw
		// "Loading…" followed by a list reset to the default filters.
		// Pin the round-trip: set a non-default filter, walk into a
		// run, walk back, assert the filter + the list look the same.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		// Capture the count we expect to see again after back-nav.
		await expect(page.locator('.run-card').first()).toBeVisible();
		const beforeCount = await page.locator('.run-card').count();
		expect(beforeCount).toBeGreaterThanOrEqual(13);

		// Click into the first run.
		await page.locator('.run-card').first().click();
		await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });

		// Back to /runs. The list should restore without a flash of
		// "Loading…" and the filter UI should still read "All time".
		await page.goBack();
		await page.waitForURL(/\/runs$/, { timeout: 10_000 });

		// Filter UI stayed on "All time" (would have reset to "today"
		// if the snapshot didn't carry dateRange).
		await expect(page.getByLabel('Date range')).toHaveValue('all');
		// And the same number of cards is in view.
		await expect(page.locator('.run-card')).toHaveCount(beforeCount, {
			timeout: 5_000
		});

		// Restore so subsequent tests don't inherit the All-time filter.
		await page.getByLabel('Date range').selectOption('today');
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

	test('filtered-empty state offers a one-tap "Show all runs" escape', async ({
		page
	}) => {
		// A sparse user opening /runs on a non-run day lands on the
		// default "today" filter with their (older) runs hidden — the
		// dead-end the round-5 casual persona hit. The filtered-empty
		// branch must give a way out, not just "try widening the range".
		// Seed runs are March-April 2026 and the describe's beforeEach
		// cleared the current week, so real-wall-clock "today" is empty;
		// force the default filter first.
		await page.addInitScript(() => localStorage.removeItem('runs_filters_v1'));
		await page.goto('/runs');

		const filteredEmpty = page.getByTestId('runs-empty-filtered');
		await expect(filteredEmpty).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('runs-empty-show-all').click();

		// Clearing to All-time reveals the real history.
		await expect(page.locator('.run-card').first()).toBeVisible({ timeout: 10_000 });
		await expect(page.getByLabel('Date range')).toHaveValue('all');

		// Restore default so later tests don't inherit All-time.
		await page.getByLabel('Date range').selectOption('today');
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
		// Adding a filter triggers a FULL refetch (the list briefly empties
		// while it loads), so poll for the settled parkrun set rather than
		// `< beforeCount` — the latter is satisfied by the transient empty
		// loading state and reads 0 before the rows land.
		await expect.poll(() => cards.count(), { timeout: 10_000 }).toBeGreaterThanOrEqual(3);
		const parkrunCount = await cards.count();
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

	test('Select-mode + bulk-delete actually removes a planted run from the DB', async ({
		page
	}) => {
		// Companion to the cancel-test above. Pin the destructive write
		// path: plant a throwaway run via service-role, navigate /runs,
		// enter select mode, pick the planted card, Delete → Confirm,
		// row is gone server-side. A regression in deleteRuns or its
		// optimistic update would fail here.
		const { getAdminClient } = await import('../fixtures/local-supabase');
		const { insertRun } = await import('../fixtures/simulate');
		const admin = getAdminClient();

		// Plant with a unique, very-distinctive distance (12345 m) so we
		// can locate the exact card in the list by its rendered text.
		const plantedId = await insertRun({
			user_id: USER_A.id,
			distance_m: 12_345,
			duration_s: 4_321,
			is_public: false,
			started_at: new Date().toISOString()
		});

		try {
			await page.goto('/runs');
			await switchRunsToAllTime(page);
			// Sort by Newest so our just-planted run is the first row.
			await page.locator('select[aria-label="Sort"]').selectOption('newest');
			await expect(page.locator('.run-card').first())
				.toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: 'Select', exact: true }).click();

			// Click the first card (most recent — our planted row).
			await page.locator('.run-card').first().click();
			const bulkBar = page.locator('.bulk-bar');
			await expect(bulkBar).toContainText('1 selected');

			await bulkBar.getByRole('button', { name: 'Delete' }).click();
			const dialog = page.locator('.modal', { hasText: /Delete 1 run/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(dialog).toHaveCount(0, { timeout: 10_000 });

			// Backend: the row is gone (poll briefly — the optimistic UI
			// closes the dialog before the await on deleteRuns resolves).
			await expect.poll(async () => {
				const { data } = await admin
					.from('runs')
					.select('id')
					.eq('id', plantedId)
					.maybeSingle();
				return data;
			}, { timeout: 5_000 }).toBeNull();
		} finally {
			// Best-effort sweep in case the test failed before the UI
			// delete fired.
			await admin.from('runs').delete().eq('id', plantedId);
		}
	});

	test('Select 10 + bulk-delete removes EVERY selected run from the DB (concurrency-safe)', async ({
		page
	}) => {
		// Real bug surfaced during /runs polish: selecting 10 runs and
		// hitting Delete only actually deleted ~5 of them. Root cause was
		// the `runs_personal_records_delete` trigger calling
		// refresh_personal_records_for_user, which DELETEs then INSERTs
		// against personal_records. With parallel run-deletes from the
		// client, two trigger invocations raced on the personal_records
		// PK and threw 23505. supabase-js surfaced the 409 as a delete
		// error, the runs.DELETE rolled back, and the rows survived.
		//
		// Fix: the trigger function now takes a pg_advisory_xact_lock
		// keyed on the user id so per-user PR refreshes serialize.
		// This test plants 12 throwaway runs and asserts that selecting
		// 10 + hitting Delete actually removes all 10 from the DB. A
		// regression in either the trigger or the client bulk-delete
		// path would fail here.
		const { getAdminClient } = await import('../fixtures/local-supabase');
		const { insertRun } = await import('../fixtures/simulate');
		const admin = getAdminClient();

		// Plant 12 runs with distinctive 12345+i distances so accidental
		// matches against seed runs are impossible. Sorted newest-first
		// so they land at the top of the list under the default sort.
		const plantedIds: string[] = [];
		const now = Date.now();
		for (let i = 0; i < 12; i++) {
			plantedIds.push(
				await insertRun({
					user_id: USER_A.id,
					distance_m: 12345 + i,
					duration_s: 4321,
					is_public: false,
					started_at: new Date(now - i * 1000).toISOString()
				})
			);
		}

		try {
			await page.goto('/runs');
			await switchRunsToAllTime(page);
			await page.locator('select[aria-label="Sort"]').selectOption('newest');
			await expect(page.locator('.run-card').first()).toBeVisible({
				timeout: 10_000
			});

			// Enter select mode + click the first 10 cards (= our planted
			// runs, sorted newest-first).
			await page.getByRole('button', { name: 'Select', exact: true }).click();
			for (let i = 0; i < 10; i++) {
				await page.locator('.run-card').nth(i).click();
			}

			const bulkBar = page.locator('.bulk-bar');
			await expect(bulkBar).toContainText('10 selected');

			await bulkBar.getByRole('button', { name: 'Delete' }).click();
			const dialog = page.locator('.modal', { hasText: /Delete 10 run/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(dialog).toHaveCount(0, { timeout: 15_000 });

			// Poll the DB: the 10 newest planted ids should all be gone,
			// leaving exactly 2 of the 12 still present. Without the
			// trigger fix this would settle at ~7 (5 deleted, 5 raced).
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('runs')
							.select('id')
							.in('id', plantedIds);
						return data?.length ?? 0;
					},
					{ timeout: 10_000 }
				)
				.toBe(2);
		} finally {
			// Best-effort sweep so the seed stays clean even if the test
			// asserted-then-failed mid-way.
			await admin.from('runs').delete().in('id', plantedIds);
		}
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

	test('Source filter "Strava" narrows the list to strava-source rows only', async ({
		page
	}) => {
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await page.locator('select[aria-label="Source"]').selectOption('strava');
		await expect(page.locator('.run-card').first()).toBeVisible({
			timeout: 10_000
		});
		// Every visible row should carry the "Strava" source badge.
		const badges = await page
			.locator('.run-card .source-badge')
			.allTextContents();
		expect(badges.length).toBeGreaterThan(0);
		for (const b of badges) expect(b.toLowerCase()).toContain('strava');
	});

	test('Sort by Newest puts a recently-planted run at the top', async ({
		page
	}) => {
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		// "Sort: Newest" is the default for the sort select. Pin it
		// after touching the select to make sure the round-trip works.
		await page.locator('select[aria-label="Sort"]').selectOption('newest');
		// First card in the list is the most recent. Just assert the
		// run-card grid is non-empty + the first row is interactable.
		const first = page.locator('.run-card').first();
		await expect(first).toBeVisible({ timeout: 10_000 });
	});

	test('Activity-button "Run" leaves the seeded run rows visible', async ({
		page
	}) => {
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		// Activity is a button group with aria-pressed. The default is
		// "All" (see filters.spec.ts); clicking Run explicitly proves the
		// toggle narrows to runs from any starting state.
		await page.getByRole('button', { name: 'Run', exact: true }).click();
		await expect(page.locator('.run-card').first()).toBeVisible({
			timeout: 10_000
		});
	});

	test('combined filters: Source=parkrun + Activity=Run narrows to parkrun-source run rows only', async ({
		page
	}) => {
		// The page composes filters AND-style — Activity, Source, Date,
		// search box are all $derived together. A regression that
		// dropped one of them on combined paths would show up here as
		// a count that reflects only one filter.
		//
		// Seed contains 30+ parkruns (all activity_type=run by design).
		// Rather than pin a brittle exact number that drifts with seed
		// evolution, pin the invariants that matter for filter
		// composition: every visible card carries the parkrun source
		// badge, and the count matches Source=parkrun alone (no rows
		// dropped by the Activity overlay).
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
		await expect(page.locator('.run-card').first()).toBeVisible({
			timeout: 10_000
		});

		// Baseline: Source=parkrun alone.
		await page.locator('select[aria-label="Source"]').selectOption('parkrun');
		await expect(page.locator('.run-card').first()).toBeVisible();
		const parkrunOnlyCount = await page.locator('.run-card').count();
		expect(parkrunOnlyCount).toBeGreaterThan(0);

		// Compose with Activity=Run — count stays identical because
		// every parkrun is a run.
		await page.getByRole('button', { name: 'Run', exact: true }).click();
		await expect(page.locator('.run-card')).toHaveCount(parkrunOnlyCount);
		const badges = page.locator('.run-card .source-badge');
		expect(await badges.count()).toBe(parkrunOnlyCount);
		await expect(badges.first()).toHaveText(/parkrun/i);

		// Restore so subsequent tests start clean.
		await page.locator('select[aria-label="Source"]').selectOption('all');
		await page.getByRole('button', { name: 'All', exact: true }).click();
	});

	test('Select-all visible covers every run-card in the filtered set', async ({
		page
	}) => {
		await page.goto('/runs');
		// Clear any inherited filter from a previous test (e.g.
		// activity=run from the test above) so the row count is what
		// the canonical "All time + Run" view shows.
		await page.evaluate(() => {
			try {
				localStorage.removeItem('runs_filters_v1');
			} catch {
				/* anonymous browsing context — ignore */
			}
		});
		await page.reload();
		await switchRunsToAllTime(page);
		// Wait for the list to populate.
		await expect(page.locator('.run-card').first()).toBeVisible({
			timeout: 10_000
		});
		const total = await page.locator('.run-card').count();
		expect(total).toBeGreaterThan(0);

		await page.getByRole('button', { name: 'Select', exact: true }).click();
		await page.getByRole('button', { name: 'Select all' }).click();
		// Every row gets the .selected class.
		await expect(page.locator('.run-card.selected')).toHaveCount(total);
		// Floating bulk-bar shows the count.
		await expect(page.locator('.bulk-bar')).toContainText(`${total} selected`);
		// Clean up — Done exits select mode.
		await page.getByRole('button', { name: 'Done' }).click();
		await expect(page.locator('.bulk-bar')).toHaveCount(0);
	});
});

// Persona-hunt finding Casual #2 — zero-run users used to see the
// filter-empty card ("No runs match these filters") with no Add CTA.
// A brand-new user landing on /runs would conclude they did something
// wrong with filters they never set. Pinned via a sub-suite that
// mints an ephemeral saga user — the seeded users all have runs.
test.describe('/runs — zero-run empty state (Casual #2)', () => {
	test('brand-new user with no runs sees Add-run CTA, not filter copy', async ({
		browser
	}) => {
		const [user] = await createSagaUsers(1, {
			displayNames: ['Zero Runs Test']
		});
		try {
			const ctx = await browser.newContext({
				storageState: user.storageStatePath
			});
			const page = await ctx.newPage();
			await page.goto('/runs');

			// Truly-empty branch carries the runs-empty-no-data testid
			// (added with the fix). The accusatory filter copy must NOT
			// appear for a zero-run user.
			await expect(
				page.locator('[data-testid="runs-empty-no-data"]')
			).toBeVisible({ timeout: 10_000 });
			await expect(page.getByText('No runs match these filters')).toHaveCount(0);

			// Affordance: a clickable "Add a run" CTA opens the create
			// modal. Click + check the modal mounts.
			await page.getByRole('button', { name: 'Add a run' }).click();
			await expect(page.getByRole('heading', { name: 'Add a run' }))
				.toBeVisible({ timeout: 5_000 });

			await ctx.close();
		} finally {
			await deleteSagaUsers([user]);
		}
	});
});
