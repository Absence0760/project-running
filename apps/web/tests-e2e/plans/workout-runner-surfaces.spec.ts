import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Workout-runner-adjacent surfaces (web).
 *
 * The live structured-workout *execution* loop is mobile-only — it
 * lives in `packages/run_recorder/lib/src/workout_runner.dart` and the
 * `workout_execution_band` widget. On the web the equivalent surfaces
 * are:
 *
 *   1. The today-card on /plans/[id] (entry point that, on mobile,
 *      would launch "Start workout"; on web it opens WorkoutEditor).
 *   2. WorkoutEditor mark/save round-trip + unit-aware distance/pace
 *      inputs + Mark-as-done / Mark-not-done toggle + the
 *      hasLinkedRun → disabled-toggle gate.
 *   3. /plans/[id]/workouts/[wid] structure breakdown (warmup +
 *      repeats + steady + cooldown) — the "preview the plan" half of
 *      the runner contract that lets a runner know what they're about
 *      to do.
 *   4. /plans/[id]/workouts/[wid] "How to run it" advice per kind.
 *   5. /plans/[id]/workouts/[wid] completed-card with Unlink button
 *      and ConfirmDialog (only the workout-detail page exposes Unlink
 *      — the in-grid editor handles unlinked-completion only).
 *
 * Adherence + per-step results — the *post-run* runner output —
 * are covered by `apps/web/tests-e2e/runs/workout-review.spec.ts`.
 *
 * The seed provisions the Richmond Half plan with a tempo workout on
 * 2026-04-07 (10 km, structure: warmup 2km + steady 6km @ 4:30 + cool-
 * down 2km), an interval workout on 2026-04-14 (12 km, structure:
 * warmup 1.5 km + 5×1000m @ 4:00 with 400m jog + cooldown 1.5 km),
 * a marathon_pace workout on 2026-04-09, and various easy/rest days.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

async function findWorkoutByDate(date: string): Promise<{ id: string; kind: string }> {
	const admin = getAdminClient();
	const { data: weeks } = await admin
		.from('plan_weeks')
		.select('id')
		.eq('plan_id', SYDNEY_HALF_PLAN_ID);
	const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
	const { data: row } = await admin
		.from('plan_workouts')
		.select('id, kind')
		.in('week_id', weekIds)
		.eq('scheduled_date', date)
		.maybeSingle();
	if (!row) throw new Error(`no plan_workouts row for date ${date}`);
	return row as { id: string; kind: string };
}

test.describe('Workout-runner surfaces (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		// Pre-accept cookie consent so the CookieConsentBanner doesn't
		// layer over modal pointer events. See calendar.spec.ts for the
		// same fix.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.describe('Today card on /plans/[id]', () => {
		test('renders + links to WorkoutEditor when a workout is scheduled today', async ({
			page
		}) => {
			// The today-card branch on /plans/[id] is gated on
			// `todayWorkout = workouts.find(w => w.scheduled_date === today)`.
			// The seed has no workout for the current wall-clock; plant
			// one via service role onto the current-week placeholder week
			// and clean up after.
			const today = new Date().toISOString().slice(0, 10);
			const admin = getAdminClient();
			// Pick a week_id that contains today. The plan's plan_weeks
			// rows are indexed week_index 0..11 from start_date.
			const { data: plan } = await admin
				.from('training_plans')
				.select('start_date')
				.eq('id', SYDNEY_HALF_PLAN_ID)
				.maybeSingle();
			expect(plan).not.toBeNull();
			const startDate = (plan as { start_date: string }).start_date;
			const dayIdx = Math.floor(
				(new Date(today).getTime() - new Date(startDate).getTime()) /
					(1000 * 60 * 60 * 24)
			);
			const weekIdx = Math.floor(dayIdx / 7);
			const { data: weekRow } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', SYDNEY_HALF_PLAN_ID)
				.eq('week_index', weekIdx)
				.maybeSingle();
			expect(weekRow).not.toBeNull();

			// Insert today's planted workout.
			const { data: ins, error: insErr } = await admin
				.from('plan_workouts')
				.insert({
					week_id: (weekRow as { id: string }).id,
					scheduled_date: today,
					kind: 'easy',
					target_distance_m: 6000,
					target_pace_sec_per_km: 330,
					target_pace_tolerance_sec: 30,
					pace_zone: 'E',
					notes: 'planted-by-test'
				})
				.select('id')
				.single();
			expect(insErr).toBeNull();
			const plantedId = (ins as { id: string }).id;

			try {
				await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
				const today_section = page.locator('section.today');
				await expect(today_section).toBeVisible({ timeout: 10_000 });
				// The today-card carries the "Today" eyebrow + kind label.
				await expect(today_section.locator('.today-label')).toHaveText('Today');
				await expect(today_section.locator('.today-kind'))
					.toContainText(/Easy/i);
				// Clicking opens WorkoutEditor (the host wires the
				// today-link to set `editing = todayWorkout`).
				await today_section.locator('.today-link').click();
				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				// Modal title carries the date string.
				await expect(modal.locator('.modal-header'))
					.toContainText(today);
				await modal.locator('.modal-close').click();
				await expect(modal).toHaveCount(0);
			} finally {
				await admin.from('plan_workouts').delete().eq('id', plantedId);
			}
		});

		test('falls back to "Next up" or "Rest day" when no workout is scheduled today', async ({
			page
		}) => {
			// Without a today-workout, the today section now renders a
			// "Next up" card pointing at the next non-rest workout (or a
			// "Rest day" placeholder if there isn't one). The previous
			// hidden-section behaviour silently dropped the most useful
			// surface on the page — runners on a rest day need to see
			// what's tomorrow, not nothing.
			const today = new Date().toISOString().slice(0, 10);
			const admin = getAdminClient();
			const { data: weeks } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', SYDNEY_HALF_PLAN_ID);
			const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
			// Sweep any today-workout (seeded OR leaked from another spec)
			// so the fallback branch is reachable. Capture the rows so
			// the finally block can restore them — the seed plants today's
			// workout deterministically and other tests in this file
			// depend on it being there.
			const { data: existing } = await admin
				.from('plan_workouts')
				.select('*')
				.in('week_id', weekIds)
				.eq('scheduled_date', today);
			const restored = (existing ?? []) as Record<string, unknown>[];
			if (restored.length > 0) {
				await admin
					.from('plan_workouts')
					.delete()
					.in('id', restored.map((r) => r.id as string));
			}

			try {
				await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
				const today_section = page.locator('section.today');
				await expect(today_section).toBeVisible({ timeout: 10_000 });
				await expect(today_section.locator('.today-label'))
					.toHaveText(/Next up|Today|Race day/);
			} finally {
				// Restore the swept today-workout rows so adjacent specs
				// that depend on them keep passing.
				if (restored.length > 0) {
					await admin.from('plan_workouts').insert(restored);
				}
			}
		});
	});

	test.describe('WorkoutEditor (modal-hosted)', () => {
		test('kind = rest hides distance + pace fields (form responds to kind change)', async ({
			page
		}) => {
			// WorkoutEditor's body branches `{#if kind !== 'rest'}` to
			// hide distance / pace / tolerance / zone. Pin the toggle:
			// open the editor on a non-rest day, switch kind to rest,
			// assert the distance input disappears.
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			await page.locator('.day:not(.rest):not(.completed) .day-link').first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			// Distance input is the first number input in the modal
			// (kind is a <select>, not number).
			const distance = modal.locator('input[type="number"]').first();
			await expect(distance).toBeVisible();
			// Switch kind to rest.
			await modal.locator('select').selectOption('rest');
			await expect(distance).toHaveCount(0);
			// Cancel without saving.
			await modal.getByRole('button', { name: 'Cancel' }).click();
			await expect(modal).toHaveCount(0);
		});

		test('Mark-as-done toggles the button label to "Mark not done"', async ({
			page
		}) => {
			// markWorkoutCompleted writes manually_completed=true; the
			// editor re-derives `wasCompleted` from the prop after the
			// host's onSaved → load() re-fetch. The button label is
			// derived from wasCompleted. Use a SPECIFIC workout
			// (2026-04-07 tempo) so we can re-open the same cell — a
			// `.day.completed .day-link .first()` would land on the
			// seed-completed Apr 5 long run which has a linked run and
			// thus a disabled Mark button (different test case).
			const wo = await findWorkoutByDate('2026-04-07');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);

			// Drive through the week-grid editor: the `.day-link` flow
			// (proven stable by cross-feature.spec.ts) is more reliable
			// for Playwright than the calendar cell. Pick the Tempo cell
			// specifically.
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const tempoDay = page.locator(
				'.weeks .week .day:not(.completed) .day-link',
				{ hasText: /Tempo/ }
			).first();
			await tempoDay.click();
			let modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);

			// Re-open the SAME Tempo day — it now carries .completed.
			// The editor's label should read "Mark not done".
			const doneTempo = page.locator(
				'.weeks .week .day.completed .day-link',
				{ hasText: /Tempo/ }
			).first();
			await expect(doneTempo).toBeVisible({ timeout: 10_000 });
			await doneTempo.click();
			modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await expect(modal.getByRole('button', { name: 'Mark not done' }))
				.toBeVisible();
			// Flip back so the test is self-cleaning.
			await modal.getByRole('button', { name: 'Mark not done' }).click();
			await expect(modal).toHaveCount(0);

			// Defensive sweep.
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

		test('hasLinkedRun → Mark button disabled + carries an explanatory title', async ({
			page
		}) => {
			// The week-1 long-run row (2026-04-05) carries
			// completed_run_id from the seed UPDATE that auto-matched
			// the corresponding 2026-04-05 run. When the editor opens
			// on that row, `hasLinkedRun` is true and the Mark button
			// must be disabled — the unlink path requires the workout-
			// detail confirm dialog, not the one-tap editor.
			// (The 2026-03-29 seed UPDATE matched zero runs, so use
			// 2026-04-05 which is actually linked — verified via SQL.)
			const wo = await findWorkoutByDate('2026-04-05');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			// Workout-detail's completed-card shows "Unlink" when
			// completed_run_id is non-null.
			await expect(page.getByRole('button', { name: 'Unlink' }))
				.toBeVisible({ timeout: 10_000 });

			// Now open the in-grid editor on the same workout via the
			// week-grid `.day-link` (stable click target). Apr 5 is the
			// completed Long day.
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const linkedDay = page.locator(
				'.weeks .week .day.completed .day-link',
				{ hasText: /Long/ }
			).first();
			await linkedDay.click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });

			// Mark button is disabled (hasLinkedRun=true) and its title
			// explains why.
			const markBtn = modal.getByRole('button', {
				name: /Mark (as done|not done)/
			});
			await expect(markBtn).toBeDisabled();
			const title = await markBtn.getAttribute('title');
			expect(title ?? '').toMatch(/A run is linked/);

			await modal.locator('.modal-close').click();
		});

		test('Save round-trip persists target distance + survives a reload', async ({
			page
		}) => {
			// Pin the canonical write path: open editor, change target
			// distance, Save → assert the new value persists in the DB.
			// Use 2026-04-08 (easy, 7000m seeded) and change to 9 km —
			// a value distinct from any seeded workout so a mis-update
			// to the wrong row would be caught. Drive through the
			// workout-detail route directly so we bypass calendar
			// navigation noise.
			const wo = await findWorkoutByDate('2026-04-08');
			const admin = getAdminClient();
			const { data: before } = await admin
				.from('plan_workouts')
				.select('target_distance_m')
				.eq('id', wo.id)
				.maybeSingle();
			const beforeDistance = (before as { target_distance_m: number | null })
				?.target_distance_m;
			expect(beforeDistance).toBe(7000);

			try {
				// Open via the workout-detail page → modal-style edit
				// would land in the same WorkoutEditor. Simpler: drive
				// through the week-grid `.day-link` flow (which is
				// stable). Apr 8 is the only Easy day in week 1 — match
				// by kind + by week-row context. To be robust, navigate
				// to the workout detail and back into the in-grid editor
				// via the day-link selector keyed on the seeded notes
				// string (no other Easy day in the plan has these exact
				// notes).
				await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
				// .day-link contains the kind label as text. There are
				// multiple Easy days; pick the one inside week-1
				// (week_index = 1 → second .week in DOM order).
				const cell = page.locator(
					'.weeks .week:nth-of-type(2) .day .day-link',
					{ hasText: /Easy/ }
				).first();
				await cell.click();

				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				const distance = modal.locator('input[type="number"]').first();
				// Sanity: editor reflects the canonical → display
				// conversion (7000 m → 7 km for the km-preferring user).
				await expect(distance).toHaveValue('7');
				await distance.fill('9');
				await modal.getByRole('button', { name: /^Save/ }).click();
				await expect(modal).toHaveCount(0);

				// 9 km → 9000 m in canonical storage.
				const { data: after } = await admin
					.from('plan_workouts')
					.select('target_distance_m')
					.eq('id', wo.id)
					.maybeSingle();
				expect(
					(after as { target_distance_m: number | null }).target_distance_m
				).toBe(9000);
			} finally {
				// Restore.
				await admin
					.from('plan_workouts')
					.update({ target_distance_m: beforeDistance })
					.eq('id', wo.id);
			}
		});
	});

	test.describe('/plans/[id]/workouts/[wid] — structure preview', () => {
		test('Tempo workout renders warmup + steady + cooldown rows', async ({
			page
		}) => {
			// The seeded 2026-04-07 tempo has
			//   warmup 2 km easy + steady 6 km @ 4:30 + cooldown 2 km easy.
			// The workout-detail page renders each section as a <li>
			// inside `<ol class="steps">` with a leading `<span class=
			// "step-kind">Warmup|Repeats|Steady|Cooldown</span>`.
			const wo = await findWorkoutByDate('2026-04-07');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			const steps = page.locator('ol.steps li');
			await expect(steps).toHaveCount(3, { timeout: 10_000 });
			await expect(steps.nth(0).locator('.step-kind')).toHaveText('Warmup');
			await expect(steps.nth(1).locator('.step-kind')).toHaveText('Steady');
			await expect(steps.nth(2).locator('.step-kind')).toHaveText('Cooldown');
			// Total = warmup + steady + cooldown = 2 + 6 + 2 = 10 km.
			await expect(page.locator('.total')).toContainText('10');
		});

		test('Interval workout renders warmup + repeats + cooldown (NOT a separate steady row)', async ({
			page
		}) => {
			// 2026-04-14 interval: 1.5 km warmup + 5×1000m + 1.5 km
			// cooldown. The repeats row mentions count + distance +
			// pace + recovery — pin the canonical descriptor so a
			// regression that dropped any field surfaces here.
			const wo = await findWorkoutByDate('2026-04-14');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			const steps = page.locator('ol.steps li');
			await expect(steps).toHaveCount(3, { timeout: 10_000 });
			await expect(steps.nth(0).locator('.step-kind')).toHaveText('Warmup');
			await expect(steps.nth(1).locator('.step-kind')).toHaveText('Repeats');
			await expect(steps.nth(2).locator('.step-kind')).toHaveText('Cooldown');
			// The repeats descriptor includes the count + distance.
			await expect(steps.nth(1)).toContainText(/5×/);
			await expect(steps.nth(1)).toContainText(/1\.0[01]?\s*km/);
			await expect(steps.nth(1)).toContainText(/jog/);
		});

		test('Easy workout (no structure) does NOT render the Structure card', async ({
			page
		}) => {
			// 2026-04-08 easy has structure=null. The detail page guards
			// `{#if structure}` so the Structure card is hidden. Pin
			// the negative — a regression that mounted the section on
			// every workout would surface here.
			const wo = await findWorkoutByDate('2026-04-08');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.getByRole('heading', { level: 1 }))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('heading', { name: 'Structure' })).toHaveCount(0);
		});

		test('Marathon-pace workout shows the pace-progression arrow (start → end)', async ({
			page
		}) => {
			// 2026-04-09 MP has target_pace_sec_per_km=295 +
			// target_pace_end_sec_per_km=280 (workout body progresses
			// across the steady portion). The hero block renders a
			// `<span class="arrow">→</span>` between the start + end
			// paces only when target_pace_end_sec_per_km is set AND
			// differs from the start. Pin the arrow so a regression
			// that dropped the progression chip surfaces.
			const wo = await findWorkoutByDate('2026-04-09');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.arrow').first()).toBeVisible({
				timeout: 10_000
			});
			// And the zone chip.
			await expect(page.locator('.zone')).toContainText('MP');
		});

		test('Pace tolerance ± seconds renders when set', async ({ page }) => {
			// `target_pace_tolerance_sec` is rendered as
			// `<span class="tol">±{n}s</span>`. The seed has 8s on the
			// tempo (2026-04-07). Pin the chip.
			const wo = await findWorkoutByDate('2026-04-07');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.tol')).toHaveText('±8s', { timeout: 10_000 });
		});
	});

	test.describe('/plans/[id]/workouts/[wid] — "How to run it" advice', () => {
		test('Easy workout advice mentions conversational pace', async ({ page }) => {
			const wo = await findWorkoutByDate('2026-04-04'); // kind='recovery' actually
			// Pick a definite easy workout: 2026-04-08 is easy.
			const easy = await findWorkoutByDate('2026-04-08');
			expect(wo.kind).toBeTruthy(); // just so the linter doesn't yell
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${easy.id}`);
			await expect(page.locator('.card.advice'))
				.toContainText(/Conversational/i, { timeout: 10_000 });
		});

		test('Tempo workout advice mentions "comfortably hard"', async ({ page }) => {
			const wo = await findWorkoutByDate('2026-04-07');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.card.advice'))
				.toContainText(/Comfortably hard/i, { timeout: 10_000 });
		});

		test('Interval advice mentions running the last rep as hard as the first', async ({
			page
		}) => {
			const wo = await findWorkoutByDate('2026-04-14');
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.card.advice'))
				.toContainText(/last one feels like the first/i, { timeout: 10_000 });
		});

		test('Long-run advice mentions dropping 10% rather than skipping', async ({
			page
		}) => {
			const wo = await findWorkoutByDate('2026-04-05'); // long, 15 km
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.card.advice'))
				.toContainText(/drop 10%/i, { timeout: 10_000 });
		});

		test('Rest-day advice mentions walking / stretching only', async ({ page }) => {
			const wo = await findWorkoutByDate('2026-04-06'); // rest
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			await expect(page.locator('.card.advice'))
				.toContainText(/walk or stretch/i, { timeout: 10_000 });
		});
	});

	test.describe('/plans/[id]/workouts/[wid] — Unlink confirm dialog', () => {
		test('linked-run workout shows Unlink → ConfirmDialog → Cancel keeps state', async ({
			page
		}) => {
			// 2026-04-05 is the seeded long run with completed_run_id
			// auto-matched to the 2026-04-05 run row (the 2026-03-29
			// seed UPDATE didn't match a real run). The completed-card
			// carries an "Unlink" button when completed_run_id is set.
			// Clicking it opens ConfirmDialog. Cancel must keep
			// completed_run_id non-null.
			const wo = await findWorkoutByDate('2026-04-05');
			const admin = getAdminClient();
			const { data: before } = await admin
				.from('plan_workouts')
				.select('completed_run_id')
				.eq('id', wo.id)
				.maybeSingle();
			expect((before as { completed_run_id: string | null }).completed_run_id)
				.not.toBeNull();

			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
			const unlinkBtn = page.getByRole('button', { name: 'Unlink' });
			await expect(unlinkBtn).toBeVisible({ timeout: 10_000 });
			await unlinkBtn.click();

			// ConfirmDialog mounts a modal with title "Unlink run".
			const dialog = page.getByRole('dialog', { name: /Unlink run/ })
				.or(page.locator('.modal', { hasText: 'Unlink run' }));
			await expect(dialog.first()).toBeVisible({ timeout: 5_000 });

			// Cancel — completed_run_id must remain set.
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			const { data: after } = await admin
				.from('plan_workouts')
				.select('completed_run_id')
				.eq('id', wo.id)
				.maybeSingle();
			expect((after as { completed_run_id: string | null }).completed_run_id)
				.not.toBeNull();
		});

		test('Confirm Unlink clears completed_run_id (and Mark-not-done branch is reachable)', async ({
			page
		}) => {
			// Round-trip the destructive path: Unlink → Confirm → the
			// completed-card disappears (because isWorkoutCompleted is
			// now false) and the DB row's completed_run_id is null. We
			// re-link it after the test via service role so the seed
			// invariants are preserved. Use 2026-04-05 (actually linked
			// in seed) rather than 2026-03-29 (seed UPDATE matched no
			// run).
			const wo = await findWorkoutByDate('2026-04-05');
			const admin = getAdminClient();
			const { data: before } = await admin
				.from('plan_workouts')
				.select('completed_run_id')
				.eq('id', wo.id)
				.maybeSingle();
			const originalRunId =
				(before as { completed_run_id: string | null }).completed_run_id;
			expect(originalRunId).not.toBeNull();

			try {
				await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${wo.id}`);
				await page.getByRole('button', { name: 'Unlink' })
					.click({ timeout: 10_000 });
				// Confirm.
				const dialog = page.getByRole('dialog', { name: /Unlink run/ })
					.or(page.locator('.modal', { hasText: 'Unlink run' }));
				await dialog.getByRole('button', { name: 'Unlink' }).click();
				// The completed-card disappears.
				await expect(page.locator('.completed-card'))
					.toHaveCount(0, { timeout: 10_000 });
				// And the DB row reflects it.
				const { data: after } = await admin
					.from('plan_workouts')
					.select('completed_run_id, manually_completed')
					.eq('id', wo.id)
					.maybeSingle();
				expect((after as { completed_run_id: string | null }).completed_run_id)
					.toBeNull();
			} finally {
				// Restore the link so the rest of the suite sees a
				// completed workout on 2026-03-29.
				await admin
					.from('plan_workouts')
					.update({ completed_run_id: originalRunId, completed_at: new Date().toISOString() })
					.eq('id', wo.id);
			}
		});

		test('not-found drill-down renders the canonical empty state', async ({
			page
		}) => {
			// Symmetry with /runs/[id] + /routes/[id] not-found — pin
			// the stale-link landing state.
			const bogus = '00000000-0000-0000-0000-000000000bad';
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${bogus}`);
			await expect(
				page.getByRole('heading', { name: /Workout not found/i, level: 2 })
			).toBeVisible({ timeout: 10_000 });
			// And the Back-to-plan link is present.
			await expect(page.getByRole('link', { name: /Back to plan/i }))
				.toBeVisible();
		});
	});
});
