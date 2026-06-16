import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, insertRoute } from '../fixtures/simulate';

/**
 * Year-in-Running recap data journey — the uncovered, data-driven arc.
 *
 * The existing `recap/page.spec.ts` covers the anon auth-wall, out-of-range
 * year hints, the seed user's populated render, and the share-affordance
 * mechanics (canShare / download / clipboard fallback). It deliberately does
 * NOT plant a known dataset and assert the aggregates reflect it — it leans
 * on whatever the seed happens to log. This spec owns that gap: it mints an
 * ephemeral saga user it fully controls, plants a precise spread of activity
 * inside ONE target year, loads /recap/[year], and asserts every headline the
 * surface computes (hero totals, the eight stat cards, the trophy grid, the
 * monthly chart, the closing CTA) reflects the planted data exactly — then
 * walks the share affordance end-to-end on this owned dataset.
 *
 * Why a saga user (not USER_A): the recap reads the user's ENTIRE run history
 * (fetchRuns is unbounded — recap.ts buckets by year internally). Asserting
 * exact totals requires owning every row in the year, which only an ephemeral
 * user gives us. We wipe the whole dataset in finally.
 *
 * GROUNDING — every number below is derived from the planted rows through the
 * pure aggregator `src/lib/runs/recap.ts#buildYearInRunningRecap`, the data
 * fetch `src/lib/core/data.ts#fetchRecapExtras`, and the km formatter
 * `src/lib/format/units.svelte.ts#fmtKm` (saga users are preferred_unit:'km',
 * set in fixtures/saga-users.ts, so fmtKm renders `(m/1000).toFixed(1) km`).
 *
 * Date window — the Playwright browser is UTC-pinned and the saga user has no
 * timezone offset, so the recap's LOCAL-year bucketing (recap.ts#isWithinYear,
 * Date.getFullYear) and fetchRecapExtras' UTC bounds agree exactly. We anchor
 * every planted timestamp at NOON UTC inside a fixed, fully-past target year
 * (currentYear - 2: in the 2010-2100 valid window, never "still accumulating",
 * never colliding with the seed user's fixed-date runs since this is a fresh
 * user) so no row sits near a midnight boundary where the two windows could
 * disagree.
 */

const TARGET_YEAR = new Date().getUTCFullYear() - 2;

// Noon-UTC timestamp on a given month/day of the target year. Noon keeps the
// run's LOCAL day (recap streak/month bucketing) == its UTC day on the
// UTC-pinned runner, so the planted month + streak are unambiguous.
function dayAt(month1: number, day: number, hour = 12, minute = 0): string {
	return new Date(Date.UTC(TARGET_YEAR, month1 - 1, day, hour, minute, 0)).toISOString();
}

// Mirror of fmtKm for the km unit (saga preferred_unit:'km'): metres/1000 to
// one decimal. We keep planted distances at round multiples of 100 m and total
// distance < 1000 km so there is never a thousands separator to locale-format.
function km1(metres: number): string {
	return `${(metres / 1000).toFixed(1)} km`;
}

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

// A Monday in mid-March of TARGET_YEAR (UTC). recap.ts buckets the top week
// by Monday-start weeks (mondayOf → (getDay()+6)%7), so the 3-day cluster MUST
// start on a Monday or it straddles a week boundary and Top week != the cluster
// sum. Computed (not a hardcoded calendar date) so it lands in one Monday-week
// for ANY TARGET_YEAR. Mid-March ± up to 6 days back stays inside March.
function marchMonday(): Date {
	const d = new Date(Date.UTC(TARGET_YEAR, 2, 15, 12, 0, 0));
	const dow = (d.getUTCDay() + 6) % 7; // 0=Mon … 6=Sun
	d.setUTCDate(d.getUTCDate() - dow);
	return d;
}
const CLUSTER_MON = marchMonday();
// offsetDays from the cluster Monday, at the given UTC clock time.
function clusterAt(offsetDays: number, hour = 12, minute = 0): string {
	const d = new Date(CLUSTER_MON);
	d.setUTCDate(d.getUTCDate() + offsetDays);
	d.setUTCHours(hour, minute, 0, 0);
	return d.toISOString();
}

/**
 * Planted dataset (all in TARGET_YEAR):
 *   - Cluster Mon/Tue/Wed (one Monday-start week): one run each (10k, 8k, half)
 *     → a 3-day best streak (recap.ts#computeRunStreaks over local days) AND
 *     the top week, since all three share a Monday bucket.
 *   - The Wednesday run is the half-marathon at 06:30 → longest run +
 *     Half-marathon badge (long-half tier, longestRunM >= 21097) + earliest
 *     start.
 *   - Jun 1, Sep 1: two more isolated runs in distinct months → 3 active
 *     months total (Mar, Jun, Sep). The two routes give uniqueRouteCount = 2.
 *
 * Longest run = 21097 m (the half). Total = 10000 + 8000 + 21097 + 6000 +
 * 7000 = 52097 m. Top week = the cluster (10000 + 8000 + 21097 = 39097 m).
 * Active months = 3.
 */
const HALF = 21097;
const RUNS: Array<{ at: string; distance_m: number; duration_s: number; route?: 0 | 1 }> = [
	{ at: clusterAt(0), distance_m: 10000, duration_s: 3000, route: 0 },
	{ at: clusterAt(1), distance_m: 8000, duration_s: 2520 },
	{ at: clusterAt(2, 6, 30), distance_m: HALF, duration_s: 7200 }, // 06:30 → earliest start
	{ at: dayAt(6, 1), distance_m: 6000, duration_s: 1980, route: 1 },
	{ at: dayAt(9, 1), distance_m: 7000, duration_s: 2310 }
];
const TOTAL_M = RUNS.reduce((s, r) => s + r.distance_m, 0); // 52097
const TOP_WEEK_M = 10000 + 8000 + HALF; // 39097
const PR_COUNT = 2;
const PHOTO_COUNT = 1;

test.describe('recap year-in-running data journey', () => {
	test.describe.configure({ timeout: 120_000 });

	let user: SagaUser;
	const runIds: string[] = [];
	const routeIds: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		[user] = await createSagaUsers(1, { displayNames: ['Recap Runner'] });

		// Two distinct routes the runs link to → uniqueRouteCount = 2.
		for (let i = 0; i < 2; i++) {
			routeIds.push(
				await insertRoute({
					user_id: user.id,
					name: `Recap Route ${i + 1}`,
					waypoints: [
						{ lat: -37.81 + i * 0.01, lng: 144.96 },
						{ lat: -37.82 + i * 0.01, lng: 144.97 }
					],
					distance_m: 5000
				})
			);
		}

		for (const r of RUNS) {
			runIds.push(
				await insertRun({
					user_id: user.id,
					started_at: r.at,
					distance_m: r.distance_m,
					duration_s: r.duration_s,
					route_id: r.route != null ? routeIds[r.route] : undefined
				})
			);
		}

		// Personal records — recap counts personal_records rows whose
		// achieved_at falls in the UTC year (data.ts#fetchRecapExtras). These
		// are trigger-maintained: inserting the runs above already fired
		// refresh_personal_records_for_user, which bracketed the 10000 m run as
		// '10k' and the 21097 m run as 'half_marathon' (migration 20261021_001:
		// 10k = 9800-10200 m, half = 20675-21519 m), each with achieved_at = the
		// run's started_at (in TARGET_YEAR). The other distances (8/6/7 km) fall
		// between brackets, so the cache holds exactly PR_COUNT = 2 in-year rows
		// — no manual insert (which would dup-key the trigger's '10k' row). The
		// PR card + 'New PR' trophy read this count.

		// One run photo on the half-marathon run → Photos card = 1, 'Documented'
		// trophy fires. fetchRecapExtras joins run_photos!inner(runs.started_at)
		// and filters owner_id + the run's started_at in the year.
		const { error: photoErr } = await admin.from('run_photos').insert({
			run_id: runIds[2],
			owner_id: user.id,
			storage_path: `${user.id}/recap-photo.jpg`,
			position_idx: 0
		});
		if (photoErr) throw new Error(`recap setup: run_photos insert failed: ${photoErr.message}`);
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		// Best-effort teardown of the rows that don't cascade off the run delete
		// cleanly in the order the saga teardown needs. personal_records +
		// run_photos cascade off auth.users delete, but wipe them explicitly so
		// a re-run before deleteSagaUsers can't trip on leftovers.
		await admin.from('run_photos').delete().eq('owner_id', user.id);
		await admin.from('personal_records').delete().eq('user_id', user.id);
		// Runs MUST go before routes — runs.route_id FKs routes with no cascade,
		// so deleting a linked route while its run still exists violates
		// runs_route_id_fkey (and would then block deleteSagaUsers' own routes
		// sweep + the auth.users delete, orphaning the user).
		for (const id of runIds) await admin.from('runs').delete().eq('id', id);
		for (const id of routeIds) await admin.from('routes').delete().eq('id', id);
		// deleteSagaUsers now has nothing left referencing routes/auth.users.
		await deleteSagaUsers([user]);
	});

	test('planted year renders aggregates + trophies + monthly chart + share', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		// Pre-accept the consent banner — it is itself role="dialog" and floats
		// over the page, intercepting the Share-recap click below.
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			await test.step('hero reflects planted totals + active months', async () => {
				await page.goto(`/recap/${TARGET_YEAR}`);

				// Hero kicker + headline (recap.heroKicker / acrossRunsMany).
				await expect(page.getByText(`My ${TARGET_YEAR} in running`).first()).toBeVisible({
					timeout: 15_000
				});
				// bignum = fmtKm(totalDistanceM). 52.097 km → "52.1 km".
				await expect(page.locator('.bignum')).toHaveText(km1(TOTAL_M));
				await expect(page.getByText(`across ${RUNS.length} runs`)).toBeVisible();
				// Active months chip: Mar/Jun/Sep = 3 (recap.activeInMonthsMany).
				await expect(page.getByText('active in 3 months')).toBeVisible();
			});

			await test.step('stat cards reflect the dataset', async () => {
				// Longest run card = fmtKm(longestRunM) = the half (21097 m).
				const longest = page.locator('.card', { hasText: 'Longest run' });
				await expect(longest.locator('.card-value')).toHaveText(km1(HALF));

				// Best streak = 3 (Mar 10/11/12 consecutive). Value cell holds
				// "3 days" — assert the numeric prefix to avoid the <small>.
				const streak = page.locator('.card', { hasText: 'Best streak' });
				await expect(streak.locator('.card-value')).toContainText('3');

				// Top week = fmtKm(39097 m) → "39.1 km" (the Mar 10-12 week).
				const topWeek = page.locator('.card', { hasText: 'Top week' });
				await expect(topWeek.locator('.card-value')).toHaveText(km1(TOP_WEEK_M));

				// Routes run = uniqueRouteCount = 2 (two distinct route_id values).
				const routes = page.locator('.card', { hasText: 'Routes run' });
				await expect(routes.locator('.card-value')).toHaveText('2');

				// Earliest start = the 06:30 half-marathon start (recap.earliestStartLocal).
				const earliest = page.locator('.card', { hasText: 'Earliest start' });
				await expect(earliest.locator('.card-value')).toHaveText('06:30');

				// Personal records card = fetchRecapExtras count = 2.
				const prs = page.locator('.card', { hasText: 'Personal records' });
				await expect(prs.locator('.card-value')).toHaveText(String(PR_COUNT));

				// Photos card = 1 (one run_photos row on a run in the year).
				const photos = page.locator('.card', { hasText: 'Photos' });
				await expect(photos.locator('.card-value')).toHaveText(String(PHOTO_COUNT));
			});

			await test.step('trophy grid earns the data-derived badges', async () => {
				await expect(page.getByRole('heading', { name: 'Trophies' })).toBeVisible();
				// Half-marathon distance badge (long-half tier, longestRunM >= 21097).
				await expect(page.getByText('Half marathon', { exact: true })).toBeVisible();
				// New-PR badge (pr-1 tier, personalRecordCount >= 1 → 2 here).
				await expect(page.getByText('New PR', { exact: true })).toBeVisible();
				// Documented badge (photo-1 tier, photoCount >= 1).
				await expect(page.getByText('Documented', { exact: true })).toBeVisible();
				// The best streak is only 3 days, below the streak-7 tier, so NO
				// streak trophy is earned — guard that the lowest streak badge is absent.
				await expect(page.getByText('Week streak', { exact: true })).toHaveCount(0);
			});

			await test.step('monthly chart has 12 bars with the 3 active months filled', async () => {
				await expect(page.getByRole('heading', { name: 'Distance by month' })).toBeVisible();
				const bars = page.locator('.bar-col');
				await expect(bars).toHaveCount(12);
				// 9 of 12 months are empty (bar-empty); 3 (Mar/Jun/Sep) are filled.
				await expect(page.locator('.bar:not(.bar-empty)')).toHaveCount(3);
				await expect(page.locator('.bar.bar-empty')).toHaveCount(9);
				// Peak label = the busiest month's distance (March = 39097 m).
				await expect(page.getByText(`Peak ${km1(TOP_WEEK_M)}`)).toBeVisible();
			});

			await test.step('closing CTA echoes the total + Share-my-year affordance', async () => {
				await expect(page.getByRole('heading', { name: 'Wrap it up' })).toBeVisible();
				// closingBody bakes in fmtKm(totalDistanceM).
				await expect(page.getByText(`That's ${km1(TOTAL_M)} of effort`)).toBeVisible();
				await expect(
					page.getByRole('button', { name: `Share my ${TARGET_YEAR}` })
				).toBeVisible();
			});

			await test.step('Share recap shares the rendered card image (file-share path)', async () => {
				// Stub canShare/share so the primary file-share branch runs and we
				// can read back what was shared. (Mirrors page.spec.ts's stub but
				// here the payload reflects OUR planted year.)
				await page.evaluate(() => {
					const w = window as unknown as { __shared?: Record<string, unknown> };
					Object.defineProperty(navigator, 'canShare', {
						value: (data: { files?: unknown[] }) => Array.isArray(data?.files),
						configurable: true
					});
					Object.defineProperty(navigator, 'share', {
						value: async (data: { files?: File[]; title?: string }) => {
							w.__shared = {
								fileName: data.files?.[0]?.name ?? null,
								fileType: data.files?.[0]?.type ?? null,
								fileSize: data.files?.[0]?.size ?? 0,
								title: data.title ?? null
							};
						},
						configurable: true
					});
				});

				await page.getByRole('button', { name: 'Share recap' }).click();

				await expect
					.poll(
						() =>
							page.evaluate(
								() => (window as unknown as { __shared?: unknown }).__shared ?? null
							),
						{ timeout: 8_000 }
					)
					.not.toBeNull();
				const payload = (await page.evaluate(
					() => (window as unknown as { __shared: Record<string, unknown> }).__shared
				)) as Record<string, unknown>;
				expect(payload.fileName).toBe(`threkir-${TARGET_YEAR}.png`);
				expect(payload.fileType).toBe('image/png');
				expect(payload.fileSize as number).toBeGreaterThan(0);
				expect(payload.title).toBe(`My ${TARGET_YEAR} in running`);
			});
		} finally {
			await ctx.close();
		}
	});
});
