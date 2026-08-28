import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * /challenges/[id] — a club admin who is NOT the creator can manage a
 * club-anchored challenge (issue #336).
 *
 * The backend RLS grants update/delete to `creator_id = auth.uid() or
 * (club_id is not null and is_club_admin(club_id))`, so admin turnover
 * doesn't orphan a club challenge. This pins that the UI now surfaces
 * Edit + Delete to that second admin — a right the server already grants.
 *
 * USER_A (owner of Richmond Run Club) creates the challenge; Morgan
 * (USER_C_PRO) is planted as a non-owner admin of the same club, loads
 * the detail page, and must see + be able to use Edit and Delete.
 */

const RICHMOND_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/challenges/[id] — non-creator club admin can manage', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	let challengeId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('club_members').upsert(
			{ club_id: RICHMOND_ID, user_id: USER_C_PRO.id, role: 'admin', status: 'active' },
			{ onConflict: 'club_id,user_id' }
		);
		const now = Date.now();
		const { data, error } = await admin
			.from('challenges')
			.insert({
				creator_id: USER_A.id,
				club_id: RICHMOND_ID,
				title: `e2e-club-challenge ${now}`,
				metric: 'distance',
				scope: 'individual',
				goal_value: 100000,
				starts_at: new Date(now - 86_400_000).toISOString(),
				ends_at: new Date(now + 7 * 86_400_000).toISOString()
			})
			.select('id')
			.single();
		if (error) throw new Error(error.message);
		challengeId = (data as { id: string }).id;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (challengeId) {
			await admin.from('challenges').delete().eq('id', challengeId);
			challengeId = null;
		}
		await admin
			.from('club_members')
			.delete()
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_C_PRO.id);
	});

	test('a second club admin sees Edit + Delete and can delete the challenge', async ({ page }) => {
		await page.goto(`/challenges/${challengeId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		// The management controls the pre-fix UI only showed the creator.
		await expect(page.getByRole('button', { name: 'Edit challenge' })).toBeVisible({
			timeout: 10_000
		});
		const deleteBtn = page.getByRole('button', { name: /^Delete$/ });
		await expect(deleteBtn).toBeVisible();

		// Functional: the delete goes through (RLS permits the club admin).
		await deleteBtn.click();
		const dialog = page.getByRole('dialog', { name: /Delete challenge\?/ });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: /^Delete$/ }).click();

		await expect(page).toHaveURL(/\/challenges$/, { timeout: 10_000 });

		const data = await readRows(
			'challenges by id',
			getAdminClient()
				.from('challenges')
				.select('id')
				.eq('id', challengeId!)
		);
		expect(data).toEqual([]);
		challengeId = null;
	});
});
