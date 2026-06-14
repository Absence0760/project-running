import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id]/workouts/[wid] — single-workout drill-down.
 *
 * The week-grid on /plans/[id] opens an in-place WorkoutEditor modal
 * (covered in plans/detail.spec.ts). The standalone workout-detail
 * page is the alternative route — used by deep links from the coach
 * surface, and by the "View workout" path that some plan templates
 * emit. Workout IDs are auto-generated, so we query one off the
 * seeded Richmond Half plan via service-role.
 *
 * Future depth: mark complete + unlink (button + ConfirmDialog),
 * plan-workout-with-structure renders the warmup / repeats / cooldown
 * breakdown.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/[id]/workouts/[wid]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the workout kind heading + Back-to-plan link', async ({
		page
	}) => {
		// Seed plan_workouts ids are auto-generated; pick the first
		// one off the plan's first week so we have a deterministic
		// target. The admin client bypasses RLS — fine for fixture
		// setup, never for the assertion (we navigate as runner).
		const { data: weekRow } = await getAdminClient()
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SEED_PLAN_ID)
			.eq('week_index', 0)
			.maybeSingle();
		expect(weekRow).not.toBeNull();
		const { data: woRow } = await getAdminClient()
			.from('plan_workouts')
			.select('id, kind')
			.eq('week_id', (weekRow as { id: string }).id)
			.order('scheduled_date', { ascending: true })
			.limit(1)
			.maybeSingle();
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string; kind: string };

		await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);

		// h1 is the workout kind label (Easy / Tempo / Long / Rest /
		// Recovery, etc). The kind is a free-form string in the seed —
		// we match the page's WORKOUT_KIND_LABEL fallback (which uses
		// the raw kind when no label is mapped) by asserting the h1
		// is non-empty rather than pinning a specific label.
		const h1 = page.getByRole('heading', { level: 1 });
		await expect(h1).toBeVisible({ timeout: 10_000 });
		const text = (await h1.textContent())?.trim() ?? '';
		expect(text.length).toBeGreaterThan(0);

		// "Back to plan" link returns to /plans/[id] — proves we hit
		// the loaded-row branch, not the not-found state (which has
		// the link too, but with text "Back to plan" inside an h2
		// "Workout not found" block).
		await expect(
			page.getByRole('heading', { name: 'Workout not found' })
		).toHaveCount(0);

		// Click the back link — verifies the link href is right.
		await page.getByRole('link', { name: /Back to plan/i }).first().click();
		await expect(page).toHaveURL(new RegExp(`/plans/${SEED_PLAN_ID}$`));
	});

	test('skip + un-skip a workout from the detail page', async ({ page }) => {
		// Pick a non-rest, non-completed workout off the plan so the
		// Skip control renders (rest days + linked-run workouts don't
		// show it). Reset its skip state after so the test is idempotent.
		const admin = getAdminClient();
		const { data: weekRow } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SEED_PLAN_ID)
			.eq('week_index', 0)
			.maybeSingle();
		const { data: woRow } = await admin
			.from('plan_workouts')
			.select('id, kind')
			.eq('week_id', (weekRow as { id: string }).id)
			.neq('kind', 'rest')
			.is('completed_run_id', null)
			.order('scheduled_date', { ascending: true })
			.limit(1)
			.maybeSingle();
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string };

		try {
			await admin
				.from('plan_workouts')
				.update({ skipped_at: null, manually_completed: false })
				.eq('id', wo.id);

			await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);

			// Skip it — the "Skipped" badge + an Un-skip button appear.
			await page.getByRole('button', { name: /^Skip this workout$/i }).click();
			await expect(page.getByText('Skipped', { exact: true })).toBeVisible({
				timeout: 10_000
			});
			const unskip = page.getByRole('button', { name: /^Un-skip$/i });
			await expect(unskip).toBeVisible();

			// Server-side: skipped_at stamped.
			const { data: afterSkip } = await admin
				.from('plan_workouts')
				.select('skipped_at')
				.eq('id', wo.id)
				.maybeSingle();
			expect((afterSkip as { skipped_at: string | null }).skipped_at).not.toBeNull();

			// Un-skip returns it to a plain to-do (the Skip button is back).
			await unskip.click();
			await expect(
				page.getByRole('button', { name: /^Skip this workout$/i })
			).toBeVisible({ timeout: 10_000 });
			const { data: afterUnskip } = await admin
				.from('plan_workouts')
				.select('skipped_at')
				.eq('id', wo.id)
				.maybeSingle();
			expect((afterUnskip as { skipped_at: string | null }).skipped_at).toBeNull();
		} finally {
			await admin
				.from('plan_workouts')
				.update({ skipped_at: null })
				.eq('id', wo.id);
		}
	});

	test('not-found: visiting a missing workout id renders "Workout not found"', async ({
		page
	}) => {
		// Stale-link landing protection — same shape as /runs/[id] +
		// /routes/[id] + /plans/[id] not-found tests.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${bogusId}`);
		await expect(
			page.getByRole('heading', { name: /Workout not found/i })
		).toBeVisible({ timeout: 10_000 });
	});
});
