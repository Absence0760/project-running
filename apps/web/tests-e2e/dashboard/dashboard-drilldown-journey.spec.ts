import { expect, test, type Page } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Dashboard overview → period-summary drilldown journey.
 *
 * This walks the arc a runner takes from the /dashboard overview into a
 * PeriodSummary drilldown and asserts the COMPUTED stats — not just that
 * the modal mounts. It's the genuinely-uncovered slice the existing specs
 * leave open:
 *
 *   - cross-cutting/dashboard-journey.spec.ts exercises goal reactivity
 *     (Total Runs, goal pct), never PeriodSummary.
 *   - dashboard/page.spec.ts clicks the "This Week" + "Longest Run" stat
 *     tiles and asserts the modal OPENS (toggle visible) — but never the
 *     distance / time / runs / pace the summary computes.
 *   - dashboard/period.spec.ts deep-links /dashboard/period/[type]/[date]
 *     and asserts the toggle MOUNTS against the seed — never the numbers,
 *     and never that the modal and the deep-link agree for one window.
 *
 * So this journey plants a KNOWN spread of runs for a clean ephemeral
 * saga user (no seed noise to perturb the totals), then verifies end to
 * end:
 *
 *   1. Overview: stat grid (This Week distance + activity count), the
 *      ThisWeekStrip ribbon total, and Recent Runs all reflect the plant.
 *   2. Drill into "This Week" stat card → PeriodSummary modal → its four
 *      computed stat cards (Distance / Time / Runs / Avg pace) match the
 *      week's plant, and its run list lists exactly the week's runs.
 *   3. Toggle the modal Week → All time → re-windows to the FULL set
 *      (week runs + an older out-of-week run), proving the toggle drives
 *      the derivation, not just the label.
 *   4. Drill into the "Longest Run" / "All time" stat card → all-time
 *      summary → longest matches the biggest planted run.
 *   5. The standalone /dashboard/period/week/<isoMonday> deep link
 *      computes the SAME week stats as the modal did (the modal + the
 *      page share the PeriodSummary component + fetchRuns, so the two
 *      drilldown entry points must agree).
 *
 * Anchoring (browser is UTC-pinned in the Playwright config): PeriodSummary
 * windows a week as Monday 00:00 → Sunday 23:59 (periodStart: `(getDay()+6)%7`
 * back-off, all in LOCAL = UTC time here). We compute this week's Monday in
 * UTC and stamp the three in-week runs at noon UTC on Mon / Wed / Fri so
 * they land squarely inside the window on any weekday the suite runs, and
 * the out-of-week run ~40 days back so it's all-time-only.
 */

const METRES_PER_KM = 1000;

// Monday 00:00:00 UTC of the calendar week containing `now`. Mirrors
// PeriodSummary.periodStart for a 'week' (Monday-start: (getDay()+6)%7
// days back) — the browser runs UTC so getUTC* == getLocal* here, but we
// use getUTC* explicitly so the plant is unambiguous.
function mondayUtc(now: Date): Date {
	const d = new Date(now);
	const dow = (d.getUTCDay() + 6) % 7;
	d.setUTCHours(0, 0, 0, 0);
	d.setUTCDate(d.getUTCDate() - dow);
	return d;
}

// `YYYY-MM-DD` in UTC — the segment the deep-link route + formatISO use.
function isoDay(d: Date): string {
	const p = (n: number) => String(n).padStart(2, '0');
	return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`;
}

// Noon UTC `offsetDays` after the given midnight — noon keeps the run clear
// of any day boundary so the local-day bucketing can't drift it a day.
function noonAfter(base: Date, offsetDays: number): string {
	const d = new Date(base);
	d.setUTCDate(d.getUTCDate() + offsetDays);
	d.setUTCHours(12, 0, 0, 0);
	return d.toISOString();
}

// PeriodSummary renders distance/time/runs as formatDistance / formatDuration.
// formatDistance (units.svelte.ts) for a metric >= 1 km is `D.DD km` (2 dp).
function kmLabel(metres: number): string {
	return `${(metres / METRES_PER_KM).toFixed(2)} km`;
}

// ThisWeekStrip's total uses fmtKm (units.svelte.ts), which defaults to ONE
// decimal — distinct from PeriodSummary's 2-dp formatDistance above. Use this
// for the week-strip-total assertion only.
function stripKmLabel(metres: number): string {
	return `${(metres / METRES_PER_KM).toFixed(1)} km`;
}

// Pre-accept the cookie banner before any context paint — the consent
// dialog is role="dialog" and floats over modals, which has eaten clicks
// on the stat tiles in prior rounds. Saga users have never accepted it.
function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

// The PeriodSummary modal's four stat cards in DOM order: Distance, Time,
// Runs, Avg pace (PeriodSummary.svelte `.stats > .stat-card` order).
async function modalStatValue(page: Page, label: string): Promise<string> {
	const card = page
		.locator('.modal .stats .stat-card')
		.filter({ has: page.locator('.stat-label', { hasText: new RegExp(`^${label}$`) }) });
	await expect(card).toBeVisible({ timeout: 10_000 });
	return ((await card.locator('.stat-value').textContent()) ?? '').trim();
}

test.describe('dashboard drilldown journey', () => {
	let user: SagaUser;

	// Three in-week runs + one older (all-time only) run. Distances chosen
	// so each total is unambiguous and the longest run is plainly the 14 km.
	const WEEK_RUNS = [
		{ distance_m: 5_000, duration_s: 1_500 }, // Mon  5.00 km / 25:00
		{ distance_m: 8_000, duration_s: 2_640 }, // Wed  8.00 km / 44:00
		{ distance_m: 12_000, duration_s: 3_960 }, // Fri 12.00 km / 66:00
	];
	const OLDER_RUN = { distance_m: 14_000, duration_s: 5_040 }; // ~40 d ago, longest

	const weekDistance = WEEK_RUNS.reduce((s, r) => s + r.distance_m, 0); // 25_000
	const weekCount = WEEK_RUNS.length; // 3
	const allCount = WEEK_RUNS.length + 1; // 4
	const longestAllMetres = OLDER_RUN.distance_m; // 14_000

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Drilldown Runner'] });

		const monday = mondayUtc(new Date());
		// Mon / Wed / Fri noon this week — squarely inside the Mon→Sun window.
		const stamps = [0, 2, 4];
		for (let i = 0; i < WEEK_RUNS.length; i++) {
			await insertRun({
				user_id: user.id,
				started_at: noonAfter(monday, stamps[i]),
				distance_m: WEEK_RUNS[i].distance_m,
				duration_s: WEEK_RUNS[i].duration_s,
			});
		}
		// Older run, ~40 days back — out of this calendar week, present only
		// in the all-time view; it's also the single longest run.
		await insertRun({
			user_id: user.id,
			started_at: new Date(Date.now() - 40 * 86_400_000).toISOString(),
			distance_m: OLDER_RUN.distance_m,
			duration_s: OLDER_RUN.duration_s,
		});
	});

	test.afterAll(async () => {
		// CASCADE on auth.users delete sweeps every planted run; the saga
		// helper also unlinks the storage-state file.
		if (user) await deleteSagaUsers([user]);
	});

	test('overview stat grid + week strip → "This Week" drilldown stats → all-time toggle → "Longest Run" drilldown → deep-link agreement', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			// ── Phase 1: overview reflects the plant ───────────────────
			await test.step('dashboard overview: This Week stat + week-strip total + Recent Runs', async () => {
				await page.goto('/dashboard');

				// "This Week" stat card value = sum of this week's run distances.
				const thisWeekCard = page
					.locator('.stat-grid .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: 'This Week' }) })
					.first();
				await expect(thisWeekCard.locator('.stat-value')).toHaveText(
					kmLabel(weekDistance),
					{ timeout: 15_000 }
				);
				// Sub-line: "3 activities" (activityCountOther). Pin the count.
				await expect(thisWeekCard.locator('.stat-sub')).toContainText(
					`${weekCount} activities`
				);

				// Total Runs counts ALL runs (no current-week window) → 4.
				const totalCard = page
					.locator('.stat-grid .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: 'Total Runs' }) })
					.first();
				await expect(totalCard.locator('.stat-value')).toHaveText(String(allCount));

				// Longest Run stat (all-time) = the older 14 km run.
				const longestCard = page
					.locator('.stat-grid .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: 'Longest Run' }) })
					.first();
				await expect(longestCard.locator('.stat-value')).toHaveText(
					kmLabel(longestAllMetres)
				);

				// ThisWeekStrip ribbon total (current_week.ts) must match the
				// "This Week" stat — same week, same source-filtered runs.
				const stripTotal = page.locator('.week-strip .week-strip-total');
				await expect(stripTotal).toContainText(stripKmLabel(weekDistance));
				await expect(stripTotal).toContainText(`${weekCount} activities`);

				// Recent Runs lists every planted run (4 ≤ the 7-row cap).
				const recentDistances = page.locator('.run-row .run-distance');
				await expect(recentDistances).toHaveCount(allCount);
			});

			// ── Phase 2: drill into the This-Week stat card ────────────
			await test.step('"This Week" tile opens PeriodSummary with this week\'s computed stats + run list', async () => {
				await page
					.getByRole('button', { name: /This Week/ })
					.first()
					.click();

				// Modal mounts in 'week' mode (Week toggle active).
				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 10_000 });
				await expect(
					modal.locator('.type-toggle .toggle-btn.active')
				).toHaveText('Week');

				// The four computed stat cards reflect THIS WEEK's three runs.
				expect(await modalStatValue(page, 'Distance')).toBe(kmLabel(weekDistance));
				// formatDuration(8100) = 2:15:00 (H:MM:SS).
				expect(await modalStatValue(page, 'Time')).toBe('2:15:00');
				expect(await modalStatValue(page, 'Runs')).toBe(String(weekCount));
				// Avg pace is rendered with a /km suffix; just assert it's a
				// real m:ss value, not the empty-state em dash.
				expect(await modalStatValue(page, 'Avg pace')).toMatch(/^\d{1,2}:\d{2} \/km$/);

				// The run list inside the modal lists exactly this week's runs.
				await expect(modal.locator('.run-list .run-row')).toHaveCount(weekCount);
			});

			// ── Phase 3: toggle Week → All time re-windows the set ─────
			await test.step('modal Week → All time toggle re-windows to the full run set', async () => {
				const modal = page.locator('.modal');
				await modal.getByRole('button', { name: 'All time' }).click();
				// The toggle label uses the lowercase `dash.allTime` copy ("all
				// time") — getByRole name-matching above is case-insensitive, but
				// the active-button text assertion is exact.
				await expect(
					modal.locator('.type-toggle .toggle-btn.active')
				).toHaveText('all time');

				// All-time distance = week runs + the older run.
				const allDistance = weekDistance + OLDER_RUN.distance_m; // 39_000
				expect(await modalStatValue(page, 'Distance')).toBe(kmLabel(allDistance));
				expect(await modalStatValue(page, 'Runs')).toBe(String(allCount));
				// And the list now carries all four runs — the toggle drove the
				// derivation, not just the heading.
				await expect(modal.locator('.run-list .run-row')).toHaveCount(allCount);

				// Close the modal (Escape) before the next drilldown so the two
				// modals don't stack.
				await page.keyboard.press('Escape');
				await expect(modal).toHaveCount(0, { timeout: 5_000 });
			});

			// ── Phase 4: drill into the Longest-Run / All-time card ────
			await test.step('"Longest Run" tile opens the all-time summary; longest matches the biggest run', async () => {
				await page
					.getByRole('button', { name: /Longest Run/ })
					.first()
					.click();

				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 10_000 });
				// Opens directly in all-time mode (periodModal type 'all'); the
				// active toggle's exact text is the lowercase `dash.allTime` copy.
				await expect(
					modal.locator('.type-toggle .toggle-btn.active')
				).toHaveText('all time');

				expect(await modalStatValue(page, 'Runs')).toBe(String(allCount));
				// All-time distance again = 39 km; the longest single run (14 km)
				// shows up in the run list as a row.
				expect(await modalStatValue(page, 'Distance')).toBe(
					kmLabel(weekDistance + OLDER_RUN.distance_m)
				);
				await expect(
					modal.locator('.run-list .run-row .run-dist', {
						hasText: kmLabel(longestAllMetres),
					})
				).toBeVisible();

				await page.keyboard.press('Escape');
				await expect(modal).toHaveCount(0, { timeout: 5_000 });
			});

			// ── Phase 5: deep-link agrees with the modal for the week ──
			await test.step('standalone /dashboard/period/week/<monday> computes the same week stats', async () => {
				const monday = isoDay(mondayUtc(new Date()));
				await page.goto(`/dashboard/period/week/${monday}`);

				// Page mounts PeriodSummary in 'week' mode. The kicker confirms
				// the route resolved type=week.
				await expect(page.locator('.kicker')).toHaveText('Weekly summary', {
					timeout: 10_000,
				});
				await expect(page.locator('.type-toggle .toggle-btn.active')).toHaveText(
					'Week'
				);

				// Same week → same computed numbers as the modal in Phase 2.
				// (The page renders PeriodSummary outside a `.modal`, so target
				// the page-level .stats here.)
				const distCard = page
					.locator('.stats .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: /^Distance$/ }) });
				await expect(distCard.locator('.stat-value')).toHaveText(
					kmLabel(weekDistance)
				);
				const runsCard = page
					.locator('.stats .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: /^Runs$/ }) });
				await expect(runsCard.locator('.stat-value')).toHaveText(String(weekCount));
				// The week's three runs are listed (and only them).
				await expect(page.locator('.run-list .run-row')).toHaveCount(weekCount);
			});
		} finally {
			await ctx.close();
		}
	});
});
