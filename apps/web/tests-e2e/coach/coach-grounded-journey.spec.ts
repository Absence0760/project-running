import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * AI-coach grounded-context journey — one runner with real training
 * data (the seeded Richmond Half 2026 plan + 12 runs) walks the whole
 * "open the Coach → see what it's grounded in → ask a question → change
 * the grounding window/plan → confirm the change reaches the server"
 * loop. The thread that the per-surface specs (page.spec.ts) exercise
 * a slice at a time, threaded end to end.
 *
 * The grounding contract this pins (src/lib/coach/context.ts):
 *   - The grounded-in context strip (CoachChat.svelte header) reflects
 *     the ACTIVE plan name + its week count + the recent-runs window —
 *     this is the user's read on what the model has loaded.
 *   - The window the strip shows is the window the client POSTs:
 *     `recent_runs_limit` + `plan_id` on the /api/coach body. So
 *     switching the runs window 20 → 50, or the plan → "No plan", must
 *     change what's sent — otherwise the strip lies and the grounding
 *     is a no-op. We capture the POST body on each send and assert it.
 *   - A persisted thread loads from the backend (coach_messages, plan-
 *     scoped) so the conversation survives a reload — proven by seeding
 *     a historical thread via service-role and asserting it renders.
 *
 * The LLM is STUBBED. The real /api/coach handler streams from Anthropic
 * (flaky + costly in CI) AND is the sole writer of the assistant/user
 * coach_messages rows server-side — neither happens here. We intercept
 * the POST and reply with a hand-rolled SSE body (meta / token / done)
 * exactly as page.spec.ts does, and capture each request so the body is
 * the grounding assertion. No coach_messages row is written by a stubbed
 * send, so "persistence" is verified against the SEEDED historical thread
 * (a real backend round-trip), not against the stubbed turn.
 *
 * USER_A (runner@test.com) is the subject: it OWNS the seeded Richmond
 * Half 2026 plan (active, 12 weeks of plan_weeks) and has 12 runs, so the
 * grounded strip is fully populated with zero seeding. It's free-tier
 * (2 msg/day cap); the journey sends three stubbed messages, so the stub's
 * `meta` event raises daily_limit to 10 and get_coach_usage is pinned to 0
 * to keep the composer live across all three (the cap is server-enforced;
 * the stub never round-trips a real provider or usage write).
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const SEED_PLAN_NAME = 'Richmond Half 2026';
const SEED_PLAN_WEEKS = 12;

// A historical thread seeded against the active plan so the journey can
// prove the thread store loads grounded from the backend (not just the
// in-flight stubbed turn). Plan-scoped to SEED_PLAN_ID so it lands in
// the same thread the default /coach view resolves to.
const SEED_USER_Q = `grounded-journey ${Date.now()}: how's my base phase looking?`;
const SEED_ASSISTANT_A = 'Base phase is on track — keep 80% easy.';

/** SSE body matching the meta/token/done events handleSseEvent expects.
 *  daily_limit is set HIGH (10) on purpose: the journey sends three
 *  stubbed messages, and the client bumps usedToday optimistically on
 *  every 200 stream. With the real free cap of 2 the composer would be
 *  replaced by the limit-bar before the third send. The meta event raises
 *  dailyLimit after the first send, so subsequent sends stay under cap. */
function sseBody(reply: string): string {
	return [
		'event: meta',
		`data: ${JSON.stringify({
			user_message_id: 'grounded-user-msg',
			tier: 'free',
			limits: { daily_limit: 10 },
		})}`,
		'',
		'event: token',
		`data: ${JSON.stringify({ text: reply })}`,
		'',
		'event: done',
		`data: ${JSON.stringify({ assistant_message_id: 'grounded-assistant-msg' })}`,
		'',
	].join('\n');
}

test.describe('AI coach grounded-context journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		// Pre-accept consent so the GDPR banner can't float over the
		// composer / context strip (mirrors the upgrade-unlock journey).
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('runner opens Coach → sees the grounded plan + runs window → asks → switches the window/plan and the grounding follows', async ({
		page,
	}) => {
		const admin = getAdminClient();

		// Capture every /api/coach POST body so the grounding (plan_id +
		// recent_runs_limit) is the assertion, not a guess. Re-keyed per
		// send below; the most recent body is what we assert against.
		const coachPosts: Array<Record<string, unknown>> = [];

		try {
			// ── Pre-state: stable plan list + a seeded historical thread ──
			await test.step('seed a clean plan list + a persisted plan-scoped thread', async () => {
				// fetchMyPlans() orders by created_at DESC; an extra plan
				// would push Richmond Half off the first dropdown row and
				// desync the switcher. Sweep non-seed plans + force Richmond
				// active (a prior Replace-plan run could have completed it) —
				// same guard the per-surface page.spec uses.
				await admin
					.from('training_plans')
					.delete()
					.eq('user_id', USER_A.id)
					.neq('id', SEED_PLAN_ID);
				await admin
					.from('training_plans')
					.update({ status: 'active' })
					.eq('id', SEED_PLAN_ID);

				// Clean any leftover active (non-archived) thread on the
				// Richmond-Half scope so the seeded count is deterministic,
				// then plant a real user+assistant pair the thread store
				// must load on first paint.
				await admin
					.from('coach_messages')
					.delete()
					.eq('user_id', USER_A.id)
					.eq('plan_id', SEED_PLAN_ID);
				const { error: seedErr } = await admin.from('coach_messages').insert([
					{
						user_id: USER_A.id,
						plan_id: SEED_PLAN_ID,
						role: 'user',
						content: SEED_USER_Q,
						created_at: '2026-05-10T09:00:00.000Z',
					},
					{
						user_id: USER_A.id,
						plan_id: SEED_PLAN_ID,
						role: 'assistant',
						content: SEED_ASSISTANT_A,
						created_at: '2026-05-10T09:00:05.000Z',
					},
				]);
				expect(seedErr).toBeNull();
			});

			// Pin the coach usage to 0 so usedToday starts deterministic — a
			// prior same-day run on this shared free user could otherwise have
			// left a real count that eats into the headroom for three sends.
			await page.route('**/rest/v1/rpc/get_coach_usage*', async (route) => {
				await route.fulfill({
					status: 200,
					headers: { 'content-type': 'application/json' },
					body: '0',
				});
			});

			// Install the SSE stub for the whole journey; record each body.
			let nextReply = 'Run easy today — target 5:30/km for 6 km.';
			await page.route('**/api/coach', async (route) => {
				const post = route.request().postDataJSON() as Record<string, unknown>;
				coachPosts.push(post);
				await route.fulfill({
					status: 200,
					headers: {
						'content-type': 'text/event-stream',
						'cache-control': 'no-cache',
					},
					body: sseBody(nextReply),
				});
			});

			// ── 1. Open Coach: grounded-in strip reflects the active plan ──
			await test.step('the grounded-in context strip shows the active plan + week count + runs window', async () => {
				await page.goto('/coach');

				// Plan chip (a ChipDropdown trigger, aria-label "Plan
				// context") carries the active plan name + its `· 12w` week
				// suffix — the strip's headline "what's loaded" signal.
				const planTrigger = page.getByRole('button', { name: 'Plan context' });
				await expect(planTrigger).toContainText(SEED_PLAN_NAME, { timeout: 10_000 });
				await expect(planTrigger).toContainText(`${SEED_PLAN_WEEKS}w`);

				// Runs-window chip defaults to Last 20 (DEFAULT_RUNS_LIMIT).
				const runsTrigger = page.getByRole('button', { name: 'Recent runs to include' });
				await expect(runsTrigger).toBeVisible();
				await expect(runsTrigger).toContainText('Last 20');
			});

			// ── 2. The seeded historical thread loaded from the backend ───
			await test.step('the persisted plan-scoped thread loads (grounded conversation survives)', async () => {
				// The seeded user turn renders as a .bubble.user, and the
				// seeded assistant turn as a non-user .bubble. Both prove the
				// thread store hydrated from coach_messages (a real backend
				// read), scoped to the active plan.
				await expect(
					page.locator('.bubble.user', { hasText: SEED_USER_Q }),
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator('.bubble', { hasText: SEED_ASSISTANT_A }),
				).toBeVisible();

				// The sidebar's active-thread row mirrors the loaded count
				// ("Active · 2"). Open the sidebar to read it.
				await page
					.getByRole('button', { name: /Show conversations|Hide conversations/i })
					.click();
				const activeRow = page.locator('.shell aside.sidebar .thread-row.active');
				await expect(activeRow).toContainText('Active');
				await expect(activeRow).toContainText('· 2');
				// Close it again so the composer is unobstructed.
				await page
					.getByRole('button', { name: /Hide conversations/i })
					.click();
			});

			// ── 3. Ask a question: stubbed reply streams + body is grounded ─
			await test.step('asking sends the grounded context (plan_id + 20-run window) and streams the reply', async () => {
				const before = coachPosts.length;
				const composer = page.getByPlaceholder(/Ask about today/);
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill('What should I run today?');
				await page.locator('form.composer button[type="submit"]').click();

				// Stubbed assistant reply renders in a non-user bubble.
				await expect(
					page.locator('.bubble', { hasText: nextReply }),
				).toBeVisible({ timeout: 10_000 });

				// The grounding assertion: the POST carried the active plan
				// + the default 20-run window. This is what the strip claims
				// is loaded — pin that the claim is honoured on the wire.
				expect(coachPosts.length).toBe(before + 1);
				const body = coachPosts[coachPosts.length - 1];
				expect(body.plan_id).toBe(SEED_PLAN_ID);
				expect(body.recent_runs_limit).toBe(20);
			});

			// ── 4. Switch the runs window → grounding window follows ──────
			await test.step('switching the runs window to Last 50 changes the strip AND the next request', async () => {
				const runsTrigger = page.getByRole('button', { name: 'Recent runs to include' });
				await runsTrigger.click();
				const popover = page.locator('[role="listbox"]');
				await expect(popover).toBeVisible({ timeout: 5_000 });
				// `name` substring-matches, so "Last 50" alone would also hit
				// "Last 500" if it existed — exact:true keeps it precise.
				await popover.getByRole('option', { name: 'Last 50', exact: true }).click();
				await expect(popover).toHaveCount(0);
				await expect(runsTrigger).toContainText('Last 50');

				// Ask again — the new window must reach the server.
				const before = coachPosts.length;
				nextReply = 'Across your last 50 runs, weekly volume is trending up.';
				const composer = page.getByPlaceholder(/Ask about today/);
				await composer.fill('How does my volume look lately?');
				await page.locator('form.composer button[type="submit"]').click();

				await expect(
					page.locator('.bubble', { hasText: nextReply }),
				).toBeVisible({ timeout: 10_000 });

				expect(coachPosts.length).toBe(before + 1);
				const body = coachPosts[coachPosts.length - 1];
				// The window changed: the grounding window is now 50, proving
				// the chip isn't cosmetic — it re-scopes what context.ts loads.
				expect(body.recent_runs_limit).toBe(50);
				expect(body.plan_id).toBe(SEED_PLAN_ID);
			});

			// ── 5. Switch the plan → "No plan" → grounding plan follows ───
			await test.step('picking "No plan" flips the strip to ?plan=none and the next request drops the plan', async () => {
				const planTrigger = page.getByRole('button', { name: 'Plan context' });
				await planTrigger.click();
				const popover = page.locator('[role="listbox"]');
				await expect(popover).toBeVisible({ timeout: 5_000 });
				await popover.getByRole('option', { name: /No plan/ }).click();
				await expect(popover).toHaveCount(0);

				// The explicit "no plan" choice is encoded in the URL so a
				// reload doesn't silently revert to the active plan.
				await expect(page).toHaveURL(/[?&]plan=none\b/);
				await expect(planTrigger).toContainText('No plan');

				// The chat-host remounts on the planId change ({#key planId}
				// in /coach/+page.svelte), so CoachChat re-mounts under the
				// no-plan scope: the active thread is empty (the seeded
				// Richmond thread does NOT bleed across plan scopes) AND the
				// component-local runsLimit resets to its default 20. Confirm
				// the no-plan runs chip shows Last 20 again.
				const runsTrigger = page.getByRole('button', { name: 'Recent runs to include' });
				await expect(runsTrigger).toContainText('Last 20', { timeout: 10_000 });

				// Ask once more and confirm the request carries no plan.
				const before = coachPosts.length;
				nextReply = 'Without a plan, base your easy pace on recent runs.';
				const composer = page.getByPlaceholder(/Ask about today/);
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill('What easy pace should I run?');
				await page.locator('form.composer button[type="submit"]').click();

				await expect(
					page.locator('.bubble', { hasText: nextReply }),
				).toBeVisible({ timeout: 10_000 });

				expect(coachPosts.length).toBe(before + 1);
				const body = coachPosts[coachPosts.length - 1];
				// plan_id is null now — the grounding dropped the plan. The
				// runs window reset to 20 on the per-plan remount (the window
				// is scoped to the chat-host instance, not global).
				expect(body.plan_id ?? null).toBeNull();
				expect(body.recent_runs_limit).toBe(20);
			});
		} finally {
			// ── Teardown: drop the seeded thread + restore the plan list ──
			// USER_A is the shared subject across the suite; a leaked plan-
			// scoped coach thread or a non-active Richmond plan would poison
			// the per-surface coach specs. (The stubbed turns never wrote any
			// coach_messages row — only the seeded pair needs removing.)
			await admin
				.from('coach_messages')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('plan_id', SEED_PLAN_ID);
			await admin
				.from('training_plans')
				.update({ status: 'active' })
				.eq('id', SEED_PLAN_ID);
		}
	});
});
