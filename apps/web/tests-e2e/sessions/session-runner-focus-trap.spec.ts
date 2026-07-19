import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Accessibility audit (issue #366) — WCAG 2.4.3 Focus Order / 2.1.2 No Keyboard
 * Trap / 4.1.2: the follow-along SessionRunner renders as a full-screen
 * role="dialog" aria-modal overlay but, before the fix, never moved focus into
 * itself, trapped Tab, or handled Escape — so a keyboard user could Tab from a
 * runner control straight into the obscured host page behind it, and Escape did
 * nothing. Mirrors cross-cutting/modal-focus-trap.spec.ts, which pins the same
 * contract on the shared Modal primitive.
 *
 * Plans are seeded directly (service role) with reps-only steps so the runner
 * never auto-advances mid keyboard cycle. Unique titles per run so the shared
 * seed DB never collides.
 */
test.describe('SessionRunner focus trap', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdPlanIds.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('Tab stays inside the runner and Escape opens the abandon confirm', async ({ page }) => {
		const admin = getAdminClient();
		const title = `e2e-focus-trap ${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
		const { data: planRow, error } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title, discipline: 'Mobility' })
			.select('id')
			.single();
		if (error) throw error;
		const planId = planRow!.id as string;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert([
			{
				plan_id: planId,
				position: 0,
				movement_name: 'Cat Cow',
				kind: 'reps',
				reps: 10,
				per_side: false
			},
			{
				plan_id: planId,
				position: 1,
				movement_name: 'Bird Dog',
				kind: 'reps',
				reps: 8,
				per_side: false
			}
		]);

		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('session-start').click();

		const runner = page.getByTestId('session-runner');
		await expect(runner).toBeVisible();

		// Focus is moved into the runner dialog on open (queueMicrotask), not left
		// on the now-obscured Start button behind it.
		await expect
			.poll(async () =>
				page.evaluate(() => document.activeElement?.closest('[role="dialog"]') != null)
			)
			.toBe(true);

		// The first Tab enters the dialog's first focusable control.
		await page.keyboard.press('Tab');
		const focused = page.locator(':focus');
		await expect(focused).toBeVisible();
		expect(await focused.evaluate((el) => el.closest('[role="dialog"]') != null)).toBe(true);

		// Shift+Tab from the first control wraps to the last, still inside.
		await page.keyboard.press('Shift+Tab');
		expect(
			await page.evaluate(() => document.activeElement?.closest('[role="dialog"]') != null)
		).toBe(true);

		// However far a run of forward Tabs goes, focus never escapes the dialog
		// into the obscured page behind it.
		for (let i = 0; i < 25; i++) {
			await page.keyboard.press('Tab');
		}
		expect(
			await page.evaluate(() => document.activeElement?.closest('[role="dialog"]') != null)
		).toBe(true);

		// Escape opens the abandon confirm rather than silently exiting the live
		// session; the runner stays mounted underneath.
		await page.keyboard.press('Escape');
		await expect(page.getByTestId('session-abandon-dialog')).toBeVisible();
		await expect(runner).toBeVisible();
	});
});
