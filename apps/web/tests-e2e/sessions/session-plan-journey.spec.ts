import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Session-plan journey — the full cradle-to-grave life of a single yoga/pilates
 * session plan, walked through every surface it touches across TWO users. Heavier
 * than session-plan.spec.ts's build→attach→read round-trip and
 * session_runner.spec.ts's runner-mechanics coverage because it threads ONE plan
 * id through author → publish → attach-to-class-event → a SECOND user follows the
 * attached session to completion → that follower's gym history gains a real
 * gym_workout — exercising the seams (the class→session attach point and the
 * session→gym log seam, lib/social/event_gym_template.ts#workoutDraftFromSession)
 * rather than any single screen.
 *
 *   1. USER_A (owner/admin of Richmond Run Club) authors a session plan via the
 *      /sessions editor — a hold, a per-side hold, and a reps movement — with a
 *      UNIQUE discipline string. The discipline is load-bearing twice over: it is
 *      what workoutDraftFromSession picks as the logged gym_workout's TITLE
 *      (discipline ?? planTitle), so the follower's /gym row is addressable by it,
 *      and it keeps assertions + cleanup from colliding in the shared seed DB.
 *   2. USER_A makes the plan PUBLIC. This is the RLS hinge for step 4: the
 *      follower (morgan) is NOT a Richmond member, and the only session_plans
 *      SELECT policies are author / public / club-member (migration 20270103_001).
 *      A class event attachment grants no read on the plan itself — so without
 *      is_public=true, fetchSessionPlan returns null for the follower and the
 *      runner can't mount.
 *   3. USER_A attaches the plan to a Richmond `class` event (the only event
 *      category that surfaces a session sequence). Richmond is a public club, so
 *      "events readable with their club" (20260416_001) lets the non-member
 *      follower see the event + its attached sequence read-only.
 *   4. USER_C_PRO (second browser context) opens the public club event, follows
 *      the attached-sequence link to /sessions/[id], and runs the follow-along
 *      player (SessionRunner) to a clean finish. The runner logs against whoever
 *      is SIGNED IN (createGymWorkout → auth.user) — so the workout lands in
 *      MORGAN's history, not the author's.
 *   5. The logged gym_workout shows up on MORGAN's /gym list (row title is the
 *      plan discipline) and the backend row carries user_id = morgan,
 *      metadata.session_plan_id = the plan, and session_adherence = 'completed'.
 *
 * Why a per-side hold in step 1: it makes the expansion non-trivial — a single
 * per_side item becomes a Left then a Right step in the runner — so the journey
 * exercises expandSessionSteps end to end, not just a flat list.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('session plan journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('author → publish → attach to class event → second user follows → logs a gym_workout', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();
		const planTitle = uniqueText('e2e-session-journey');
		// Unique discipline: becomes the logged gym_workout's title (the follower
		// asserts their /gym row by it) AND scopes the workout lookup below.
		const discipline = uniqueText('e2e-journey-vinyasa');
		const eventTitle = uniqueText('e2e-journey-class');

		// Captured from the create round-trip so every later surface (the attach,
		// the follower's runner, the backend cross-checks) addresses the SAME plan;
		// also drives best-effort teardown.
		let planId = '';
		let eventId = '';
		let loggedWorkoutId = '';

		try {
			// ── 1. USER_A authors the plan via the /sessions editor ─────────────
			await test.step('USER_A authors a 3-movement session plan', async () => {
				await page.goto('/sessions');
				await page.getByRole('button', { name: 'New session' }).click();
				const modal = page.locator('.modal', { hasText: 'New session' });
				await expect(modal).toBeVisible({ timeout: 5_000 });

				await modal.getByLabel('Title').fill(planTitle);
				await modal.getByLabel('Discipline').fill(discipline);

				const cards = modal.locator('.item-card');
				// Movement 0 (default row): a plain hold.
				await cards.nth(0).getByLabel('Movement', { exact: true }).fill('Downward Dog');
				await cards.nth(0).getByLabel('Seconds').fill('30');

				// Movement 1: a per-side hold — expands to Left + Right in the runner.
				await modal.getByRole('button', { name: 'Add movement' }).click();
				await cards.nth(1).getByLabel('Movement', { exact: true }).fill('Low Lunge');
				await cards.nth(1).getByLabel('Seconds').fill('30');
				await cards.nth(1).getByLabel('Per side (left & right)').check();

				// Movement 2: a reps movement (no countdown — advances on Done).
				await modal.getByRole('button', { name: 'Add movement' }).click();
				await cards.nth(2).getByLabel('Type').selectOption('reps');
				await cards.nth(2).getByLabel('Movement', { exact: true }).fill('The Hundred');
				await cards.nth(2).getByLabel('Reps', { exact: true }).fill('100');

				await modal.getByRole('button', { name: 'Save', exact: true }).click();

				// Navigated to the read view; the per-side hold expanded to L/R:
				// Downward Dog + Low Lunge (Left) + Low Lunge (Right) + The Hundred.
				await expect(page.getByRole('heading', { name: planTitle })).toBeVisible({
					timeout: 10_000
				});
				await expect(page.getByTestId('session-steps').locator('li')).toHaveCount(4);

				const { data: planRow } = await admin
					.from('session_plans')
					.select('id, author_id, discipline')
					.eq('title', planTitle)
					.single();
				planId = planRow!.id as string;
				expect(planRow?.author_id).toBe(USER_A.id);
				expect(planRow?.discipline).toBe(discipline);
			});

			// ── 2. USER_A publishes the plan (the RLS hinge for the follower) ───
			await test.step('USER_A makes the plan public', async () => {
				// The detail page is already mounted on /sessions/[id] from step 1.
				await page.getByTestId('session-toggle-public').click();
				// Toggle label flips once the write settles (Make public → Make private).
				await expect(page.getByTestId('session-toggle-public')).toHaveText(/private/i, {
					timeout: 10_000
				});

				const { data: pub } = await admin
					.from('session_plans')
					.select('is_public')
					.eq('id', planId)
					.single();
				expect(pub?.is_public).toBe(true);
			});

			// ── 3. USER_A attaches the plan to a Richmond `class` event ─────────
			await test.step('USER_A attaches the plan to a class event', async () => {
				eventId = await insertEvent({
					club_id: RICHMOND_CLUB_ID,
					author_id: USER_A.id,
					title: eventTitle,
					category: 'class',
					discipline,
					starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
				});

				await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
				await expect(page.getByRole('heading', { name: eventTitle })).toBeVisible({
					timeout: 10_000
				});

				const sequence = page.getByTestId('session-sequence');
				await expect(sequence).toBeVisible();
				await sequence.getByRole('button', { name: 'Attach to a class event' }).click();
				await page.getByTestId('attach-plan-select').selectOption(planId);
				await page.getByTestId('attach-plan-save').click();

				// The event now surfaces the attached sequence read-only.
				await expect(sequence.getByText('Low Lunge (Left)')).toBeVisible({ timeout: 10_000 });

				const { data: evRow } = await admin
					.from('events')
					.select('session_plan_id')
					.eq('id', eventId)
					.single();
				expect(evRow?.session_plan_id).toBe(planId);
			});

			// ── 4 + 5. A SECOND user follows the attached session to completion ─
			await test.step('USER_C_PRO opens the class event, follows the session, logs a workout', async () => {
				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath
				});
				const followerPage = await ctx.newPage();
				try {
					// Morgan is NOT a Richmond member but Richmond is a PUBLIC club, so
					// the event + its attached sequence are visible. The session link
					// resolves only because the plan is public (step 2).
					await followerPage.goto(`/clubs/richmond-run-club/events/${eventId}`);
					await expect(
						followerPage.getByRole('heading', { name: eventTitle })
					).toBeVisible({ timeout: 10_000 });

					const sequence = followerPage.getByTestId('session-sequence');
					const planLink = sequence.locator('a.session-plan-name');
					await expect(planLink).toHaveAttribute('href', `/sessions/${planId}`);
					await planLink.click();

					await followerPage.waitForURL(new RegExp(`/sessions/${planId}$`), {
						timeout: 10_000
					});
					await expect(
						followerPage.getByRole('heading', { name: planTitle })
					).toBeVisible({ timeout: 10_000 });

					// Start the follow-along player and walk it to a clean finish.
					await followerPage.getByTestId('session-start').click();
					const runner = followerPage.getByTestId('session-runner');
					await expect(runner).toBeVisible();
					const band = runner.getByTestId('session-execution-band');

					// Step 1: Downward Dog (30s hold). Done short-circuits the timer.
					await expect(band.getByTestId('session-step-name')).toHaveText('Downward Dog');
					await band.getByTestId('session-done').click();
					// Step 2: Low Lunge (Left).
					await expect(band.getByTestId('session-step-name')).toHaveText('Low Lunge (Left)');
					await band.getByTestId('session-done').click();
					// Step 3: Low Lunge (Right).
					await expect(band.getByTestId('session-step-name')).toHaveText(
						'Low Lunge (Right)'
					);
					await band.getByTestId('session-done').click();
					// Step 4: The Hundred (reps — no countdown). Done on the last step finishes.
					await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred');
					await band.getByTestId('session-done').click();

					await expect(runner).toBeHidden({ timeout: 10_000 });
					await expect(followerPage.getByText('Session saved.')).toBeVisible({
						timeout: 10_000
					});

					// Backend: exactly one gym_workout logged FOR MORGAN against this
					// plan, fully completed. The runner logs against the signed-in user,
					// so this proves the cross-user seam (author's plan, follower's log).
					await expect
						.poll(
							async () => {
								const { data } = await admin
									.from('gym_workouts')
									.select('id, title, user_id, metadata')
									.eq('user_id', USER_C_PRO.id);
								return ((data ?? []) as Array<{ metadata: Record<string, unknown> }>).filter(
									(w) => w.metadata?.session_plan_id === planId
								).length;
							},
							{ timeout: 10_000 }
						)
						.toBe(1);

					const { data: rows } = await admin
						.from('gym_workouts')
						.select('id, title, user_id, metadata')
						.eq('user_id', USER_C_PRO.id);
					const logged = ((rows ?? []) as Array<{
						id: string;
						title: string | null;
						user_id: string;
						metadata: Record<string, unknown>;
					}>).find((w) => w.metadata?.session_plan_id === planId)!;
					loggedWorkoutId = logged.id;
					expect(logged.user_id).toBe(USER_C_PRO.id);
					expect(logged.title).toBe(discipline);
					expect(logged.metadata.session_adherence).toBe('completed');
					expect(Array.isArray(logged.metadata.session_step_results)).toBe(true);
					// 4 expanded steps → 4 step results.
					expect((logged.metadata.session_step_results as unknown[]).length).toBe(4);

					// UI: the logged session shows up in MORGAN's gym history, titled
					// by the plan discipline (workoutDraftFromSession), most-recent first.
					await followerPage.goto('/gym');
					await expect(
						followerPage.locator('.workout-row .row-title', { hasText: discipline }).first()
					).toBeVisible({ timeout: 10_000 });
				} finally {
					await ctx.close();
				}
			});
		} finally {
			// Teardown in reverse dependency order. The workout is the follower's;
			// the event + plan are the author's. All best-effort via the admin client.
			if (loggedWorkoutId) {
				await admin.from('gym_workouts').delete().eq('id', loggedWorkoutId);
			}
			if (eventId) {
				try {
					await deleteEvent(eventId);
				} catch (_) {
					/* best-effort */
				}
			}
			if (planId) {
				await admin.from('session_plans').delete().eq('id', planId);
			}
		}
	});
});
