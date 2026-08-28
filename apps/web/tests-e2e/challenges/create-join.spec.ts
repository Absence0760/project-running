import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readRow } from '../fixtures/db-read';

/**
 * Challenges create + join lifecycle (challenges.md).
 * USER_A creates an individual distance challenge via the editor, it appears
 * in My challenges (the creator is NOT auto-joined), then joins it from the
 * detail page and the Leave control appears.
 *
 * Also pins the goal field's unit contract (decisions § 758): the author types
 * in their own unit and the editor converts into the metres / seconds / count
 * `challenges.goal_value` stores, so a typed `100` on a distance board is
 * 100 km rather than the 100 metre goal every entrant cleared on their first
 * run. The two refusals `challenges_goal_ck` makes are named inline before the
 * insert, never as a raw 23514.
 */
test.describe('/challenges — create + join', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of created) {
			await admin.from('challenges').delete().eq('id', id);
		}
		created.length = 0;
	});

	test('create an individual distance challenge, then join it', async ({ page }) => {
		const title = `e2e-challenge ${Date.now()}`;

		await page.goto('/challenges');
		await expect(page.getByRole('heading', { level: 1, name: /Challenges/ })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(title);

		// The field names the reader's own unit, so 100 means 100 km.
		await expect(modal.locator('.goal-unit')).toHaveText('km');
		await modal.getByLabel(/Goal/).fill('100');
		await expect(modal.getByText(/Entrants see\s+100(\.00)?\s?km/)).toBeVisible();

		await modal.getByRole('button', { name: /Create challenge/ }).click();

		// Lands on the new challenge's detail page.
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		// Capture the id for cleanup from the URL.
		const url = new URL(page.url());
		const id = url.pathname.split('/').pop()!;
		created.push(id);

		// The stored figure is the converted one — the whole point of the field.
		const row = await readRow(
			'challenges by id',
			getAdminClient()
				.from('challenges')
				.select('goal_value')
				.eq('id', id)
				.single()
		);
		expect(Number(row.goal_value)).toBe(100_000);

		// Creator is not auto-joined → Join is offered.
		const joinBtn = page.getByRole('button', { name: /^Join$/ });
		await expect(joinBtn).toBeVisible();
		await joinBtn.click();

		// After joining, Leave appears and the progress bar (for an individual
		// joined challenge) shows.
		await expect(page.getByRole('button', { name: /^Leave$/ })).toBeVisible({ timeout: 10_000 });
	});

	test('create a vert (elevation) challenge', async ({ page }) => {
		const title = `e2e-vert ${Date.now()}`;

		await page.goto('/challenges');
		await expect(page.getByRole('heading', { level: 1, name: /Challenges/ })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(title);
		await modal.getByLabel(/Metric/).selectOption({ label: 'Elevation' });
		await expect(modal.locator('.goal-unit')).toHaveText('m');
		await modal.getByLabel(/Goal/).fill('1000');
		await modal.getByRole('button', { name: /Create challenge/ }).click();

		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		const url = new URL(page.url());
		const id = url.pathname.split('/').pop()!;
		created.push(id);

		// The goal renders through formatElevation (km pref → "m"), proving the
		// vert metric flows create → leaderboard display.
		await expect(page.getByText(/1,?000\s?m/).first()).toBeVisible({ timeout: 10_000 });
	});

	test('the goal unit follows the metric, and switching metric clears the number', async ({
		page
	}) => {
		await page.goto('/challenges');
		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const goal = modal.getByLabel(/Goal/);
		await goal.fill('100');
		await expect(modal.locator('.goal-unit')).toHaveText('km');

		// A 100 that meant kilometres must not silently become 100 hours.
		await modal.getByLabel(/Metric/).selectOption({ label: 'Time' });
		await expect(modal.locator('.goal-unit')).toHaveText('h');
		await expect(goal).toHaveValue('');

		// Hours in, seconds stored — the readback is the leaderboard's own
		// rendering of the converted figure.
		await goal.fill('5');
		await expect(modal.getByText(/Entrants see\s+5:00:00/)).toBeVisible();

		await modal.getByLabel(/Metric/).selectOption({ label: 'Active days' });
		await expect(modal.locator('.goal-unit')).toHaveText('days');
		// The window ceiling is stated up front, not only on a refusal.
		await expect(modal.getByText(/At most \d+ active days fit in this window/)).toBeVisible();
	});

	test('a goal the window cannot hold is refused inline, before the insert', async ({ page }) => {
		await page.goto('/challenges');
		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(`e2e-unwinnable ${Date.now()}`);
		await modal.getByLabel(/Metric/).selectOption({ label: 'Active days' });
		// The default window is 30 days, so 400 active days can never be reached.
		await modal.getByLabel(/Goal/).fill('400');
		await modal.getByRole('button', { name: /Create challenge/ }).click();

		await expect(modal.getByRole('alert')).toContainText(/At most \d+ active days/);
		// Still on the list route: nothing was inserted, so nothing navigated.
		await expect(page).toHaveURL(/\/challenges$/);
	});

	test('a zero goal is refused inline — it would complete for everyone', async ({ page }) => {
		await page.goto('/challenges');
		await page.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(`e2e-zero-goal ${Date.now()}`);
		await modal.getByLabel(/Goal/).fill('0');
		await modal.getByRole('button', { name: /Create challenge/ }).click();

		await expect(modal.getByRole('alert')).toContainText(/above zero/);
		await expect(page).toHaveURL(/\/challenges$/);
	});
});
