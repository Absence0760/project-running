import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug] — admin bulk-approves pending join requests (persona round-5
 * parkrun-owner). Tempo Tuesday uses join_policy='request'. Plant two pending
 * members (alex + the pro user), confirm the "Approve all" button appears only
 * when there's more than one pending request, click it, and assert both flip
 * to active in one shot. afterEach restores the seed shape.
 */

const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

test.describe('/clubs/[slug] — bulk approve', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		for (const uid of [USER_B.id, USER_C_PRO.id]) {
			await getAdminClient()
				.from('club_members')
				.upsert(
					{ club_id: TEMPO_TUESDAY_ID, user_id: uid, role: 'member', status: 'pending' },
					{ onConflict: 'club_id,user_id' }
				);
		}
	});

	test.afterEach(async () => {
		try {
			await getAdminClient()
				.from('club_members')
				.upsert(
					{ club_id: TEMPO_TUESDAY_ID, user_id: USER_B.id, role: 'member', status: 'pending' },
					{ onConflict: 'club_id,user_id' }
				);
			// USER_C_PRO is not part of the seed for this club — drop the synthetic row.
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', TEMPO_TUESDAY_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('Approve all flips every pending member to active in one action', async ({ page }) => {
		await page.goto('/clubs/tempo-tuesday');
		await expect(page.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })).toBeVisible({
			timeout: 10_000
		});

		const pendingPanel = page.locator('section.admin-card', { hasText: /Pending requests/ });
		await expect(pendingPanel).toBeVisible({ timeout: 10_000 });
		await expect(pendingPanel).toContainText('Pending requests (2)');

		await pendingPanel.getByRole('button', { name: 'Approve all' }).click();

		// No pending rows left → the whole section is hidden.
		await expect(pendingPanel).toHaveCount(0, { timeout: 10_000 });

		const { data } = await getAdminClient()
			.from('club_members')
			.select('user_id, status')
			.eq('club_id', TEMPO_TUESDAY_ID)
			.in('user_id', [USER_B.id, USER_C_PRO.id]);
		expect((data ?? []).every((r) => r.status === 'active')).toBe(true);
		expect((data ?? []).length).toBe(2);
	});

	test('Approve all is hidden when only one request is pending', async ({ page }) => {
		// Drop the pro user so just alex is pending.
		await getAdminClient()
			.from('club_members')
			.delete()
			.eq('club_id', TEMPO_TUESDAY_ID)
			.eq('user_id', USER_C_PRO.id);

		await page.goto('/clubs/tempo-tuesday');
		const pendingPanel = page.locator('section.admin-card', { hasText: /Pending requests/ });
		await expect(pendingPanel).toContainText('Pending requests (1)', { timeout: 10_000 });
		await expect(pendingPanel.getByRole('button', { name: 'Approve all' })).toHaveCount(0);
		await expect(pendingPanel.getByRole('button', { name: 'Approve' })).toBeVisible();
	});
});
