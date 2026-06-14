import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session planner — depth coverage for the genuinely-uncovered corners of the
 * yoga/pilates planner + follow-along player that the existing specs leave open:
 *
 *  - session-plan.spec.ts      → build a flat plan, attach to a class event
 *  - session_runner.spec.ts    → runner mount / timed / reps / per-side names /
 *                                all-completed adherence / abandon
 *  - runner-skip-pause.spec.ts → skip→partial adherence, pause→freeze
 *  - plan-edit-start.spec.ts   → edit round-trip, start-from-event
 *  - movement-autocomplete.spec.ts, club-template*.spec.ts
 *  - ../share/session.spec.ts  → the anon /share/session/[id] view + 404
 *
 * What none of them touch (and this file does):
 *  1. A MULTI-BLOCK plan — items expand in block-then-position order via
 *     expandSessionSteps; the detail sequence list reflects that ordering
 *     across blocks, not just the per-side split inside one flat list.
 *  2. The editor writing the `equipment` text + `is_public` toggle (every
 *     other spec seeds those columns with the service role — the editor's
 *     own write path for them is untested).
 *  3. Delete HAPPY path — confirm → leaves /sessions → the row is gone. Only
 *     the *failed* delete (stays put + error toast) is covered today.
 *  4. A per_side step producing TWO `session_step_results` (left + right) in
 *     the logged gym_workout metadata — the runner spec asserts the L/R step
 *     *names* on screen but never that the persisted results carry both sides.
 *  5. The owner `session-copy-share-link` affordance auto-flipping a private
 *     plan public before copying (the anon share view is covered; the owner
 *     publish-on-copy seam is not).
 *
 * Plans are seeded directly (service role) where the test exercises the runner
 * or the read view; the editor tests drive the UI so the write path is the
 * thing under test. Unique titles per run so the shared seed DB never collides.
 */

test.describe('/sessions — planner depth', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];
	const createdPlanTitles: string[] = [];
	const createdWorkoutIds: string[] = [];

	async function findWorkout(
		planId: string
	): Promise<{ id: string; title: string | null; metadata: Record<string, unknown> } | undefined> {
		const admin = getAdminClient();
		const { data } = await admin
			.from('gym_workouts')
			.select('id, title, metadata')
			.eq('user_id', USER_A.id);
		const match = (
			(data ?? []) as { id: string; title: string | null; metadata: Record<string, unknown> }[]
		).find((w) => w.metadata?.session_plan_id === planId);
		if (match) createdWorkoutIds.push(match.id);
		return match;
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
		for (const title of createdPlanTitles.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('title', title);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a multi-block plan expands block-then-position in the detail sequence', async ({
		page
	}) => {
		// Two blocks deliberately seeded out of insertion order (Cool-down at
		// position 1, Warm-up at position 0) with an item in each plus one
		// blockless item, to prove the detail list orders by:
		//   blocks ascending by position → items ascending by position →
		//   blockless items last.
		const admin = getAdminClient();
		const title = `e2e-multiblock ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: planRow, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'Vinyasa' })
			.select('id')
			.single();
		if (error) throw error;
		const planId = (planRow as { id: string }).id;
		createdPlanIds.push(planId);

		// Insert the "Cool-down" block FIRST (position 1) and "Warm-up" SECOND
		// (position 0) so a naive insertion-order render would put Cool-down
		// ahead of Warm-up — only position-sorting yields the right sequence.
		const { data: blockRows, error: blockErr } = await admin
			.from('session_plan_blocks')
			.insert([
				{ plan_id: planId, position: 1, name: 'Cool-down' },
				{ plan_id: planId, position: 0, name: 'Warm-up' }
			])
			.select('id, position');
		if (blockErr) throw blockErr;
		const blockByPos = new Map(
			(blockRows as { id: string; position: number }[]).map((b) => [b.position, b.id])
		);
		const warmupId = blockByPos.get(0)!;
		const cooldownId = blockByPos.get(1)!;

		// Within Warm-up, two items also seeded out of order (position 1 before 0).
		await admin.from('session_plan_items').insert([
			{
				plan_id: planId,
				block_id: cooldownId,
				position: 0,
				movement_name: 'Savasana',
				kind: 'hold',
				duration_s: 60,
				per_side: false
			},
			{
				plan_id: planId,
				block_id: warmupId,
				position: 1,
				movement_name: 'Sun Salute',
				kind: 'flow',
				duration_s: 30,
				per_side: false
			},
			{
				plan_id: planId,
				block_id: warmupId,
				position: 0,
				movement_name: 'Cat Cow',
				kind: 'reps',
				reps: 10,
				per_side: false
			},
			{
				plan_id: planId,
				block_id: null,
				position: 0,
				movement_name: 'Closing Breath',
				kind: 'hold',
				duration_s: 20,
				per_side: false
			}
		]);

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const steps = page.getByTestId('session-steps').locator('li');
		await expect(steps).toHaveCount(4);
		// Expected order: Warm-up(pos0 Cat Cow, pos1 Sun Salute) →
		// Cool-down(pos0 Savasana) → blockless(Closing Breath) last.
		await expect(steps.nth(0)).toContainText('Cat Cow');
		await expect(steps.nth(1)).toContainText('Sun Salute');
		await expect(steps.nth(2)).toContainText('Savasana');
		await expect(steps.nth(3)).toContainText('Closing Breath');
	});

	test('the editor persists the equipment text and the public toggle', async ({ page }) => {
		const stamp = Date.now();
		const title = `e2e-equip-public ${stamp}`;
		createdPlanTitles.push(title);

		await page.goto('/sessions');
		await page.getByRole('button', { name: 'New session' }).click();
		const modal = page.locator('.modal', { hasText: 'New session' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel('Title').fill(title);
		await modal.getByLabel('Equipment').fill('Reformer');
		// The "Make public" toggle is off by default — flip it on.
		await modal.getByText('Make public').click();

		const card = modal.locator('.item-card').nth(0);
		await card.getByLabel('Movement', { exact: true }).fill('Footwork');
		await card.getByLabel('Seconds').fill('40');

		await modal.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		// Detail header surfaces the equipment + a Public visibility chip.
		await expect(page.getByText('Reformer')).toBeVisible();
		await expect(page.locator('.visibility-chip')).toHaveText(/Public/i);

		// And both round-tripped to the row.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('session_plans')
			.select('equipment, is_public')
			.eq('title', title)
			.single();
		expect(row?.equipment).toBe('Reformer');
		expect(row?.is_public).toBe(true);
	});

	test('deleting a plan leaves /sessions and removes the row', async ({ page }) => {
		const admin = getAdminClient();
		const title = `e2e-delete ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: ins, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'Pilates' })
			.select('id')
			.single();
		if (error) throw error;
		const planId = (ins as { id: string }).id;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert({
			plan_id: planId,
			position: 0,
			movement_name: 'The Hundred',
			kind: 'reps',
			reps: 100,
			per_side: false
		});

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		// Confirm the delete. The detail page's delete dialog shares the "Delete"
		// label with the header button, so scope the confirm to the dialog.
		await page.getByRole('button', { name: 'Delete' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete this session plan?' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Delete' }).click();

		// Navigated back to the list, and the deleted plan is no longer listed.
		await page.waitForURL(/\/sessions$/, { timeout: 10_000 });
		await expect(page.getByRole('link', { name: title })).toHaveCount(0);

		// The row (and its cascaded items) are gone from the DB.
		const { data: after } = await admin
			.from('session_plans')
			.select('id')
			.eq('id', planId)
			.maybeSingle();
		expect(after).toBeNull();
	});

	test('a per-side step logs two step results (left + right) in the metadata', async ({
		page
	}) => {
		const discipline = 'Mobility';
		const admin = getAdminClient();
		const title = `e2e-perside-meta ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: planRow, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline })
			.select('id')
			.single();
		if (error) throw error;
		const planId = (planRow as { id: string }).id;
		createdPlanIds.push(planId);

		// A single per-side reps item → expands to exactly two steps (L, R), each
		// advanced by a Done tap with no countdown race. Finishing both completes
		// the session and logs the gym_workout.
		await admin.from('session_plan_items').insert({
			plan_id: planId,
			position: 0,
			movement_name: 'Pigeon',
			kind: 'reps',
			reps: 12,
			per_side: true
		});

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('session-start').click();
		const band = page.getByTestId('session-runner').getByTestId('session-execution-band');

		await expect(band.getByTestId('session-step-name')).toHaveText('Pigeon (Left)');
		await band.getByTestId('session-done').click();
		await expect(band.getByTestId('session-step-name')).toHaveText('Pigeon (Right)');
		await band.getByTestId('session-done').click();

		await expect(page.getByTestId('session-runner')).toBeHidden({ timeout: 10_000 });
		await expect(page.getByText('Session saved.')).toBeVisible({ timeout: 10_000 });

		await expect.poll(async () => !!(await findWorkout(planId)), { timeout: 10_000 }).toBe(true);
		const workout = (await findWorkout(planId))!;

		expect(workout.metadata.session_plan_id).toBe(planId);
		expect(workout.metadata.session_adherence).toBe('completed');

		const results = workout.metadata.session_step_results as Array<{
			item_id: string;
			side?: string;
			status: string;
		}>;
		// One per_side item → exactly two persisted results, one per side, both
		// completed, both carrying the same item_id.
		expect(results.length).toBe(2);
		expect(results.map((r) => r.side).sort()).toEqual(['left', 'right']);
		expect(results.every((r) => r.status === 'completed')).toBe(true);
		expect(new Set(results.map((r) => r.item_id)).size).toBe(1);
	});

	test('copy-share-link flips a private plan public before copying', async ({ page, context }) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);

		const admin = getAdminClient();
		const title = `e2e-copyshare ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: ins, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'Barre', is_public: false })
			.select('id')
			.single();
		if (error) throw error;
		const planId = (ins as { id: string }).id;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert({
			plan_id: planId,
			position: 0,
			movement_name: 'Plié',
			kind: 'reps',
			reps: 16,
			per_side: false
		});

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// Starts private.
		await expect(page.locator('.visibility-chip')).toHaveText(/Private/i);

		await page.getByTestId('session-copy-share-link').click();
		await expect(page.getByText('Share link copied.')).toBeVisible({ timeout: 10_000 });

		// The chip flips to Public in place (the affordance auto-publishes a
		// private plan so the copied link doesn't 404 for everyone else).
		await expect(page.locator('.visibility-chip')).toHaveText(/Public/i);

		// The clipboard carries the share URL.
		const clip = await page.evaluate(() => navigator.clipboard.readText());
		expect(clip).toContain(`/share/session/${planId}`);

		// And the plan is now public in the DB so the share link resolves.
		const { data: row } = await admin
			.from('session_plans')
			.select('is_public')
			.eq('id', planId)
			.single();
		expect(row?.is_public).toBe(true);
	});
});
