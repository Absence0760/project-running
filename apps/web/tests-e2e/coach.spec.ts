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
});
