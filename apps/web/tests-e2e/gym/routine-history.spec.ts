import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/routines/[id] — the routine-history panel.
 *
 * Every guided session stamps `gym_workouts.metadata.routine_id` (+ the
 * adherence verdict), but nothing read it back per routine, so a lifter could
 * not see when they last ran a routine or whether they were finishing it.
 * These pin the three row classes the panel has to tell apart: a graded
 * session, an ungraded "save as is" row, and an in-flight draft that must NOT
 * count as a session performed.
 */

type Seeded = { routineId: string; title: string; workoutIds: string[] };

const DAY_MS = 86_400_000;

async function seed(stamp: number): Promise<Seeded> {
	const admin = getAdminClient();
	const title = `E2E History ${stamp}`;

	const { data: routine, error } = await admin
		.from('gym_routines')
		.insert({ author_id: USER_A.id, title, exercise_count: 1 })
		.select('id')
		.single();
	if (error || !routine) throw error ?? new Error('seed routine failed');
	const routineId = routine.id as string;

	const { data: ex } = await admin
		.from('gym_routine_exercises')
		.insert({
			routine_id: routineId,
			exercise_name: `E2E History Press ${stamp}`,
			exercise_key: `e2e history press ${stamp}`,
			position: 0,
		})
		.select('id')
		.single();
	await admin
		.from('gym_routine_sets')
		.insert({ routine_exercise_id: ex!.id, set_index: 0, target_reps_min: 5, target_weight_kg: 60 });

	const now = Date.now();
	const { data: workouts, error: wErr } = await admin
		.from('gym_workouts')
		.insert([
			{
				user_id: USER_A.id,
				title: `${title} completed`,
				started_at: new Date(now - 2 * DAY_MS).toISOString(),
				duration_s: 2400,
				metadata: { routine_id: routineId, gym_adherence: 'completed' },
			},
			{
				user_id: USER_A.id,
				title: `${title} partial`,
				started_at: new Date(now - 9 * DAY_MS).toISOString(),
				duration_s: 1800,
				metadata: { routine_id: routineId, gym_adherence: 'partial' },
			},
			{
				user_id: USER_A.id,
				title: `${title} saved as is`,
				started_at: new Date(now - 16 * DAY_MS).toISOString(),
				duration_s: 900,
				metadata: { routine_id: routineId },
			},
			{
				user_id: USER_A.id,
				title: `${title} in flight`,
				started_at: new Date(now - 1 * 3600_000).toISOString(),
				duration_s: 300,
				metadata: {
					routine_id: routineId,
					gym_session_draft: { saved_at: new Date(now).toISOString(), results: [] },
				},
			},
		])
		.select('id');
	if (wErr) throw wErr;

	return { routineId, title, workoutIds: (workouts ?? []).map((w) => w.id as string) };
}

async function cleanup(s: Seeded): Promise<void> {
	const admin = getAdminClient();
	for (const id of s.workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
	await admin.from('gym_routines').delete().eq('id', s.routineId);
}

test.describe('/gym/routines/[id] — routine history', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('counts performed sessions, excludes the in-flight draft, and grades honestly', async ({
		page,
	}) => {
		const s = await seed(Date.now());
		try {
			await page.goto(`/gym/routines/${s.routineId}`);
			const panel = page.getByTestId('routine-history');
			await expect(panel).toBeVisible({ timeout: 15_000 });

			// Three performed sessions — the draft row carries routine_id but is
			// not a session, so it must not inflate the count or the "last run".
			await expect(page.getByTestId('routine-history-count')).toHaveText('3 sessions');
			await expect(page.getByTestId('routine-history-last')).toHaveText('Done 2 days ago');

			// The save-as-is row claims no verdict, so it is out of the
			// denominator rather than counted as a failure.
			await expect(page.getByTestId('routine-history-rate')).toHaveText('1 of 2 completed');

			await expect(panel).toContainText('Completed');
			await expect(panel).toContainText('Partial');
			await expect(panel).toContainText('Not graded');
			await expect(panel).not.toContainText('in flight');

			// Each row is a way back into the session it summarises.
			await panel.getByRole('link').first().click();
			await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });
		} finally {
			await cleanup(s);
		}
	});

	test('the count is the complete total while the list stays a bounded page', async ({ page }) => {
		// The panel lists five rows but claims a session COUNT; before the
		// gym_routine_history aggregate that count came from the rows the client
		// happened to read, so a lifter past the window saw a capped figure.
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E History Paged ${stamp}`;
		const { data: routine } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title, exercise_count: 0 })
			.select('id')
			.single();
		const routineId = routine!.id as string;
		const { data: workouts } = await admin
			.from('gym_workouts')
			.insert(
				Array.from({ length: 7 }, (_, i) => ({
					user_id: USER_A.id,
					title: `${title} ${i}`,
					started_at: new Date(stamp - (i + 1) * DAY_MS).toISOString(),
					duration_s: 1200,
					metadata: { routine_id: routineId, gym_adherence: 'completed' },
				})),
			)
			.select('id');
		try {
			await page.goto(`/gym/routines/${routineId}`);
			const panel = page.getByTestId('routine-history');
			await expect(panel).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('routine-history-count')).toHaveText('7 sessions');
			await expect(panel.getByRole('link')).toHaveCount(5);
		} finally {
			for (const w of workouts ?? []) await admin.from('gym_workouts').delete().eq('id', w.id as string);
			await admin.from('gym_routines').delete().eq('id', routineId);
		}
	});

	test('a routine that has never been run shows no history panel', async ({ page }) => {
		const admin = getAdminClient();
		const title = `E2E History Unrun ${Date.now()}`;
		const { data: routine } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title, exercise_count: 0 })
			.select('id')
			.single();
		try {
			await page.goto(`/gym/routines/${routine!.id}`);
			await expect(page.getByTestId('routine-start')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('routine-history')).toHaveCount(0);
		} finally {
			await admin.from('gym_routines').delete().eq('id', routine!.id);
		}
	});
});
