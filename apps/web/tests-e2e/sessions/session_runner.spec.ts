import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session follow-along player (session_planner.md P2 / instructor M5) — drives
 * the SessionRunner overlay that /sessions/[id] mounts when "Start session" is
 * tapped. Covers the player's whole surface: mount on the first step, a timed
 * step auto-advancing, a reps step waiting on Done, a per-side step showing L
 * then R, a finished run logging a gym_workout with the session metadata
 * (session_plan_id / session_step_results / session_adherence), and an abandon
 * via the ConfirmDialog leaving without saving.
 *
 * Plans are seeded directly (service role) so each test exercises the runner
 * with the exact step shape it needs — the editor build flow is covered by
 * session-plan.spec.ts. Unique titles per run so the shared seed DB never
 * collides on assertions or cleanup.
 */

type ItemSeed = {
	position: number;
	movement_name: string;
	kind: 'hold' | 'reps' | 'flow';
	duration_s?: number | null;
	reps?: number | null;
	per_side?: boolean;
};

type WorkoutRow = { id: string; title: string | null; metadata: Record<string, unknown> };

test.describe('/sessions/[id] — follow-along player', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];
	const createdWorkoutIds: string[] = [];

	async function seedPlan(discipline: string, items: ItemSeed[]): Promise<string> {
		const admin = getAdminClient();
		const title = `e2e-runner ${discipline} ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: planRow, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline })
			.select('id')
			.single();
		if (error) throw error;
		const planId = planRow!.id as string;
		createdPlanIds.push(planId);

		await admin.from('session_plan_items').insert(
			items.map((it) => ({
				plan_id: planId,
				position: it.position,
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: it.duration_s ?? null,
				reps: it.reps ?? null,
				per_side: it.per_side ?? false
			}))
		);
		return planId;
	}

	async function findWorkout(planId: string): Promise<WorkoutRow | undefined> {
		const admin = getAdminClient();
		const { data } = await admin
			.from('gym_workouts')
			.select('id, title, metadata')
			.eq('user_id', USER_A.id);
		const match = ((data ?? []) as WorkoutRow[]).find(
			(w) => w.metadata?.session_plan_id === planId
		);
		if (match) createdWorkoutIds.push(match.id);
		return match;
	}

	async function start(page: import('@playwright/test').Page, planId: string, title: string) {
		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('session-start').click();
		const runner = page.getByTestId('session-runner');
		await expect(runner).toBeVisible();
		return runner;
	}

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdWorkoutIds.splice(0)) {
			try {
				await admin.from('gym_workouts').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdPlanIds.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('Start mounts the runner on the first step', async ({ page }) => {
		const admin = getAdminClient();
		const { data: planRow } = await admin
			.from('session_plans')
			.insert({
				author_id: USER_A.id,
				title: `e2e-runner mount ${Date.now()}`,
				discipline: 'Mobility'
			})
			.select('id, title')
			.single();
		const planId = planRow!.id as string;
		const title = planRow!.title as string;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert([
			{ plan_id: planId, position: 0, movement_name: 'Cat Cow', kind: 'reps', reps: 10 },
			{ plan_id: planId, position: 1, movement_name: 'Child Pose', kind: 'hold', duration_s: 30 }
		]);

		const runner = await start(page, planId, title);
		const band = runner.getByTestId('session-execution-band');
		await expect(band).toBeVisible();
		await expect(band.getByTestId('session-step-name')).toHaveText('Cat Cow');
		await expect(band.getByText('Step 1 of 2')).toBeVisible();
	});

	test('a timed step counts down and auto-advances', async ({ page }) => {
		const discipline = 'Flow';
		const planId = await seedPlan(discipline, [
			{ position: 0, movement_name: 'Sun Salute', kind: 'flow', duration_s: 2 },
			{ position: 1, movement_name: 'The Hundred', kind: 'reps', reps: 100 }
		]);
		const { data } = await getAdminClient()
			.from('session_plans')
			.select('title')
			.eq('id', planId)
			.single();

		const runner = await start(page, planId, data!.title as string);
		const band = runner.getByTestId('session-execution-band');

		await expect(band.getByTestId('session-step-name')).toHaveText('Sun Salute');
		await expect(band.getByTestId('session-remaining')).toBeVisible();
		// The 2s timer expires on its own and surfaces the next step — no tap.
		await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred', {
			timeout: 10_000
		});
	});

	test('a reps step waits and Done advances', async ({ page }) => {
		const planId = await seedPlan('Core', [
			{ position: 0, movement_name: 'The Hundred', kind: 'reps', reps: 100 },
			{ position: 1, movement_name: 'Roll Up', kind: 'reps', reps: 8 }
		]);
		const { data } = await getAdminClient()
			.from('session_plans')
			.select('title')
			.eq('id', planId)
			.single();

		const runner = await start(page, planId, data!.title as string);
		const band = runner.getByTestId('session-execution-band');

		// A reps step has no countdown and never auto-advances; it sits until Done.
		await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred');
		await expect(band.getByTestId('session-remaining')).toHaveCount(0);
		await page.waitForTimeout(1_000);
		await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred');

		await band.getByTestId('session-done').click();
		await expect(band.getByTestId('session-step-name')).toHaveText('Roll Up');
	});

	test('a per-side step shows Left then Right', async ({ page }) => {
		const planId = await seedPlan('Mobility', [
			{ position: 0, movement_name: 'Pigeon', kind: 'reps', reps: 12, per_side: true }
		]);
		const { data } = await getAdminClient()
			.from('session_plans')
			.select('title')
			.eq('id', planId)
			.single();

		const runner = await start(page, planId, data!.title as string);
		const band = runner.getByTestId('session-execution-band');

		await expect(band.getByTestId('session-step-name')).toHaveText('Pigeon (Left)');
		await band.getByTestId('session-done').click();
		await expect(band.getByTestId('session-step-name')).toHaveText('Pigeon (Right)');
	});

	test('finishing logs a gym_workout with the session adherence metadata', async ({ page }) => {
		const discipline = 'Mobility';
		const planId = await seedPlan(discipline, [
			{ position: 0, movement_name: 'Cat Cow', kind: 'flow', duration_s: 2 },
			{ position: 1, movement_name: 'The Hundred', kind: 'reps', reps: 100 }
		]);
		const { data } = await getAdminClient()
			.from('session_plans')
			.select('title')
			.eq('id', planId)
			.single();

		const runner = await start(page, planId, data!.title as string);
		const band = runner.getByTestId('session-execution-band');

		// The 2s flow auto-advances to the reps step; Done on the last step finishes.
		await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred', {
			timeout: 10_000
		});
		await band.getByTestId('session-done').click();
		await expect(runner).toBeHidden({ timeout: 10_000 });

		await expect(page.getByText('Session saved.')).toBeVisible({ timeout: 10_000 });

		await expect.poll(async () => !!(await findWorkout(planId)), { timeout: 10_000 }).toBe(true);
		const workout = (await findWorkout(planId))!;

		expect(workout.title).toBe(discipline);
		expect(workout.metadata.session_plan_id).toBe(planId);
		expect(workout.metadata.session_adherence).toBe('completed');
		expect(Array.isArray(workout.metadata.session_step_results)).toBe(true);
		expect((workout.metadata.session_step_results as unknown[]).length).toBe(2);
	});

	test('abandon via the confirm dialog leaves without saving', async ({ page }) => {
		const planId = await seedPlan('Mobility', [
			{ position: 0, movement_name: 'Child Pose', kind: 'hold', duration_s: 30 },
			{ position: 1, movement_name: 'The Hundred', kind: 'reps', reps: 100 }
		]);
		const { data } = await getAdminClient()
			.from('session_plans')
			.select('title')
			.eq('id', planId)
			.single();

		const runner = await start(page, planId, data!.title as string);
		const band = runner.getByTestId('session-execution-band');

		await band.getByTestId('session-abandon').click();
		const dialog = page.getByTestId('session-abandon-dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Discard' }).click();
		await expect(runner).toBeHidden();

		// Nothing was logged for this plan.
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('gym_workouts')
			.select('id, metadata')
			.eq('user_id', USER_A.id);
		const matches = ((rows ?? []) as { id: string; metadata: Record<string, unknown> }[]).filter(
			(w) => w.metadata?.session_plan_id === planId
		);
		expect(matches.length).toBe(0);
	});
});
