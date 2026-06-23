import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { liveMonthLabel, seedDateToLive } from '../fixtures/plan-today';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — PlanCalendar.svelte (the month-view calendar mounted
 * under the "Calendar" section between the today-card and the week
 * grid).
 *
 * The component (apps/web/src/lib/components/PlanCalendar.svelte)
 * owns:
 *   - Month nav (prev / next, disabled at plan boundaries)
 *   - Monday-first day-of-week header
 *   - 7-column grid with leading/trailing padding cells from the
 *     adjacent months (rendered with .out-month opacity)
 *   - Cells outside the plan window (.out-plan) drawn as ghosts
 *   - Today marker (.today, primary border + shadow)
 *   - Per-workout cell: kind-colour border-left, kind pill, distance,
 *     completed checkmark, .done background tint
 *   - onSelect handler dispatch when the host wants the click to open
 *     an editor instead of navigating to /plans/[id]/workouts/[wid]
 *
 * The seed provisions a 12-week plan ("Richmond Half 2026", id
 * `a1a1eada-aaaa-…`) with workouts in weeks 0-4 + the race week 11.
 * Weeks 5-10 have no workouts on purpose (placeholder gap) — useful
 * because it lets us exercise the in-plan-but-no-workout cell shape
 * AND the prev/next disabling at the first and last month.
 *
 * Drift in any of these would silently break the calendar, since
 * regressions usually keep rendering "some" cells.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

// The seed slides the plan onto a now()-relative window, so the live
// start/end (and therefore the calendar's first/last month labels) move on
// every reset. Resolve them from the seed-coordinate dates the plan is
// authored against — '2026-03-29' (start) and '2026-06-20' (race) — instead
// of hard-coding the 2026 calendar months. The first plan month carries the
// week-0 completed long run; the seed week-1/2 workouts (the tempo, the
// interval, the MP run) live in the SECOND plan month.
let PLAN_START = '2026-03-29';
let PLAN_END = '2026-06-20';
// `MMMM YYYY` labels matching `.cal-head h3`, computed live in beforeAll.
let FIRST_MONTH_LABEL: string;
let SECOND_MONTH_LABEL: string;
let GAP_MONTH_LABEL: string;
let LAST_MONTH_LABEL: string;

test.beforeAll(async () => {
	PLAN_START = await seedDateToLive('2026-03-29');
	PLAN_END = await seedDateToLive('2026-06-20');
	FIRST_MONTH_LABEL = await liveMonthLabel('2026-03-29');
	// The tempo/interval/MP workouts are in the seed's April (week 1/2).
	SECOND_MONTH_LABEL = await liveMonthLabel('2026-04-07');
	// Seed weeks 5-10 (the placeholder gap) have no workouts; mid-gap day.
	GAP_MONTH_LABEL = await liveMonthLabel('2026-05-20');
	LAST_MONTH_LABEL = await liveMonthLabel('2026-06-20');
});

/**
 * Walk the calendar to the month whose `.cal-head h3` reads exactly
 * `label`, direction-agnostic: rewind to the first plan month (Prev until
 * disabled), then step Next until the head matches. The plan window's months
 * move with the seed's now()-relative shift, so callers pass a live label
 * (FIRST/SECOND/LAST_MONTH_LABEL) rather than a hard-coded 2026 month.
 */
async function walkToMonth(page: import('@playwright/test').Page, label: string) {
	const head = page.locator('.cal-head h3');
	const prev = page.locator('.cal .nav[aria-label="Previous month"]');
	const next = page.locator('.cal .nav[aria-label="Next month"]');
	for (let i = 0; i < 24; i++) {
		if ((await prev.getAttribute('disabled')) !== null) break;
		await prev.click();
	}
	for (let i = 0; i < 24; i++) {
		if (((await head.textContent()) ?? '').trim() === label) return;
		if ((await next.getAttribute('disabled')) !== null) break;
		await next.click();
	}
	await expect(head).toHaveText(label);
}

test.describe('/plans/[id] — PlanCalendar (month view)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		// Pre-accept cookie consent so the CookieConsentBanner doesn't
		// intercept pointer events on the modal buttons we click below.
		// The banner mounts on every cold page load when localStorage
		// has no `cookie_consent` entry — Playwright contexts start
		// without one even though the auth storage state is loaded.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('Calendar section mounts under the plan-detail hero', async ({ page }) => {
		// `<section class="calendar-section">` + `<h2 class="section-title">Calendar</h2>`
		// + `.cal` from PlanCalendar. A regression that dropped the
		// component from the page (e.g. inadvertent {#if} guard) would
		// surface here. The .cal class is unique to PlanCalendar.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('section.calendar-section')).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('section.calendar-section h2.section-title'))
			.toHaveText('Calendar');
		await expect(page.locator('.cal')).toBeVisible();
		// 7-column grid is the load-bearing layout invariant — the cell
		// count must be a multiple of 7 (full weeks only).
		const cellCount = await page.locator('.cal .grid .cell').count();
		expect(cellCount).toBeGreaterThan(0);
		expect(cellCount % 7).toBe(0);
	});

	test('Day-of-week row is Monday-first (matches week_start_day default)', async ({
		page
	}) => {
		// The rest of the app — `currentWeek` math on /plans/[id],
		// `week_start_day` user setting, weekly mileage stats — all
		// assume Monday-first. A regression to Sunday-first in just
		// the calendar would silently shift the visual layout by one
		// column without breaking the data.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const dow = page.locator('.cal .dow-row span');
		await expect(dow).toHaveText(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
	});

	test('Prev-month button is disabled in the first plan month, Next disabled in the last', async ({
		page
	}) => {
		// PlanCalendar opens on the *current* month if today is inside
		// the plan, else the plan's first month. The seed anchors today
		// mid-plan, so we step back to the first month and pin Prev
		// disabled there. Mirror for Next at the last month. The first/
		// last month labels are live (seed shifts the plan onto now()).
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		const prev = page.locator('.cal .nav[aria-label="Previous month"]');
		const next = page.locator('.cal .nav[aria-label="Next month"]');

		// Walk back until prev disables. The plan spans ~3-4 months, so
		// at most 12 clicks. Guarded against runaway loops.
		for (let i = 0; i < 24; i++) {
			const disabled = await prev.getAttribute('disabled');
			if (disabled !== null) break;
			await prev.click();
		}
		await expect(prev).toBeDisabled();
		await expect(page.locator('.cal-head h3')).toHaveText(FIRST_MONTH_LABEL);

		// Walk forward to the last month + pin Next disabled.
		for (let i = 0; i < 24; i++) {
			const disabled = await next.getAttribute('disabled');
			if (disabled !== null) break;
			await next.click();
		}
		await expect(next).toBeDisabled();
		await expect(page.locator('.cal-head h3')).toHaveText(LAST_MONTH_LABEL);
	});

	test('Today cell carries .today (primary border + shadow)', async ({ page }) => {
		// The today marker is a visual anchor — runners scan the
		// calendar specifically for "where am I now in the plan?". A
		// regression that lost it would not break anything but it
		// would cost the surface its purpose. todayISO() drives the
		// match; pin that at least one .today cell exists when the
		// calendar lands on the current month.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.cal .cell.today').first()).toBeVisible();
	});

	test('A seeded workout cell renders kind pill + distance + kind-colour border-left', async ({
		page
	}) => {
		// Walk to the seed's April (week 1, with the tempo workout
		// 2026-04-07 — kind='tempo', target_distance_m=10000, structure
		// present). The .has-workout class is set only when a
		// plan_workouts row matches the cell's iso date. The kind-colour
		// border-left is inlined as `--kind` style; we read it back to
		// confirm the component dispatched the per-kind colour.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		await walkToMonth(page, SECOND_MONTH_LABEL);

		const cells = page.locator('.cal .cell.has-workout');
		expect(await cells.count()).toBeGreaterThan(0);

		// Pick the tempo cell on Apr 7 specifically — non-rest, has a
		// distance, distinct kind pill. Picking .first() would land on
		// the Mar 30 rest cell from the leading-edge padding (which
		// has no .dist by design).
		const tempoCell = page.locator('.cal .cell.has-workout', {
			has: page.locator('.kind-pill', { hasText: /^Tempo$/ })
		}).first();
		await expect(tempoCell.locator('.kind-pill')).toBeVisible();
		await expect(tempoCell.locator('.dist')).toBeVisible();
		// Inline style carries --kind: <CSS variable>. We don't pin a
		// specific colour because the variables are theme-resolved at
		// the browser level; pin that the attribute exists.
		const styleAttr = (await tempoCell.getAttribute('style')) ?? '';
		expect(styleAttr).toContain('--kind:');
	});

	test('Completed workout cell shows the check icon and .done class', async ({
		page
	}) => {
		// The seed marks the week-0 long run completed via
		// `completed_run_id` (matched to the 2026-03-29 long run row).
		// PlanCalendar's `isWorkoutCompleted` returns true for either
		// `manually_completed = true` OR a non-null completed_run_id.
		// Walk to the plan's first month (where 2026-03-29 lands after
		// the seed shift) + assert at least one .done cell.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		await walkToMonth(page, FIRST_MONTH_LABEL);

		const doneCells = page.locator('.cal .cell.has-workout.done');
		expect(await doneCells.count()).toBeGreaterThanOrEqual(1);
		await expect(doneCells.first().locator('.check')).toBeVisible();
	});

	test('Clicking a workout cell opens the WorkoutEditor (host onSelect handler wins)', async ({
		page
	}) => {
		// /plans/[id] passes an `onSelect` callback to PlanCalendar
		// that sets `editing = wo`. The component branches the cell to
		// a <button> instead of an <a> when onSelect is present
		// (svelte:element + role="button"), so the click goes to the
		// editor rather than navigating to /plans/<id>/workouts/<wid>.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		// Walk to the seed's April so a workout-bearing cell is guaranteed.
		await walkToMonth(page, SECOND_MONTH_LABEL);

		// Capture URL before the click — we expect the modal to open,
		// not a navigation.
		const urlBefore = page.url();
		await page.locator('.cal .cell.has-workout').first().click();
		// WorkoutEditor opens inside a Modal — its .modal-header carries
		// the workout date in the title. URL stays the same.
		await expect(page.locator('.modal')).toBeVisible({ timeout: 5_000 });
		expect(page.url()).toBe(urlBefore);
		// Tidy: close the editor.
		await page.locator('.modal .modal-close').click();
		await expect(page.locator('.modal')).toHaveCount(0);
	});

	test('Cells outside the plan window get .out-plan and no border', async ({ page }) => {
		// PlanCalendar's grid pads the month rectangle to 7-column
		// width with leading/trailing days from the adjacent months.
		// Cells whose iso date falls outside [start_date, end_date]
		// get .out-plan (background:transparent + border-color:
		// transparent in the component CSS). Walk to the plan's first
		// month: the plan starts on a Sunday, so in a Monday-first grid
		// the Mon-Sat of that starting week are leading-edge .out-plan
		// cells regardless of which calendar month the shift lands on.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		await walkToMonth(page, FIRST_MONTH_LABEL);

		// At least one out-plan cell — the start day is a Sunday so the
		// rest of its week (and any earlier leading-edge pad) is out-of-plan.
		expect(await page.locator('.cal .cell.out-plan').count())
			.toBeGreaterThanOrEqual(1);
	});

	test('Rest-day workouts render in the calendar with kind pill but no distance', async ({
		page
	}) => {
		// rest workouts have target_distance_m = null. The component
		// guards `{#if wo.target_distance_m != null && wo.kind !== 'rest'}`
		// before rendering the .dist span. Pin that rest cells exist
		// and have no .dist child.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		await walkToMonth(page, SECOND_MONTH_LABEL);

		// A rest cell has the rest kind pill but no .dist sibling.
		const restCells = page.locator(
			'.cal .cell.has-workout',
			{ has: page.locator('.kind-pill', { hasText: /^Rest$/i }) }
		);
		expect(await restCells.count()).toBeGreaterThan(0);
		// First rest cell should not carry a .dist child.
		await expect(restCells.first().locator('.dist')).toHaveCount(0);
	});

	test('Calendar gracefully renders months with NO workouts (placeholder gap)', async ({
		page
	}) => {
		// Seed weeks 5-10 (seed-dates May 3 - Jun 13) have no plan_workouts
		// rows. The PlanCalendar must still render a month for that window
		// with cells, even though every cell is a plain .cell (no
		// .has-workout). Walk to the live month the seed's mid-gap day maps
		// to after the now()-relative shift; the calendar must not collapse.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		await walkToMonth(page, GAP_MONTH_LABEL);
		// The month plus pads should still render >= 28 cells.
		const cells = page.locator('.cal .grid .cell');
		expect(await cells.count()).toBeGreaterThanOrEqual(28);
		// A few has-workout cells exist for May 1+2 (which are in
		// week 4 of the plan, so they do have rows) but the bulk of
		// May has none. Pin that the May grid is allowed to be sparse.
		const workoutCount = await page.locator('.cal .cell.has-workout').count();
		expect(workoutCount).toBeGreaterThanOrEqual(0);
	});

	test('Newly-marked-done workout flips the calendar cell to .done after reload', async ({
		page
	}) => {
		// Round-trip test: open a non-completed workout via the cal,
		// Mark as done, then re-navigate to the same month and assert
		// the cell now carries .done. Pins the load() → re-fetch path
		// that ties WorkoutEditor's onSaved callback back to the
		// PlanCalendar render. Without it, the calendar would render
		// stale data after a write.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		// Drive the marking via the week-grid `.day-link` (which is the
		// pattern cross-feature.spec.ts already proves stable). Marking
		// also flips the matching calendar cell because PlanCalendar
		// renders from the same `workouts` array. Pick a specific
		// non-completed workout (Apr 7 tempo) to keep this deterministic.
		const tempoDay = page.locator('.weeks .week .day:not(.completed) .day-link', {
			hasText: /Tempo/
		}).first();
		await tempoDay.click();

		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByRole('button', { name: 'Mark as done' }).click();
		await expect(modal).toHaveCount(0);

		// Navigate the calendar to the seed's April — the calendar opens
		// on the current month so the Tempo cell isn't in view until we
		// walk to its month.
		await walkToMonth(page, SECOND_MONTH_LABEL);

		// load() re-fetched; the Apr 7 Tempo cell in the calendar now
		// carries .done. Locate by kind pill so the assertion targets
		// the precise cell — not the seed-completed Apr 5 Long.
		await expect(
			page.locator('.cal .cell.has-workout.done', {
				has: page.locator('.kind-pill', { hasText: /^Tempo$/ })
			})
		).toBeVisible({ timeout: 10_000 });

		// Cleanup — sweep manually_completed=true on the plan back to
		// false. The seed has zero `manually_completed=true` rows so
		// the sweep targets exactly what this test flipped.
		const admin = getAdminClient();
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		if (weekIds.length > 0) {
			await admin
				.from('plan_workouts')
				.update({ manually_completed: false })
				.in('week_id', weekIds)
				.eq('manually_completed', true);
		}
	});

	test('Today marker matches the current ISO date (todayISO drift guard)', async ({
		page
	}) => {
		// `todayISO()` returns YYYY-MM-DD; the cell's iso date is built
		// from year/month/day in the local timezone. A regression that
		// switched todayISO to UTC would cause the marker to land on
		// the wrong day around midnight in CET/CST. Pin that the
		// .today cell's day-number matches Date.now()'s getDate().
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });
		// Browser-resolved expected day number.
		const expected = await page.evaluate(() => new Date().getDate().toString());
		await expect(page.locator('.cal .cell.today .day-num').first())
			.toHaveText(expected, { timeout: 5_000 });
	});

	test('Plan window matches the calendar bounds (drift between plan + cal)', async ({
		page
	}) => {
		// Sanity check: the visible plan window in PlanCalendar's
		// `months` array should run from PLAN_START's month to
		// PLAN_END's month (both live after the seed's now()-relative
		// shift). A regression that off-by-one'd the bounds would
		// silently drop the race week. Walk to the last month and confirm
		// it's the goal-race month.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 10_000 });

		// Step forward until next is disabled. <= 12 clicks for this
		// 12-week plan.
		const next = page.locator('.cal .nav[aria-label="Next month"]');
		for (let i = 0; i < 24; i++) {
			const disabled = await next.getAttribute('disabled');
			if (disabled !== null) break;
			await next.click();
		}
		await expect(next).toBeDisabled();
		const fmtMonth = (iso: string) => {
			const [y, m, d] = iso.split('-').map(Number);
			return new Date(y, m - 1, d).toLocaleDateString('en-GB', {
				month: 'long',
				year: 'numeric'
			});
		};
		await expect(page.locator('.cal-head h3')).toHaveText(fmtMonth(PLAN_END));

		// And the leading edge.
		const prev = page.locator('.cal .nav[aria-label="Previous month"]');
		for (let i = 0; i < 24; i++) {
			const disabled = await prev.getAttribute('disabled');
			if (disabled !== null) break;
			await prev.click();
		}
		await expect(prev).toBeDisabled();
		await expect(page.locator('.cal-head h3')).toHaveText(fmtMonth(PLAN_START));

		// And the formatted race date renders on the hero meta strip,
		// matching PLAN_END. The hero used to print the literal
		// `start_date → end_date` ISO pair; the polished detail page
		// now mirrors the dashboard plan-hero by showing only the
		// formatted race date (en-GB "20 Jun 2026").
		const [y, m, d] = PLAN_END.split('-').map(Number);
		const fmtRaceDate = new Date(y, m - 1, d)
			.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
		await expect(page.locator('.meta')).toContainText(fmtRaceDate);
	});
});
