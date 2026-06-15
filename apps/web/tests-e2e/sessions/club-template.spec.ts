import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session planner P3 (session_planner.md) — club-published session templates.
 *
 * USER_A owns Richmond Run Club (admin), so they can publish a personal session
 * plan to it and the club's Templates tab surfaces it with an Adopt action that
 * clones it back into a fresh personal plan (the clone_session_template RPC).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/sessions — club session templates', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let sourcePlanId: string | null = null;
	const title = `e2e-session-template ${Date.now()}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title })
			.select('id')
			.single();
		sourcePlanId = (data as { id: string }).id;
		await admin.from('session_plan_items').insert({
			plan_id: sourcePlanId,
			position: 0,
			movement_name: 'Sun Salutation',
			kind: 'flow',
			duration_s: 60
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		// The source plan, the published club copy, and any adopted clone all
		// share the title — sweep them all.
		await admin.from('session_plans').delete().eq('title', title);
	});

	test('publish a session to a club, then adopt it from the club Templates tab', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Publish from the session detail page.
		await page.goto(`/sessions/${sourcePlanId}`);
		const publishRow = page.locator('.publish-row');
		await expect(publishRow).toBeVisible({ timeout: 10_000 });
		await publishRow.locator('select').selectOption(RICHMOND_CLUB_ID);
		await page.getByTestId('session-publish').click();
		await expect(publishRow.locator('select')).toHaveValue('', { timeout: 10_000 });

		// A club-owned copy now exists.
		const { data: clubCopies } = await admin
			.from('session_plans')
			.select('id')
			.eq('club_id', RICHMOND_CLUB_ID)
			.eq('title', title);
		expect(clubCopies?.length).toBe(1);

		// It surfaces on the club's Templates tab, and Adopt clones it.
		await page.goto('/clubs/richmond-run-club?tab=templates');
		const adoptBtn = page.getByTestId('session-template-adopt').first();
		await expect(adoptBtn).toBeVisible({ timeout: 10_000 });
		await adoptBtn.click();

		// Adopt keeps the user on the club Templates tab (it does NOT yank them
		// to the orphaned /sessions detail page) — the adopted copy lands in their
		// own plans, reachable from the Gym → Sessions link.
		await expect(page.getByText('Session added to your plans.')).toBeVisible({ timeout: 10_000 });
		await expect(page).toHaveURL(/\/clubs\/richmond-run-club\?tab=templates$/);

		const { data: personalClones } = await admin
			.from('session_plans')
			.select('id')
			.eq('author_id', USER_A.id)
			.is('club_id', null)
			.eq('title', title);
		// The original source + the adopted clone are both personal + club-less.
		expect((personalClones?.length ?? 0)).toBeGreaterThanOrEqual(2);
	});
});
