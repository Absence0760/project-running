import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/session/[routineId] — the draft / resume path (decisions.md § 483,
 * brought to web by § 493).
 *
 * Web is the canonical feature surface, but until now a refresh mid-session
 * lost the runner outright: the sets were never persisted before Finish. The
 * runner now durably saves onto a single `gym_workouts` draft row carrying the
 * `gym_session_draft` metadata snapshot, so a force-kill (refresh, tab close)
 * is as resumable as a graceful leave. These cover both entry points — a
 * reload of the session URL, and the /gym resume card — plus the three-way
 * leave prompt that replaced the binary Abandon confirm.
 */

type SeededRoutine = { id: string; title: string; press: string; row: string };

async function seedRoutine(stamp: number): Promise<SeededRoutine> {
	const admin = getAdminClient();
	const title = `E2E Draft ${stamp}`;
	const press = `E2E Draft Press ${stamp}`;
	const row = `E2E Draft Row ${stamp}`;

	const { data: routine, error } = await admin
		.from('gym_routines')
		.insert({ author_id: USER_A.id, title, exercise_count: 2 })
		.select('id')
		.single();
	if (error || !routine) throw error ?? new Error('seed routine failed');
	const routineId = routine.id as string;

	const { data: pressEx } = await admin
		.from('gym_routine_exercises')
		.insert({
			routine_id: routineId,
			exercise_name: press,
			exercise_key: press.trim().toLowerCase(),
			position: 0,
		})
		.select('id')
		.single();
	const { data: rowEx } = await admin
		.from('gym_routine_exercises')
		.insert({
			routine_id: routineId,
			exercise_name: row,
			exercise_key: row.trim().toLowerCase(),
			position: 1,
		})
		.select('id')
		.single();

	// No rest on any set: the rest timer is exercised by gym_session.spec.ts and
	// only gets in the way of the draft assertions here.
	await admin.from('gym_routine_sets').insert([
		{ routine_exercise_id: pressEx!.id, set_index: 0, target_reps_min: 5, target_weight_kg: 60 },
		{ routine_exercise_id: pressEx!.id, set_index: 1, target_reps_min: 5, target_weight_kg: 60 },
		{ routine_exercise_id: rowEx!.id, set_index: 0, target_reps_min: 8, target_weight_kg: 40 },
	]);

	return { id: routineId, title, press, row };
}

async function cleanup(r: SeededRoutine): Promise<void> {
	const admin = getAdminClient();
	await admin.from('gym_workouts').delete().eq('user_id', USER_A.id).eq('title', r.title);
	await admin.from('gym_routines').delete().eq('id', r.id);
}

async function draftRows(title: string) {
	const admin = getAdminClient();
	const { data } = await admin
		.from('gym_workouts')
		.select('id, metadata, duration_s')
		.eq('user_id', USER_A.id)
		.eq('title', title);
	return data ?? [];
}

/// The runner writes durably on a 10 s tick, so the draft appears a beat after
/// the set does. Poll rather than sleep a fixed span.
async function waitForDraft(title: string): Promise<{ id: string; metadata: unknown }> {
	for (let i = 0; i < 30; i++) {
		const rows = await draftRows(title);
		const withDraft = rows.find(
			(r) => (r.metadata as Record<string, unknown> | null)?.gym_session_draft != null,
		);
		if (withDraft) return withDraft as { id: string; metadata: unknown };
		await new Promise((resolve) => setTimeout(resolve, 1000));
	}
	throw new Error(`no gym_session_draft row appeared for "${title}"`);
}

async function startSession(page: Page, routineId: string): Promise<void> {
	await page.goto(`/gym/session/${routineId}`);
	await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 15_000 });
	await expect(page.getByTestId('gym-exec-band')).toBeVisible();
}

test.describe('/gym/session — draft and resume', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a refresh mid-session resumes where the runner left off', async ({ page }) => {
		// The durable save is on a 10 s tick, so this one waits for real time.
		test.setTimeout(90_000);
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			const draft = await waitForDraft(r.title);
			const snapshot = (draft.metadata as Record<string, unknown>).gym_session_draft as {
				results: Array<{ step_index: number; status: string; reps: number | null }>;
			};
			// Only the steps already left behind — the step in hand carries no
			// outcome, or the resume would land a step ahead of the runner.
			expect(snapshot.results).toHaveLength(1);
			expect(snapshot.results[0]).toMatchObject({ step_index: 0, status: 'completed', reps: 5 });

			await page.reload();
			await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');
			await expect(page.getByTestId('gym-exec-band')).toContainText(r.press);

			// Finishing from the resumed runner replaces the draft in place: one
			// row, no fork, and the marker is gone because it is no longer in flight.
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-session-finish-save').click();
			await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

			const rows = await draftRows(r.title);
			expect(rows).toHaveLength(1);
			expect(rows[0].id).toBe(draft.id);
			const finished = rows[0].metadata as Record<string, unknown>;
			expect(finished.gym_session_draft).toBeUndefined();
			expect(finished.gym_adherence).toBe('completed');
		} finally {
			await cleanup(r);
		}
	});

	test('leaving keeps a draft the gym page offers to resume', async ({ page }) => {
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			await page.getByTestId('gym-session-discard').click();
			await expect(page.getByTestId('gym-leave-dialog')).toBeVisible({ timeout: 10_000 });
			await page.getByTestId('gym-leave-keep-draft').click();
			await page.waitForURL(new RegExp(`/gym/routines/${r.id}$`), { timeout: 15_000 });

			await page.goto('/gym');
			const card = page.getByTestId('gym-session-draft-card');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(card).toContainText(r.title);

			await page.getByTestId('gym-draft-resume').click();
			await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');
		} finally {
			await cleanup(r);
		}
	});

	test('save as is keeps the workout and clears the draft marker', async ({ page }) => {
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-session-discard').click();
			await page.getByTestId('gym-leave-keep-draft').click();
			await page.waitForURL(new RegExp(`/gym/routines/${r.id}$`), { timeout: 15_000 });

			await page.goto('/gym');
			await expect(page.getByTestId('gym-session-draft-card')).toBeVisible({ timeout: 15_000 });
			await page.getByTestId('gym-draft-save-as-is').click();
			await expect(page.getByTestId('gym-session-draft-card')).toHaveCount(0, { timeout: 15_000 });

			const rows = await draftRows(r.title);
			expect(rows).toHaveLength(1);
			const metadata = rows[0].metadata as Record<string, unknown>;
			// The routine link is real and survives; no adherence verdict is
			// claimed, because the session never ran to completion.
			expect(metadata.routine_id).toBe(r.id);
			expect(metadata.gym_session_draft).toBeUndefined();
			expect(metadata.gym_adherence).toBeUndefined();
		} finally {
			await cleanup(r);
		}
	});

	test('discarding the draft from the gym card deletes the row', async ({ page }) => {
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-session-discard').click();
			await page.getByTestId('gym-leave-keep-draft').click();
			await page.waitForURL(new RegExp(`/gym/routines/${r.id}$`), { timeout: 15_000 });

			await page.goto('/gym');
			await expect(page.getByTestId('gym-session-draft-card')).toBeVisible({ timeout: 15_000 });
			await page.getByTestId('gym-draft-discard').click();
			const dialog = page.getByTestId('gym-draft-discard-dialog');
			await expect(dialog).toBeVisible({ timeout: 10_000 });
			await dialog.getByRole('button', { name: 'Discard', exact: true }).click();

			await expect(page.getByTestId('gym-session-draft-card')).toHaveCount(0, { timeout: 15_000 });
			expect(await draftRows(r.title)).toHaveLength(0);
		} finally {
			await cleanup(r);
		}
	});

	test('navigating away mid-session prompts before the runner is lost', async ({ page }) => {
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			await page.getByRole('link', { name: /Back to routines/ }).click();
			const dialog = page.getByTestId('gym-leave-dialog');
			await expect(dialog).toBeVisible({ timeout: 10_000 });

			// Keep going stays put with the runner exactly where it was.
			await dialog.getByRole('button', { name: 'Keep going' }).click();
			await expect(dialog).toHaveCount(0);
			await expect(page).toHaveURL(new RegExp(`/gym/session/${r.id}`));
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');
		} finally {
			await cleanup(r);
		}
	});

	test('a failed keep-draft save keeps the runner put instead of losing the session', async ({
		page
	}) => {
		// leaveKeepingDraft awaited a save whose failure was swallowed to
		// console.error, then departed regardless. Offline — or before the
		// first 10 s autosave tick has landed — the runner asked to KEEP the
		// draft and the entire session vanished with no feedback.
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);
			await page.getByTestId('gym-step-complete').click();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			// Fail every gym_workouts write so the draft cannot land.
			await page.route('**/rest/v1/gym_workouts*', (route) =>
				route.request().method() === 'GET'
					? route.continue()
					: route.fulfill({ status: 500, body: 'boom' })
			);

			await page.getByTestId('gym-session-discard').click();
			await expect(page.getByTestId('gym-leave-dialog')).toBeVisible({ timeout: 10_000 });
			await page.getByTestId('gym-leave-keep-draft').click();

			// Still on the session, with the failure stated and the logged set
			// intact — not navigated away with the work thrown out.
			await expect(page.getByTestId('gym-leave-save-failed')).toBeVisible({
				timeout: 15_000
			});
			await expect(page).toHaveURL(new RegExp(`/gym/session/${r.id}`));
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			// Recovering the connection and retrying departs as it should.
			await page.unroute('**/rest/v1/gym_workouts*');
			await page.getByTestId('gym-leave-keep-draft').click();
			await page.waitForURL(new RegExp(`/gym/routines/${r.id}$`), { timeout: 15_000 });

			await page.goto('/gym');
			await expect(page.getByTestId('gym-session-draft-card')).toBeVisible({
				timeout: 15_000
			});
		} finally {
			await cleanup(r);
		}
	});
});
