import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Session planner P3 (session_planner.md) — create a club-owned session template
 * directly from the club Templates tab, rather than building a personal plan
 * first and publishing it.
 *
 * USER_A owns Richmond Run Club (admin), so the admin-only "New session
 * template" front door is visible and the SessionPlanEditor mounted there writes
 * a club_id-set session_plans row in one step.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs — create session template from Templates tab', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdTitles: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const title of createdTitles.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('title', title);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('admin creates a club-owned session template inline; it lands club_id-set and lists', async ({
		page
	}) => {
		const title = `e2e-club-session-create ${Date.now()}`;
		createdTitles.push(title);

		await page.goto('/clubs/richmond-run-club?tab=templates');

		// The admin-only front door.
		const newBtn = page.getByTestId('new-session-template');
		await expect(newBtn).toBeVisible({ timeout: 10_000 });
		await newBtn.click();

		// The editor mounts inline (not in a modal) — scope all fields to it.
		const editor = page.locator('.session-editor');
		await expect(editor).toBeVisible({ timeout: 5_000 });
		await editor.getByLabel('Title', { exact: true }).fill(title);
		const card = editor.locator('.item-card').first();
		await card.getByRole('combobox', { name: 'Movement' }).fill('Sun Salutation');
		await card.getByLabel('Seconds', { exact: true }).fill('60');

		await editor.getByRole('button', { name: 'Save', exact: true }).click();

		// On save the editor closes and the new template lists on the same tab —
		// no navigation away from the club.
		await expect(editor).toBeHidden({ timeout: 10_000 });
		await expect(page.getByRole('link', { name: title })).toBeVisible({ timeout: 10_000 });

		// It persisted as a club-owned plan (club_id set, author = the admin).
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('session_plans')
			.select('id, club_id, author_id')
			.eq('title', title);
		expect(rows?.length).toBe(1);
		expect(rows?.[0].club_id).toBe(RICHMOND_CLUB_ID);
		expect(rows?.[0].author_id).toBe(USER_A.id);
	});
});
