import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session follow-along player — the two control paths a yoga / pilates
 * instructor relies on that session_runner.spec.ts doesn't cover:
 *
 * (a) SKIP a step mid-session → the finished gym_workout logs
 *     session_adherence = 'partial' with the skipped step recorded as
 *     'skipped' and the rest 'completed'. (session_runner.spec covers the
 *     all-completed path; the partial path is the realistic "we ran out of
 *     time and dropped a pose" case.)
 * (b) PAUSE a timed hold → the countdown freezes (a student pausing to
 *     reset their mat), the control flips to Resume, and resuming carries the
 *     session to a clean finish.
 *
 * Plans are seeded directly (service role) so each test gets the exact step
 * shape it needs; unique titles per run so the shared seed DB never collides.
 */

type ItemSeed = {
	position: number;
	movement_name: string;
	kind: 'hold' | 'reps' | 'flow';
	duration_s?: number | null;
	reps?: number | null;
};

type WorkoutRow = { id: string; title: string | null; metadata: Record<string, unknown> };

test.describe('/sessions/[id] — follow-along skip + pause', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];
	const createdWorkoutIds: string[] = [];

	async function seedPlan(discipline: string, items: ItemSeed[]): Promise<{ id: string; title: string }> {
		const admin = getAdminClient();
		const title = `e2e-skippause ${discipline} ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
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
				per_side: false
			}))
		);
		return { id: planId, title };
	}

	async function findWorkout(planId: string): Promise<WorkoutRow | undefined> {
		const admin = getAdminClient();
		const { data } = await admin
			.from('gym_workouts')
			.select('id, title, metadata')
			.eq('user_id', USER_A.id);
		const match = ((data ?? []) as WorkoutRow[]).find((w) => w.metadata?.session_plan_id === planId);
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

	test('skipping a step logs session_adherence = partial with a skipped result', async ({
		page
	}) => {
		const discipline = 'Vinyasa';
		// Three reps steps (no timer) so the sequence is deterministic — every
		// advance is a tap, never a race against a countdown.
		const { id: planId, title } = await seedPlan(discipline, [
			{ position: 0, movement_name: 'Warrior II', kind: 'reps', reps: 8 },
			{ position: 1, movement_name: 'Triangle', kind: 'reps', reps: 8 },
			{ position: 2, movement_name: 'Tree', kind: 'reps', reps: 8 }
		]);

		const runner = await start(page, planId, title);
		const band = runner.getByTestId('session-execution-band');

		// Skip the first pose, then complete the remaining two.
		await expect(band.getByTestId('session-step-name')).toHaveText('Warrior II');
		await band.getByTestId('session-skip').click();
		await expect(band.getByTestId('session-step-name')).toHaveText('Triangle');
		await band.getByTestId('session-done').click();
		await expect(band.getByTestId('session-step-name')).toHaveText('Tree');
		await band.getByTestId('session-done').click();

		await expect(runner).toBeHidden({ timeout: 10_000 });
		await expect(page.getByText('Session saved.')).toBeVisible({ timeout: 10_000 });

		await expect.poll(async () => !!(await findWorkout(planId)), { timeout: 10_000 }).toBe(true);
		const workout = (await findWorkout(planId))!;

		expect(workout.metadata.session_plan_id).toBe(planId);
		// One of three steps was skipped → the session is partial, not completed.
		expect(workout.metadata.session_adherence).toBe('partial');

		const results = workout.metadata.session_step_results as Array<{ status: string }>;
		expect(results.filter((r) => r.status === 'skipped').length).toBe(1);
		expect(results.filter((r) => r.status === 'completed').length).toBe(2);
	});

	test('pausing a timed hold freezes the countdown; resume finishes the session', async ({
		page
	}) => {
		const discipline = 'Restorative';
		// A single long hold so there's room to pause without racing the clock.
		const { id: planId, title } = await seedPlan(discipline, [
			{ position: 0, movement_name: 'Savasana', kind: 'hold', duration_s: 12 }
		]);

		const runner = await start(page, planId, title);
		const band = runner.getByTestId('session-execution-band');
		const remaining = band.getByTestId('session-remaining');
		await expect(remaining).toBeVisible();

		// Pause — the control flips to Resume and the countdown stops ticking.
		const pause = runner.getByTestId('session-pause');
		await expect(pause).toHaveText('Pause');
		await pause.click();
		await expect(pause).toHaveText('Resume');

		const frozen = await remaining.textContent();
		await page.waitForTimeout(1_500);
		await expect(remaining).toHaveText(frozen ?? '', { timeout: 2_000 });

		// Resume — the countdown runs out and the session logs cleanly.
		await pause.click();
		await expect(pause).toHaveText('Pause');
		await expect(runner).toBeHidden({ timeout: 15_000 });
		await expect(page.getByText('Session saved.')).toBeVisible({ timeout: 10_000 });
	});
});
