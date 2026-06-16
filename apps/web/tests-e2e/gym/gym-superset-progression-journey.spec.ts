import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Gym P2 supersets + P4 progression journey — the gym-programming engine's
 * THREE-MEMBER superset chain authored end-to-end, run through the guided
 * session runner with a SKIPPED set, and yielding a double-progression
 * rep-climb suggestion. On a CLEAN, fully-owned canvas (one ephemeral saga
 * user with zero gym history) so every grouping / round-robin / adherence /
 * progression assertion is unambiguous.
 *
 * What the two existing long-form gym specs already own (and this one does NOT
 * re-cover):
 *   - gym-routine-runner-journey.spec.ts: a TWO-exercise superset (ONE flag →
 *     one A,B pair), all sets HIT → a `completed` verdict, and a LINEAR
 *     `increase_weight` ("Add load next time") next-target chip.
 *   - routine-progression-journey.spec.ts: the save-as-routine + repeat-last
 *     "vs last time" / since-first est.-1RM deltas (no routine builder, no
 *     guided runner, no adherence/superset).
 *
 * This journey owns the genuinely-UNCOVERED gym slices:
 *   1. assignSupersetGroups' "a RUN of flagged exercises forms one LONGER
 *      group" branch — TWO adjacent superset flags bracket THREE exercises
 *      (A→B→C) into ONE shared group, ordered 0/1/2 — distinct from the
 *      single A,B pair the runner journey authors. A FOURTH exercise is left
 *      standalone (no flag), so the both-null/both-set CHECK
 *      (gym_routine_exercises_superset_chk) is exercised on both arms in one
 *      routine: three rows with (group, order) both-set, one with both-null.
 *   2. expandRoutineSteps' THREE-member round-robin: A1,B1,C1,A2,B2,C2 then the
 *      standalone D's sets — the interleave the runner journey's two-member
 *      pair can't show (it never proves C lands between B and A2).
 *   3. A PARTIAL adherence verdict via SKIPPING working sets — the runner
 *      journey only logs all-hit → `completed`. Here TWO of the five planned
 *      sets are skipped so 3/5 = 60% < the 80% completed threshold → the
 *      verdict is `partial` (one skip would be exactly 4/5 = 80% and still
 *      `completed`, so it has to be two), the review shows two `missed` status
 *      pills, and metadata.gym_adherence === 'partial'.
 *   4. A DOUBLE_PROGRESSION rep-climb next-target chip (`increase_reps` /
 *      "Add reps next time" + an "8→9" repClimb delta) — the main lift logs
 *      8 reps inside an 8–12 range, below the top, so nextPrescription climbs
 *      REPS not load. The runner journey only proves the linear add-load chip.
 *
 * Weight is entered in the editor's display unit; the saga user defaults to
 * km/kg (createSagaUsers upserts preferred_unit 'km', weight_unit unset → kg),
 * so '100' stores 100 kg canonical and the band renders the kg target. Rests
 * are left at 0 so the runner steps directly (the rest-timer interpose is
 * covered by gym_session.spec.ts). Gym workout creation is not rate-limited.
 *
 * A unique stamped routine title + exercise names keep every assertion + the
 * cleanup lookups unambiguous against the shared seed DB. The saga user is
 * pre-consented (the GDPR banner is role="dialog" and floats over modals).
 */
test.describe('gym superset + progression journey — 3-member chain → guided run with a skip → partial adherence → double-progression rep-climb', () => {
	test('a three-exercise superset routine is authored, run with one skipped set, and suggests a rep climb', async ({
		browser,
	}) => {
		const admin = getAdminClient();
		const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const routineTitle = `e2e-ss-routine-${stamp}`;
		// Three exercises chained into one superset (A→B→C) + a fourth standalone.
		// The main lift A carries double_progression over an 8–12 rep range.
		const exA = `e2e-ss-press-${stamp}`;
		const exB = `e2e-ss-row-${stamp}`;
		const exC = `e2e-ss-curl-${stamp}`;
		const exD = `e2e-ss-squat-${stamp}`;
		const keyA = exA.trim().toLowerCase();

		let users: SagaUser[] = [];
		let routineId: string | null = null;
		const workoutIds: string[] = [];

		// Fill one block (name + first set's reps + optional weight) inside the
		// RoutineEditor, scoped to the block at index `ei` so a later block's
		// set inputs can't shift the index. Weight is a type=number input →
		// canonical kg. A bodyweight/no-weight block passes weight = null.
		async function fillBlock(
			page: Page,
			ei: number,
			name: string,
			reps: string,
			weightKg: string | null,
		) {
			await page.getByTestId('routine-exercise-name').nth(ei).fill(name);
			const block = page.locator('.exercise-block').nth(ei);
			await block.getByTestId('routine-set-reps').nth(0).fill(reps);
			if (weightKg != null) await block.getByTestId('routine-set-weight').nth(0).fill(weightKg);
		}

		try {
			users = await createSagaUsers(1, { displayNames: ['Superset Saga'] });
			const user = users[0];
			const ctx: BrowserContext = await browser.newContext({
				storageState: user.storageStatePath,
			});
			// Pre-accept the cookie banner so the role="dialog" GDPR banner can't
			// float over the editor modal / runner band.
			await ctx.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
				);
			});
			const page = await ctx.newPage();

			try {
				// ── 1. Author the 3-member superset chain + a standalone ─────────
				await test.step('author a 3-exercise superset (A→B→C) + a standalone D, A on double_progression 8–12', async () => {
					await page.goto('/gym/routines/new');
					await page.getByTestId('routine-title').fill(routineTitle);

					// Block 0 (A, main lift): TWO working sets @ 8 reps × 100 kg over
					// an 8–12 range, double_progression. The editor opens with ONE set;
					// the second comes from "Add set".
					const blockA = page.locator('.exercise-block').nth(0);
					await page.getByTestId('routine-exercise-name').nth(0).fill(exA);
					await blockA.getByTestId('routine-set-reps').nth(0).fill('8');
					await blockA.getByTestId('routine-set-reps-max').nth(0).fill('12');
					await blockA.getByTestId('routine-set-weight').nth(0).fill('100');
					await blockA.getByRole('button', { name: 'Add set' }).click();
					await expect(blockA.getByTestId('routine-set-reps')).toHaveCount(2);
					await blockA.getByTestId('routine-set-reps').nth(1).fill('8');
					await blockA.getByTestId('routine-set-reps-max').nth(1).fill('12');
					await blockA.getByTestId('routine-set-weight').nth(1).fill('100');
					await blockA.getByText('Advanced').click();
					await blockA.getByTestId('routine-progression').selectOption('double_progression');

					// Block 1 (B): one working set @ 10 × 60.
					await page.getByTestId('routine-add-exercise').click();
					await fillBlock(page, 1, exB, '10', '60');

					// Block 2 (C): one working set @ 12 × 30.
					await page.getByTestId('routine-add-exercise').click();
					await fillBlock(page, 2, exC, '12', '30');

					// Block 3 (D, standalone): one working set @ 5 × 80.
					await page.getByTestId('routine-add-exercise').click();
					await fillBlock(page, 3, exD, '5', '80');

					// Chain A→B and B→C into ONE superset group. The toggle on the LAST
					// block (D) is disabled (nothing follows), so D stays standalone.
					// Two adjacent flags merge into a single group of three via
					// assignSupersetGroups' "run of flagged exercises" branch.
					await page.getByTestId('routine-superset-toggle').nth(0).check();
					await page.getByTestId('routine-superset-toggle').nth(1).check();

					await page.getByTestId('routine-save').click();
					await expect(page.getByTestId('routine-exercises')).toBeVisible({ timeout: 10_000 });

					const { data: routines } = await admin
						.from('gym_routines')
						.select('id, exercise_count')
						.eq('author_id', user.id)
						.eq('title', routineTitle);
					expect(routines?.length).toBe(1);
					expect(routines![0].exercise_count).toBe(4);
					routineId = routines![0].id as string;

					// The plan persisted: A,B,C share ONE non-null superset_group with
					// orders 0/1/2; D is standalone (both null). This is the
					// gym_routine_exercises_superset_chk both-arms check, in one routine.
					const { data: exRows } = await admin
						.from('gym_routine_exercises')
						.select('exercise_name, position, superset_group, superset_order, progression')
						.eq('routine_id', routineId)
						.order('position', { ascending: true });
					expect(exRows?.length).toBe(4);
					const [a, b, c, d] = exRows!;
					// The chain: one shared group across the first three, ordered.
					expect(a.superset_group).not.toBeNull();
					expect(a.superset_group).toBe(b.superset_group);
					expect(b.superset_group).toBe(c.superset_group);
					expect(a.superset_order).toBe(0);
					expect(b.superset_order).toBe(1);
					expect(c.superset_order).toBe(2);
					// D standalone — both null (the other arm of the CHECK).
					expect(d.superset_group).toBeNull();
					expect(d.superset_order).toBeNull();
					// A carries the double-progression scheme; B/C/D none.
					expect(a.progression).toBe('double_progression');
					expect(b.progression).toBe('none');
					expect(d.progression).toBe('none');
				});

				// ── 2. The routine detail shows the superset grouping ────────────
				await test.step('the routine detail renders the superset badges for the chained three (not D)', async () => {
					await page.goto(`/gym/routines/${routineId}`);
					const exercises = page.getByTestId('routine-exercises');
					await expect(exercises).toContainText(exA, { timeout: 10_000 });
					await expect(exercises).toContainText(exD);
					// A,B,C are supersetted → three superset badges; D is standalone.
					await expect(page.getByTestId('routine-superset-badge')).toHaveCount(3);
				});

				// ── 3. Run the guided session: 3-member round-robin + two skips ──
				await test.step('the runner interleaves A1,B1,C1 then A2 then D, skipping A2 and D', async () => {
					await page.goto(`/gym/session/${routineId}`);
					await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
					const band = page.getByTestId('gym-exec-band');
					await expect(band).toBeVisible();

					// expandRoutineSteps round-robins the group of three by set-index.
					// rounds = max member set count = 2 (A has 2 sets, B & C have 1).
					// Round 0 emits A1,B1,C1; round 1 emits A2 only (B & C have no set
					// at index 1). Then the standalone D's single set. Total = 5 steps.
					// Step 1 — A1, prefilled from plan (8 reps @ 100 kg). Log it (hit).
					await expect(band).toContainText(exA);
					await expect(band).toContainText('Set 1/5');
					await expect(page.getByTestId('gym-set-reps')).toHaveValue('8');
					await expect(page.getByTestId('gym-set-weight')).toHaveValue('100');
					await page.getByTestId('gym-step-complete').click();

					// Step 2 — B (the superset partner), not A's second set.
					await expect(band).toContainText(exB);
					await expect(band).toContainText('Set 2/5');
					await expect(page.getByTestId('gym-set-reps')).toHaveValue('10');
					await page.getByTestId('gym-step-complete').click();

					// Step 3 — C, the third member of the round-robin, lands BEFORE A2.
					await expect(band).toContainText(exC);
					await expect(band).toContainText('Set 3/5');
					await expect(page.getByTestId('gym-set-reps')).toHaveValue('12');
					await page.getByTestId('gym-step-complete').click();

					// Step 4 — back to A for round 1 (A2). SKIP it (one of two skips).
					await expect(band).toContainText(exA);
					await expect(band).toContainText('Set 4/5');
					await page.getByTestId('gym-step-skip').click();

					// Step 5 — D, the standalone, emitted after the whole group drains.
					// SKIP it too: with 3/5 = 60% hit (< the 80% completed threshold)
					// the verdict lands `partial`. Skipping ONLY A2 would be 4/5 = 80%
					// → still `completed`, so two skips are required to reach partial.
					await expect(band).toContainText(exD);
					await expect(band).toContainText('Set 5/5');
					await page.getByTestId('gym-step-skip').click();

					// All steps drained → finish panel; save the session.
					await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
					await page.getByTestId('gym-session-finish-save').click();
					await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });
				});

				// ── 4. The adherence review: PARTIAL (two skipped working sets) ──
				await test.step('the detail screen shows a Partial verdict with two missed steps', async () => {
					// Do NOT hard-navigate: the runner reaches /gym/[id] via a
					// client-side goto() with the auth session already live, so the
					// onMount fetch is authenticated. A full reload would re-fire it
					// before Supabase rehydrates and RLS would render blank.
					const workoutId = new URL(page.url()).pathname.split('/').pop() as string;
					expect(workoutId).toMatch(/^[0-9a-f-]+$/);
					workoutIds.push(workoutId);

					const review = page.getByTestId('gym-workout-review');
					await expect(review).toBeVisible({ timeout: 10_000 });
					// Two of five working sets skipped → 60% hit → Partial.
					await expect(page.getByTestId('gym-review-verdict')).toHaveText('Partial');
					// The three logged sets (A1,B1,C1) are hits; the skipped A2 and D
					// are missed steps.
					await expect(review.locator('.status-hit')).toHaveCount(3);
					await expect(review.locator('.status-missed')).toHaveCount(2);

					// Backend cross-check: the workout is linked to the routine and the
					// adherence verdict is persisted as 'partial'.
					const { data: created } = await admin
						.from('gym_workouts')
						.select('id, metadata')
						.eq('id', workoutId);
					expect(created?.length).toBe(1);
					const metadata = created![0].metadata as {
						routine_id: string;
						gym_adherence: string;
						gym_step_results: Array<{ exercise_key: string; status: string }>;
					};
					expect(metadata.routine_id).toBe(routineId);
					expect(metadata.gym_adherence).toBe('partial');
					// Two step results are missed; three are hits.
					expect(metadata.gym_step_results.filter((s) => s.status === 'missed').length).toBe(2);
					expect(metadata.gym_step_results.filter((s) => s.status === 'hit').length).toBe(3);

					// The flat log holds the three PERFORMED sets only (each skip wrote
					// no gym_set): A1, B1, C1. A2 (skipped) and D (skipped) are absent.
					const { data: sets } = await admin
						.from('gym_sets')
						.select('exercise_name, reps, weight_kg')
						.eq('workout_id', workoutId);
					expect(sets?.length).toBe(3);
					const aSets = sets!.filter((s) => s.exercise_name === exA);
					expect(aSets.length).toBe(1);
					// Weight stored canonical kg (100), not lbs.
					expect(Number(aSets[0].weight_kg)).toBe(100);
					// D was skipped → no logged set for it.
					expect(sets!.filter((s) => s.exercise_name === exD).length).toBe(0);
				});

				// ── 5. The double-progression next-target: a REP CLIMB, not load ─
				await test.step('the next-target chip suggests adding reps (8→9), not load, for the main lift', async () => {
					const targets = page.getByTestId('gym-next-targets');
					await expect(targets).toBeVisible();

					// A logged 8 reps inside its 8–12 range — below the top — so
					// double_progression climbs REPS at the same load, not weight.
					const mainChip = page.getByTestId('gym-next-target').filter({ hasText: exA });
					await expect(mainChip).toBeVisible();
					await expect(mainChip).toContainText('Add reps next time');
					// The repClimb delta cites the climb off the logged top set: 8→9.
					await expect(mainChip).toContainText('8');
					await expect(mainChip).toContainText('9');
					// It must NOT be a load bump — distinct from the linear-scheme chip
					// the runner journey covers.
					await expect(mainChip).not.toContainText('Add load next time');

					// B/C/D carry no scheme → no chips for them.
					await expect(page.getByTestId('gym-next-target').filter({ hasText: exB })).toHaveCount(
						0,
					);
					await expect(page.getByTestId('gym-next-target').filter({ hasText: exD })).toHaveCount(
						0,
					);

					// Backend sanity: the bound exercise key for A is its normalised
					// name (the plan↔log binding identity).
					expect(keyA).toBe(exA.toLowerCase());
				});
			} finally {
				await ctx.close();
			}
		} finally {
			// Explicit gym teardown first (the saga delete cascades these too, but
			// an explicit wipe is robust to a saga-delete race and leaves the
			// shared seed DB clean even if deleteSagaUsers logs a warning).
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
			if (routineId) await admin.from('gym_routines').delete().eq('id', routineId);
			if (users.length > 0) await deleteSagaUsers(users);
		}
	});
});
