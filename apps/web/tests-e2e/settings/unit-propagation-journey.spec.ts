import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Unit-propagation JOURNEY — flipping the distance-unit preference once
 * must propagate across EVERY surface that renders distance/pace, on a
 * user who already has real run data, in a single continuous walk.
 *
 * This is the cross-surface companion to the focused specs:
 *   - settings/unit-pref-round-trip.spec.ts pins that the SAME runs
 *     re-render in the right unit on /runs (the list surface) across
 *     km → mi → km, via a SERVICE-ROLE pref flip.
 *   - settings/preferences.spec.ts pins the toggle → /runs (+ dashboard
 *     + detail) propagation via the UI toggle on the SHARED seed user.
 *   - cross-cutting/unit-pref-event-and-race-day.spec.ts pins the
 *     EventEditor + RaceDayPanel LABELS.
 *
 * What none of them does, and this one does: drive the pref change
 * through the REAL Settings → Preferences UI toggle (not a service-role
 * write) and then prove the new value lands on MULTIPLE distinct
 * surfaces — /runs list, /dashboard recent-runs, /runs/[id] detail — in
 * ONE journey, then revert and prove every surface reverts too.
 *
 * Isolation: an EPHEMERAL saga user, NOT the shared seed user. The seed
 * (`runner@test.com`) assumes km, and ~50 other specs render against it;
 * driving its pref through the UI mid-suite would pollute them. The saga
 * user starts at the default km (createSagaUsers upserts preferred_unit
 * 'km') and is deleted in afterAll (CASCADE strips its runs).
 *
 * Propagation mechanism (why a full `goto` is the correct, sleep-free
 * driver — see src/lib/format/units.svelte.ts + stores/auth.svelte.ts):
 *   - `formatDistance` / `formatPace` read the module-level reactive
 *     `unit` signal. The Settings toggle's `pickDistanceUnit` calls
 *     `setUnit(next)` AND dual-writes `user_profiles.preferred_unit`
 *     (awaited) + the settings bag before the "Saved" cue shows.
 *   - The auth store's profile load calls `setUnit(profile.preferred_unit)`
 *     on every fresh app mount. So a full `page.goto` after the save
 *     re-seeds the signal from the persisted pref deterministically —
 *     no waitForTimeout, no networkidle (the pages hold an open realtime
 *     socket that can hang networkidle).
 *
 * Asserted strings, derived from units.svelte.ts (not guessed):
 *   - 10000 m: km → formatDecimal(10, 2) = "10.00 km";
 *              mi → 10000 / 1609.344 = 6.2137… → "6.21 mi".
 *   - 5000 m:  km → "5.00 km"; mi → 5000 / 1609.344 = 3.1069… → "3.11 mi".
 *   - Pace 10000 m / 3000 s: perKm = 300 s = 5:00 → "/km" in km mode;
 *     × 1.609344 = 482.8 s → "/mi" in mi mode (suffix-asserted; the
 *     distance value strings carry the exact-number assertion).
 */

const RUN_A_METRES = 10_000;
const RUN_A_DURATION_S = 3_000; // 10 km in 50:00 → 5:00 /km, ~8:03 /mi
const RUN_B_METRES = 5_000;
const RUN_B_DURATION_S = 1_500;

const RUN_A_KM_TEXT = '10.00 km';
const RUN_A_MI_TEXT = '6.21 mi';
const RUN_B_KM_TEXT = '5.00 km';
const RUN_B_MI_TEXT = '3.11 mi';

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7777';

test.describe('saga: unit pref flip propagates across runs list + dashboard + detail', () => {
	// One continuous multi-surface journey with several full navigations
	// + a UI save round-trip; the default 30 s test timeout is tight.
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];
	let runIdA: string;
	let runIdB: string;

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Saga Units'] });
		const userId = users[0].id;

		// Plant two runs with deterministic distances/durations so both
		// distance AND pace are observable on every surface. Dated now-ish
		// (most-recent-first) so they land in /dashboard's 7-run recent
		// window without any filter dance; the /runs list is then widened
		// to "all" in-journey to bypass its 'today' default.
		runIdA = await insertRun({
			user_id: userId,
			started_at: new Date(Date.now() - 1 * 3600 * 1000).toISOString(),
			duration_s: RUN_A_DURATION_S,
			distance_m: RUN_A_METRES,
			is_public: false,
		});
		runIdB = await insertRun({
			user_id: userId,
			started_at: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
			duration_s: RUN_B_DURATION_S,
			distance_m: RUN_B_METRES,
			is_public: false,
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('km baseline → toggle to mi in Settings → every surface follows → revert to km', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({
			storageState: users[0].storageStatePath,
			baseURL: BASE_URL,
		});
		const page = await ctx.newPage();

		// Anchors reused at every step.
		const runsRowA = page.locator(`a[href="/runs/${runIdA}"]`);
		const runsRowB = page.locator(`a[href="/runs/${runIdB}"]`);
		// Dashboard recent-runs rows share the same href shape.
		const dashRowA = page.locator(`a[href="/runs/${runIdA}"].run-row`);

		try {
			// ── Step 1: km baseline on /runs (list) ──────────────────
			// New saga user defaults to km. Widen the date range to "all"
			// (the list defaults to 'today') so both planted runs render.
			await test.step('km: /runs list renders both runs in km + pace /km', async () => {
				await page.goto('/runs');
				await page.getByLabel('Date range').selectOption('all');

				await expect(runsRowA).toBeVisible({ timeout: 10_000 });
				await expect(runsRowB).toBeVisible({ timeout: 10_000 });

				// First .run-stat-value in a row is the Distance stat;
				// the third is the Pace stat (Distance / Time / Pace).
				await expect(runsRowA.locator('.run-stat-value').first()).toHaveText(
					RUN_A_KM_TEXT,
				);
				await expect(runsRowB.locator('.run-stat-value').first()).toHaveText(
					RUN_B_KM_TEXT,
				);
				await expect(runsRowA.locator('.run-stat-value').nth(2)).toContainText(
					'/km',
				);
				// Negative shape: no mi leaks in km mode.
				await expect(runsRowA.locator('.run-stat-value').first()).not.toContainText(
					'mi',
				);
			});

			// ── Step 2: km baseline on /dashboard (recent runs) ──────
			await test.step('km: /dashboard recent-runs render in km + pace /km', async () => {
				await page.goto('/dashboard');
				await expect(dashRowA).toBeVisible({ timeout: 10_000 });
				await expect(dashRowA.locator('.run-distance')).toHaveText(RUN_A_KM_TEXT);
				await expect(dashRowA.locator('.run-pace')).toContainText('/km');
				await expect(dashRowA.locator('.run-distance')).not.toContainText('mi');
			});

			// ── Step 3: flip the unit to MILES via the real Settings UI ─
			// The headline action of the journey: drive the pref change
			// through the canonical toggle, not a service-role write.
			await test.step('flip to Miles in Settings → Preferences', async () => {
				await page.goto('/settings/preferences');
				await page.getByRole('button', { name: 'Miles', exact: true }).click();
				await expect(page.getByTestId('save-status')).toContainText('Saved', {
					timeout: 8_000,
				});
			});

			// ── Step 4: the SAME runs now render in mi on /runs ──────
			// Full goto re-mounts the app; the auth store re-seeds the unit
			// signal from the now-persisted preferred_unit. Date range
			// persists in localStorage (runs_filters_v1) across the goto.
			await test.step('mi: /runs list re-renders both runs in mi + pace /mi', async () => {
				await page.goto('/runs');
				await expect(runsRowA).toBeVisible({ timeout: 10_000 });
				await expect(runsRowB).toBeVisible();
				await expect(runsRowA.locator('.run-stat-value').first()).toHaveText(
					RUN_A_MI_TEXT,
				);
				await expect(runsRowB.locator('.run-stat-value').first()).toHaveText(
					RUN_B_MI_TEXT,
				);
				await expect(runsRowA.locator('.run-stat-value').nth(2)).toContainText(
					'/mi',
				);
				await expect(runsRowA.locator('.run-stat-value').first()).not.toContainText(
					/\bkm\b/,
				);
			});

			// ── Step 5: /dashboard follows the flip too ──────────────
			await test.step('mi: /dashboard recent-runs re-render in mi + pace /mi', async () => {
				await page.goto('/dashboard');
				await expect(dashRowA).toBeVisible({ timeout: 10_000 });
				await expect(dashRowA.locator('.run-distance')).toHaveText(RUN_A_MI_TEXT);
				await expect(dashRowA.locator('.run-pace')).toContainText('/mi');
				await expect(dashRowA.locator('.run-distance')).not.toContainText(
					/\bkm\b/,
				);
			});

			// ── Step 6: run DETAIL reflects mi for an already-stored run ─
			await test.step('mi: /runs/[id] detail Distance + Avg Pace read mi', async () => {
				await page.goto(`/runs/${runIdA}`);
				const distanceStat = page
					.locator('.key-stat', { hasText: 'Distance' })
					.locator('.key-stat-value');
				await expect(distanceStat).toHaveText(RUN_A_MI_TEXT, { timeout: 10_000 });
				const paceStat = page
					.locator('.key-stat', { hasText: 'Avg Pace' })
					.locator('.key-stat-value');
				await expect(paceStat).toContainText('/mi');
				await expect(paceStat).not.toContainText('/km');
			});

			// ── Step 7: revert to KM via the UI → every surface reverts ─
			// The revert leg catches a regression that cached the converted
			// value anywhere (memoised derived, write-time format) — the
			// runs would otherwise stay stuck at mi.
			await test.step('revert to Kilometres → all surfaces show km again', async () => {
				await page.goto('/settings/preferences');
				await page
					.getByRole('button', { name: 'Kilometres', exact: true })
					.click();
				await expect(page.getByTestId('save-status')).toContainText('Saved', {
					timeout: 8_000,
				});

				// /runs list reverts.
				await page.goto('/runs');
				await expect(runsRowA).toBeVisible({ timeout: 10_000 });
				await expect(runsRowA.locator('.run-stat-value').first()).toHaveText(
					RUN_A_KM_TEXT,
				);
				await expect(runsRowB.locator('.run-stat-value').first()).toHaveText(
					RUN_B_KM_TEXT,
				);

				// /dashboard reverts.
				await page.goto('/dashboard');
				await expect(dashRowA).toBeVisible({ timeout: 10_000 });
				await expect(dashRowA.locator('.run-distance')).toHaveText(RUN_A_KM_TEXT);

				// Detail reverts.
				await page.goto(`/runs/${runIdA}`);
				await expect(
					page
						.locator('.key-stat', { hasText: 'Distance' })
						.locator('.key-stat-value'),
				).toHaveText(RUN_A_KM_TEXT, { timeout: 10_000 });
			});
		} finally {
			await ctx.close();
		}
	});
});
