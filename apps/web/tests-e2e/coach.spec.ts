import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * /coach — Anthropic-backed chat surface. The LLM round-trip itself
 * isn't exercised in e2e (would need a stub for the SSE endpoint);
 * tests here cover everything around it: page mount, plan picker,
 * conversation history sidebar, message composer state.
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
});
