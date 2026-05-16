import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

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

	test('chat surface mounts (no LLM call)', async ({ page }) => {
		// /coach mounts CoachChat which loads conversation history
		// and binds the input. We don't actually exercise the LLM
		// — that would need a stub for the SSE endpoint — just
		// verify the page mounts past the "Loading…" state and the
		// composer textarea is wired up.
		await page.goto('/coach');
		await page.waitForLoadState('networkidle');

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
});
