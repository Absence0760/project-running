import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — Workout review section.
 *
 * When a run carries `metadata.workout_step_results` (set by the
 * recorder when the user runs against a `plan_workouts` row), the
 * detail page renders a "Workout" section with:
 *   - Adherence pill (on / amber / off)
 *   - Workout name + planned distance
 *   - A per-step table: Step / Plan / Actual / Pace / Δ
 *
 * The renderer is `apps/web/src/routes/runs/[id]/+page.svelte` lines
 * 1009-1064. The Dart parity is `workout_review_section_test.dart`
 * (11 tests); web-side has no e2e coverage of the section beyond
 * "doesn't leak via public_runs view" (cross-cutting/public-runs).
 *
 * These tests plant `metadata` on a real run via service-role and
 * pin the section's render across the three adherence states +
 * mixed distance / duration steps + the skipped-step badge.
 */

const PLANNED_M = 5000;

function distanceStep(opts: {
	step_idx: number;
	target_distance_m: number;
	actual_distance_m: number;
	actual_pace_sec_per_km: number;
	duration_s: number;
	status?: 'completed' | 'skipped';
}): Record<string, unknown> {
	return {
		step_idx: opts.step_idx,
		kind: 'rep',
		target_distance_m: opts.target_distance_m,
		actual_distance_m: opts.actual_distance_m,
		actual_pace_sec_per_km: opts.actual_pace_sec_per_km,
		duration_s: opts.duration_s,
		status: opts.status ?? 'completed',
	};
}

test.describe('/runs/[id] — Workout review section', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('section is HIDDEN when metadata.workout_step_results is absent', async ({
		page
	}) => {
		// Default seeded run has no workout_step_results → the section
		// must not render. Pin the negative so a regression that
		// mounted the section on every run is caught.
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		await page.goto(`/runs/${runId}`);
		// The section header is `<h2>Workout</h2>` inside .workout-review.
		await expect(page.locator('section.workout-review')).toHaveCount(0);
	});

	test('on-adherence run: pill + per-step rows render with correct counts', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_adherence: 'on',
					workout_step_results: [
						distanceStep({
							step_idx: 0,
							target_distance_m: 2000,
							actual_distance_m: 2010,
							actual_pace_sec_per_km: 330,
							duration_s: 660
						}),
						distanceStep({
							step_idx: 1,
							target_distance_m: 3000,
							actual_distance_m: 3020,
							actual_pace_sec_per_km: 335,
							duration_s: 1011
						}),
					]
				}
			})
			.eq('id', runId);

		await page.goto(`/runs/${runId}`);
		await page.waitForLoadState('networkidle');
		const section = page.locator('section.workout-review');
		await expect(section).toBeVisible({ timeout: 10_000 });
		await expect(section.getByRole('heading', { name: 'Workout' })).toBeVisible();
		// Adherence pill carries the modifier class.
		await expect(section.locator('.workout-adherence-on')).toBeVisible();
		// Two body rows for two steps.
		await expect(section.locator('tbody tr')).toHaveCount(2);
	});

	test('amber adherence flips the pill class', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_adherence: 'amber',
					workout_step_results: [
						distanceStep({
							step_idx: 0,
							target_distance_m: 5000,
							actual_distance_m: 4800,
							actual_pace_sec_per_km: 350,
							duration_s: 1680
						})
					]
				}
			})
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		await expect(page.locator('.workout-adherence-amber')).toBeVisible({ timeout: 10_000 });
		// Negative — the 'on' modifier must NOT render simultaneously.
		await expect(page.locator('.workout-adherence-on')).toHaveCount(0);
	});

	test('off-adherence pill renders the off variant', async ({ page }) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 2000,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_adherence: 'off',
					workout_step_results: [
						distanceStep({
							step_idx: 0,
							target_distance_m: 5000,
							actual_distance_m: 3000,
							actual_pace_sec_per_km: 420,
							duration_s: 1260
						})
					]
				}
			})
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		await expect(page.locator('.workout-adherence-off')).toBeVisible({ timeout: 10_000 });
	});

	test('skipped step renders the skip badge in the Δ column + visual skipped class', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_adherence: 'amber',
					workout_step_results: [
						distanceStep({
							step_idx: 0,
							target_distance_m: 2000,
							actual_distance_m: 2010,
							actual_pace_sec_per_km: 330,
							duration_s: 660
						}),
						distanceStep({
							step_idx: 1,
							target_distance_m: 3000,
							actual_distance_m: 0,
							actual_pace_sec_per_km: 0,
							duration_s: 0,
							status: 'skipped'
						})
					]
				}
			})
			.eq('id', runId);

		await page.goto(`/runs/${runId}`);
		await page.waitForLoadState('networkidle');
		const section = page.locator('section.workout-review');
		await expect(section).toBeVisible({ timeout: 10_000 });
		// Both rows present, one with .skipped class.
		await expect(section.locator('tbody tr')).toHaveCount(2);
		await expect(section.locator('tbody tr.skipped')).toHaveCount(1);
		// Skip badge in the Δ column of the skipped row.
		await expect(section.locator('tbody tr.skipped .pace-delta')).toHaveText('skip');
	});

	test('table header carries the canonical column labels', async ({ page }) => {
		// The 5-column layout (Step / Plan / Actual / Pace / Δ) is the
		// load-bearing UX contract — a regression that dropped a column
		// or relabelled it would silently change the way users read
		// adherence. Pin every header label.
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_adherence: 'on',
					workout_step_results: [
						distanceStep({
							step_idx: 0,
							target_distance_m: 5000,
							actual_distance_m: 5010,
							actual_pace_sec_per_km: 330,
							duration_s: 1653
						})
					]
				}
			})
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		await page.waitForLoadState('networkidle');
		const headers = page.locator('table.workout-table thead th');
		await expect(headers).toHaveText(['Step', 'Plan', 'Actual', 'Pace', 'Δ']);
	});

	test('section is hidden if workout_step_results is an empty array (defence-in-depth)', async ({
		page
	}) => {
		// `{#if workoutStepResults.length > 0}` guards the section.
		// An empty array satisfies the typing but should not render —
		// confirms the length-check is the gate, not just truthiness.
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: PLANNED_M,
			duration_s: 1500,
			is_public: false
		});
		const admin = getAdminClient();
		await admin
			.from('runs')
			.update({
				metadata: {
					activity_type: 'run',
					workout_step_results: []
				}
			})
			.eq('id', runId);
		await page.goto(`/runs/${runId}`);
		await expect(page.locator('section.workout-review')).toHaveCount(0);
	});
});
