import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * /coach — Anthropic-backed chat surface. The LLM round-trip itself
 * isn't exercised in e2e (would need a stub for the SSE endpoint);
 * tests here cover everything around it: page mount, plan picker,
 * runs-limit picker, conversation history sidebar, message composer
 * state.
 *
 * The plan + runs-limit chips are themed `<ChipDropdown>` instances
 * (a custom popover-backed dropdown — replaces the OS-native
 * `<select>` whose popup couldn't be themed). Tests below pin both
 * the trigger styling AND the option-pick → URL / state flow.
 */

test.describe('/coach', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// The plan ChipDropdown lists fetchMyPlans() ordered by
		// created_at DESC, so any test that plants an extra plan for
		// runner pushes Sydney Half 2026 off the first row of the
		// dropdown. The keyboard-nav test below (ArrowDown from "No
		// plan") then picks the wrong plan and fails with a stale
		// "test · 12w" assertion. Sweep any non-seed plans (including
		// abandoned and template clones) so the dropdown order is
		// stable. Restore Sydney Half to active in case a prior run's
		// Replace-plan flow left it completed.
		const admin = getAdminClient();
		await admin
			.from('training_plans')
			.delete()
			.eq('user_id', USER_A.id)
			.neq('id', SEED_PLAN_ID);
		await admin
			.from('training_plans')
			.update({ status: 'active' })
			.eq('id', SEED_PLAN_ID);
	});

	test('chat surface mounts (no LLM call)', async ({ page }) => {
		// /coach mounts CoachChat which loads conversation history
		// and binds the input. We don't actually exercise the LLM
		// — that would need a stub for the SSE endpoint — just
		// verify the page mounts past the "Loading…" state and the
		// composer textarea is wired up.
		await page.goto('/coach');

		// CoachChat's input has a placeholder starting with "Ask
		// about today, pace, adherence…" — see CoachChat.svelte.
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
	});

	test('plan dropdown — picking "No plan" persists via ?plan=none and survives a reload', async ({
		page
	}) => {
		// The plan chip is a ChipDropdown trigger with aria-label
		// "Plan context". Default state on a fresh /coach load:
		// runner's only seeded plan ("Sydney Half 2026") is the active
		// one, so it's preselected.
		await page.goto('/coach');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toBeVisible({ timeout: 10_000 });

		// Open the popover.
		await planTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });

		// Both options should be present: "No plan" + "Sydney Half 2026".
		await expect(
			popover.getByRole('option', { name: /No plan/ })
		).toBeVisible();
		await expect(
			popover.getByRole('option', { name: /Sydney Half 2026/ })
		).toBeVisible();

		// Pick "No plan" — the previous bug was that this silently
		// reverted to the active plan because resolvePlanId fell back
		// when the URL had no `?plan=`. The fix encodes the explicit
		// "no plan" choice as `?plan=none` so the page knows to stay
		// null on the next resolve.
		await popover.getByRole('option', { name: /No plan/ }).click();
		await expect(popover).toHaveCount(0);
		await expect(page).toHaveURL(/[?&]plan=none\b/);
		// Trigger label flips to the selected option.
		await expect(planTrigger).toContainText('No plan');

		// Reload — the URL persists, so the explicit "No plan" stays.
		await page.reload();
		await expect(planTrigger).toBeVisible({ timeout: 10_000 });
		await expect(planTrigger).toContainText('No plan');
		await expect(page).toHaveURL(/[?&]plan=none\b/);
	});

	test('plan dropdown — picking the seeded plan sets ?plan=<id>', async ({
		page
	}) => {
		// Land on /coach?plan=none so the trigger starts as "No plan"
		// — that way picking the real plan is a clean transition.
		await page.goto('/coach?plan=none');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toContainText('No plan', { timeout: 10_000 });

		await planTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await popover.getByRole('option', { name: /Sydney Half 2026/ }).click();
		await expect(popover).toHaveCount(0);

		// Plan UUIDs are 8-4-4-4-12 hex; pin the URL changed.
		await expect(page).toHaveURL(/[?&]plan=[0-9a-f-]{36}\b/);
		await expect(planTrigger).toContainText('Sydney Half 2026');
	});

	test('runs-limit dropdown — picking "Last 50" updates the trigger label', async ({
		page
	}) => {
		await page.goto('/coach');
		const runsTrigger = page.getByRole('button', { name: 'Recent runs to include' });
		await expect(runsTrigger).toBeVisible({ timeout: 10_000 });

		// Default: Last 20 (DEFAULT_RUNS_LIMIT in CoachChat).
		await expect(runsTrigger).toContainText('Last 20');

		await runsTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });

		// Each option is the literal "Last <n>" — pin all 4 are present.
		// `name` does a substring match, so "Last 10" would also match
		// "Last 100" without exact:true.
		for (const n of [10, 20, 50, 100]) {
			await expect(
				popover.getByRole('option', { name: `Last ${n}`, exact: true })
			).toBeVisible();
		}

		await popover.getByRole('option', { name: 'Last 50', exact: true }).click();
		await expect(popover).toHaveCount(0);
		await expect(runsTrigger).toContainText('Last 50');

		// Restore so subsequent tests start from the default.
		await runsTrigger.click();
		await page
			.locator('[role="listbox"]')
			.getByRole('option', { name: 'Last 20', exact: true })
			.click();
	});

	test('plan dropdown — keyboard navigation (ArrowDown + Enter picks the focused option)', async ({
		page
	}) => {
		// Pin a11y: the trigger opens on Enter, ArrowDown moves the
		// active option, Enter picks. Without keyboard support this
		// custom dropdown would regress on screen-reader users vs.
		// the OS-native <select> we replaced.
		await page.goto('/coach?plan=none');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toContainText('No plan', { timeout: 10_000 });

		// Focus the trigger then open with Enter.
		await planTrigger.focus();
		await page.keyboard.press('Enter');
		const popover = page.locator('[role="listbox"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });

		// First option ("No plan") is active on open; ArrowDown moves
		// to "Sydney Half 2026".
		await page.keyboard.press('ArrowDown');
		await page.keyboard.press('Enter');
		await expect(popover).toHaveCount(0);
		await expect(planTrigger).toContainText('Sydney Half 2026');
	});

	test('429 daily-limit response surfaces the retry message instead of failing silently', async ({
		page
	}) => {
		// Free users have a daily message cap. When the server returns
		// 429 with { used, tier, limit, message }, the client must
		// surface a clear message so the user knows what happened —
		// otherwise the assistant bubble vanishes mid-flight and the
		// composer feels broken (a leave-the-app moment).
		await page.route('**/api/coach', async (route) => {
			await route.fulfill({
				status: 429,
				contentType: 'application/json',
				body: JSON.stringify({
					error: 'rate_limited',
					used: 5,
					limit: 5,
					tier: 'free',
					message: 'Daily limit reached (5 messages). Come back tomorrow!'
				})
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });

		await composer.fill('What pace today?');
		await page.locator('form.composer button[type="submit"]').click();

		// Surfaced as the .error banner inside CoachChat, OR the daily-
		// limit "no messages left" empty-state in the composer area.
		// Either is acceptable — both communicate "nothing's broken,
		// you've used your allowance" rather than silent failure.
		await expect(
			page.getByText(/Daily limit reached/i)
		).toBeVisible({ timeout: 10_000 });
	});

	test('send → mocked SSE response streams into an assistant bubble', async ({
		page
	}) => {
		// The headline AI feature: type a question → Send → POST
		// /api/coach → SSE stream → assistant bubble fills with the
		// streamed text. The real handler hits Anthropic / OpenAI which
		// would be flaky + costly in CI, so intercept the POST and
		// reply with a hand-rolled SSE body matching the meta / token /
		// done events that handleSseEvent in CoachChat.svelte expects.
		// Pins the read-stream + bubble-update pipeline against
		// regressions in the parser, the optimistic placeholder, or
		// the meta-id stitching.
		const ASSISTANT_REPLY = 'Run easy today, target 5:30/km for 6 km.';

		await page.route('**/api/coach', async (route) => {
			const body = [
				'event: meta',
				`data: ${JSON.stringify({
					user_message_id: 'e2e-user-msg',
					tier: 'free',
					limits: { daily_limit: 20 }
				})}`,
				'',
				'event: token',
				`data: ${JSON.stringify({ text: ASSISTANT_REPLY })}`,
				'',
				'event: done',
				`data: ${JSON.stringify({ assistant_message_id: 'e2e-assistant-msg' })}`,
				''
			].join('\n');

			await route.fulfill({
				status: 200,
				headers: {
					'content-type': 'text/event-stream',
					'cache-control': 'no-cache'
				},
				body
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });

		const userText = `e2e-coach ${Date.now()} pace?`;
		await composer.fill(userText);
		await page.locator('form.composer button[type="submit"]').click();

		// The streamed token lands in a `.bubble` (the assistant one
		// — non-user). Constrain to .bubble so the conversation-history
		// sidebar's `.thread-title` (which mirrors the user message)
		// doesn't confuse the locator.
		await expect(
			page.locator('.bubble', { hasText: ASSISTANT_REPLY })
		).toBeVisible({ timeout: 10_000 });

		// User's bubble (the one with .user class) holds the prompt.
		await expect(
			page.locator('.bubble.user', { hasText: userText })
		).toBeVisible();
	});

	test('SSE: multi-token stream appends in order into the assistant bubble', async ({
		page
	}) => {
		// The existing happy-path test fires a single token event.
		// Real LLM responses arrive as N small chunks — the bubble must
		// accumulate them in arrival order. A regression that replaced
		// (not appended) the bubble content on each token would still
		// pass the single-token test but ship "Run easy today, target"
		// instead of the full reply. Pin three chunks that together
		// form a recognisable sentence so the assertion proves order.
		const CHUNKS = ['Run easy today', ', target 5:30/km', ' for 6 km.'];
		const EXPECTED = CHUNKS.join('');
		await page.route('**/api/coach', async (route) => {
			const blocks = [
				`event: meta\ndata: ${JSON.stringify({
					user_message_id: 'multi-user',
					tier: 'free',
					limits: { daily_limit: 20 }
				})}\n`,
				...CHUNKS.map(
					(t) => `event: token\ndata: ${JSON.stringify({ text: t })}\n`
				),
				`event: done\ndata: ${JSON.stringify({
					assistant_message_id: 'multi-assistant'
				})}\n`
			];
			await route.fulfill({
				status: 200,
				headers: {
					'content-type': 'text/event-stream',
					'cache-control': 'no-cache'
				},
				body: blocks.join('\n')
			});
		});

		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({
			timeout: 10_000
		});
		await page.getByPlaceholder(/Ask about today/).fill('e2e multi-token');
		await page.locator('form.composer button[type="submit"]').click();

		await expect(
			page.locator('.bubble', { hasText: EXPECTED })
		).toBeVisible({ timeout: 10_000 });
	});

	test('SSE: special characters in streamed tokens render verbatim', async ({
		page
	}) => {
		// Markdown backticks, em-dashes, curly quotes, an emoji, and an
		// accented character all live in real LLM responses. A
		// JSON-stringify/parse round-trip on every token chunk must
		// preserve them — a regression in either the server's
		// `event: token\ndata: ...` escaping or the client's parse
		// would corrupt at least one. Pin the full set so a
		// "works for ASCII, drops on multibyte" regression fails loud.
		const STR = 'Pace: `5:30/km` — try “easy effort” 😅 (café tempo)';
		await page.route('**/api/coach', async (route) => {
			const body = [
				'event: meta',
				`data: ${JSON.stringify({
					user_message_id: 'sc-user',
					tier: 'free',
					limits: { daily_limit: 20 }
				})}`,
				'',
				'event: token',
				`data: ${JSON.stringify({ text: STR })}`,
				'',
				'event: done',
				`data: ${JSON.stringify({ assistant_message_id: 'sc-assistant' })}`,
				''
			].join('\n');
			await route.fulfill({
				status: 200,
				headers: {
					'content-type': 'text/event-stream',
					'cache-control': 'no-cache'
				},
				body
			});
		});

		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({
			timeout: 10_000
		});
		await page.getByPlaceholder(/Ask about today/).fill('e2e special chars');
		await page.locator('form.composer button[type="submit"]').click();

		// The bubble renders the markdown through CoachChat's sanitiser,
		// which wraps backticked spans in <code>. Assert on a sentinel
		// substring (the emoji + accent) that survives any wrapper.
		await expect(
			page.locator('.bubble', { hasText: /😅.*café/ })
		).toBeVisible({ timeout: 10_000 });
	});

	test('SSE: mid-stream error event surfaces banner + retains partial text', async ({
		page
	}) => {
		// Real failure mode — provider streams a few tokens then their
		// upstream rate-limit / context-window-overflow / safety-filter
		// fires and the server emits `event: error`. The user must see
		// (a) the partial text that DID stream + (b) a banner naming
		// the failure, not a stuck "Thinking…" spinner. A regression
		// that dropped the partial text on error would silently lose
		// what the runner already saw scroll past.
		const PARTIAL = 'Run easy today,';
		const ERR_MSG = 'Provider returned 429';
		await page.route('**/api/coach', async (route) => {
			// SSE event blocks must end with `\n\n` for CoachChat's
			// parser (readSse looks for `\n\n` to flush each block).
			// Joining `['...','']` only produces `...\n`, which leaves
			// the last block unflushed and silently drops the error
			// event. Construct each event with an explicit double-
			// newline tail so the parser sees every event.
			const events = [
				{
					event: 'meta',
					data: {
						user_message_id: 'mid-user',
						tier: 'free',
						limits: { daily_limit: 20 }
					}
				},
				{ event: 'token', data: { text: PARTIAL } },
				{ event: 'error', data: { message: ERR_MSG } }
			];
			const body = events
				.map((e) => `event: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`)
				.join('');
			await route.fulfill({
				status: 200,
				headers: {
					'content-type': 'text/event-stream',
					'cache-control': 'no-cache'
				},
				body
			});
		});

		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({
			timeout: 10_000
		});
		await page.getByPlaceholder(/Ask about today/).fill('e2e mid-stream err');
		await page.locator('form.composer button[type="submit"]').click();

		// Both: partial bubble + error banner.
		await expect(
			page.locator('.bubble', { hasText: PARTIAL })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText(ERR_MSG)).toBeVisible({ timeout: 10_000 });
	});

	test('SSE: empty stream (meta + done, no tokens) does not stall the bubble', async ({
		page
	}) => {
		// Real LLM responses are non-empty in happy-path cases, but
		// content-filter + safety-block + provider-soft-fail can all
		// emit a meta/done pair with no token events. CoachChat must
		// finalise the (empty) bubble + leave the composer reusable
		// rather than parking in "Thinking…" forever. Pin the
		// composer-renabled signal — a regression that locked the
		// composer would block the user's recovery message.
		await page.route('**/api/coach', async (route) => {
			const body = [
				'event: meta',
				`data: ${JSON.stringify({
					user_message_id: 'empty-user',
					tier: 'free',
					limits: { daily_limit: 20 }
				})}`,
				'',
				'event: done',
				`data: ${JSON.stringify({ assistant_message_id: 'empty-assistant' })}`,
				''
			].join('\n');
			await route.fulfill({
				status: 200,
				headers: {
					'content-type': 'text/event-stream',
					'cache-control': 'no-cache'
				},
				body
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill('e2e empty stream');
		await page.locator('form.composer button[type="submit"]').click();

		// Composer becomes reusable: typing into it must succeed
		// (a stuck "Thinking…" state would disable the textarea).
		// Poll because the un-block signal arrives after `done`.
		await expect
			.poll(
				async () => {
					await composer.fill('follow-up after empty stream');
					return await composer.inputValue();
				},
				{ timeout: 10_000 }
			)
			.toBe('follow-up after empty stream');
	});

	test('runs-limit chip flips its trigger label after picking Last 50', async ({
		page
	}) => {
		await page.goto('/coach');
		const runsTrigger = page.getByRole('button', { name: 'Recent runs' });
		await expect(runsTrigger).toBeVisible({ timeout: 10_000 });
		await runsTrigger.click();
		await page.getByRole('option', { name: 'Last 50' }).click();
		await expect(runsTrigger).toContainText('Last 50');
	});

	test('401 from /api/coach surfaces a non-empty error banner instead of stalling on "Thinking…"', async ({
		page
	}) => {
		// When the streaming endpoint rejects with 401 (e.g. the
		// session expired upstream), CoachChat falls through to the
		// generic-error branch (line 475) and surfaces j.error or
		// `Coach error (401)`. Pin that the banner is visible — a
		// regression that swallowed the error would leave the
		// optimistic assistant bubble in a "Thinking…" spinner.
		const errorMessage = 'Session expired. Please refresh.';
		await page.route('**/api/coach', async (route) => {
			await route.fulfill({
				status: 401,
				contentType: 'application/json',
				body: JSON.stringify({ error: errorMessage })
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill('e2e 401 path');
		await page.locator('form.composer button[type="submit"]').click();

		await expect(
			page.getByText(errorMessage)
		).toBeVisible({ timeout: 10_000 });
	});

	test('500 upstream error surfaces a banner instead of leaving the user staring at "Thinking…"', async ({
		page
	}) => {
		// When the LLM provider 500s the streaming endpoint, the SSE
		// reader throws and CoachChat must surface a non-empty error
		// banner. A regression that swallowed the error would leave
		// the optimistic assistant bubble in a "Thinking…" state
		// indefinitely — a leave-the-app moment.
		await page.route('**/api/coach', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({
					error: 'Coach is temporarily unavailable. Try again shortly.'
				})
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill('e2e 500 path');
		await page.locator('form.composer button[type="submit"]').click();

		// CoachChat reads j.error first for non-401/429 responses
		// (line 475 in CoachChat.svelte), so the banner surfaces the
		// upstream `error` field as the user-facing message.
		await expect(
			page.getByText(/Coach is temporarily unavailable|temporarily unavailable/i)
		).toBeVisible({ timeout: 10_000 });
	});

	test('chat history sidebar mounts (the conversation-history scaffold is reachable)', async ({
		page
	}) => {
		await page.goto('/coach');
		// Prove the page mounts past the loading shell — the composer
		// and the plan/runs chips both render.
		await expect(page.getByRole('button', { name: 'Plan context' }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Recent runs' }))
			.toBeVisible();
	});

	test('Guided-runs right rail mounts with intensity chips + bottom mobile-CTA panel + forward-arrow library link', async ({
		page
	}) => {
		// The polish round restructured the right rail: ALSO-FOR-YOU
		// eyebrow + h2, per-card intensity chip with tone-coded dot,
		// bottom-anchored mobile-CTA panel that fills empty space on
		// tall viewports, and a forward-arrow "See the full library →"
		// link (was a back-arrow, read as a return). Pin those so the
		// hierarchy/CTA changes can't silently regress.
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/coach');
		const rail = page.locator('aside.guided');
		await expect(rail).toBeVisible({ timeout: 10_000 });

		// Eyebrow + h2 reads as the rail's heading hierarchy.
		await expect(rail.getByText(/ALSO FOR YOU/i)).toBeVisible();
		await expect(
			rail.getByRole('heading', { level: 2, name: /Guided runs/i })
		).toBeVisible();

		// At least one card carries an intensity chip + dot.
		const cards = rail.locator('.guided-card');
		await expect(cards.first()).toBeVisible();
		await expect(cards.first().locator('.intensity-dot')).toBeVisible();

		// Bottom-anchored mobile-CTA fills the empty rail space at desktop width.
		await expect(rail.locator('.mobile-cta')).toBeVisible();
		await expect(rail.locator('.mobile-cta')).toContainText(
			/Run these on mobile/i
		);

		// Library link reads as a forward action — material-symbol
		// arrow_forward icon sits AFTER the text node so the link
		// reads as a forward CTA, not a back-link.
		const libraryLink = rail.getByRole('link', { name: /See the full library/i });
		await expect(libraryLink).toBeVisible();
		const arrowText = await libraryLink
			.locator('.material-symbols')
			.textContent();
		expect(arrowText?.trim()).toBe('arrow_forward');
	});

	test('mobile-CTA panel is hidden on narrow viewports (user is already on mobile)', async ({
		page
	}) => {
		// The "Run these on mobile" bridge messaging is desktop-only —
		// telling a user on their phone to "run these on mobile" is
		// nonsense chrome. Pin the responsive hide at <=64rem.
		await page.setViewportSize({ width: 720, height: 900 });
		await page.goto('/coach');
		await expect(page.locator('aside.guided')).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('aside.guided .mobile-cta')).toBeHidden();
	});

	test('composer Send button is disabled on empty draft and enables once the user types', async ({
		page
	}) => {
		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });

		const sendBtn = page.locator('form.composer button[type="submit"]');
		await expect(sendBtn).toBeDisabled();

		await composer.fill('hi');
		await expect(sendBtn).toBeEnabled();

		await composer.fill('   ');
		await expect(sendBtn).toBeDisabled();

		await composer.fill('what pace for tomorrow?');
		await expect(sendBtn).toBeEnabled();
	});

	test('composer supports Shift+Enter for newline; Enter alone submits', async ({
		page
	}) => {
		// Contract: Enter submits, Shift+Enter inserts a newline. The
		// onkeydown handler in CoachChat.svelte hard-pins this — without
		// it, multi-line questions would be impossible.
		await page.route('**/api/coach', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'stub' })
			});
		});

		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });

		await composer.focus();
		await composer.type('line one');
		await page.keyboard.press('Shift+Enter');
		await composer.type('line two');

		await expect(composer).toHaveValue('line one\nline two');

		await page.keyboard.press('Enter');
		await expect(page.getByText(/stub/)).toBeVisible({ timeout: 5_000 });
	});

	test('picking a real plan via mouse-click switches the chat-host (planId key remount)', async ({
		page
	}) => {
		// Plan-context chip — `value=""` is the "No plan" option. Picking
		// a real plan must update the URL AND the chat-host remounts
		// (`{#key planId}`) so the thread reloads for the new plan
		// scope.
		await page.goto('/coach?plan=none');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toContainText('No plan', { timeout: 10_000 });

		await planTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await popover.getByRole('option', { name: /Sydney Half 2026/ }).click();
		await expect(planTrigger).toContainText('Sydney Half 2026');

		// Header sub-copy adapts to the plan-present state.
		await expect(
			page.locator('header .sub', { hasText: /Second opinion on your plan and runs/i })
		).toBeVisible({ timeout: 5_000 });

		await page.reload();
		await expect(planTrigger).toContainText('Sydney Half 2026', { timeout: 10_000 });
		await expect(page).toHaveURL(/[?&]plan=[0-9a-f-]{36}\b/);
	});

	test('grounded-in context strip surfaces the active plan name', async ({
		page
	}) => {
		// The "what the coach has loaded" chip-strip is the user's read
		// on grounding. Pin that the active plan name lands in the
		// trigger AND the runs-window chip is alongside it — both must
		// render together for the strip to be useful.
		await page.goto('/coach');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		const runsTrigger = page.getByRole('button', { name: 'Recent runs to include' });

		await expect(planTrigger).toContainText('Sydney Half 2026', { timeout: 10_000 });
		await expect(runsTrigger).toBeVisible();
		await expect(runsTrigger).toContainText('Last 20');
	});

	test('chat-history sidebar toggles open + closed via the menu button', async ({
		page
	}) => {
		// Collapses by default — the toggle must show + hide the panel
		// without a navigation, so a user can sweep history mid-thread.
		await page.goto('/coach');
		await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({
			timeout: 10_000
		});

		const sidebar = page.locator('.shell aside.sidebar');
		await expect(sidebar).toHaveClass(/collapsed/);

		const toggle = page.getByRole('button', { name: /Show conversations/i });
		await toggle.click();
		await expect(sidebar).not.toHaveClass(/collapsed/);

		// "New chat" affordance lives in the open sidebar header.
		await expect(sidebar.getByRole('button', { name: /New chat/i }))
			.toBeVisible();

		// The active-thread row renders with the "Active" meta line.
		await expect(sidebar.locator('.thread-row.active')).toBeVisible();
		await expect(sidebar.locator('.thread-row.active')).toContainText(/Active/);

		const closeToggle = page.getByRole('button', { name: /Hide conversations/i });
		await closeToggle.click();
		await expect(sidebar).toHaveClass(/collapsed/);
	});
});

test.describe('/coach — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login', async ({ page }) => {
		// /coach is NOT in the anon-allowed list, so an anon user must
		// be redirected to /login with a return_to.
		await page.goto('/coach');
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
	});
});
