import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug] — admin promotes a member's role.
 *
 * The members tab on /clubs/[slug] exposes a role <select> on every
 * non-owner row when the viewer is an admin (the per-row select is
 * gated on `isAdmin && m.role !== 'owner'`). The handler calls
 * `setMemberRole` (RPC-backed) and rolls back the dropdown on
 * failure. This pins the promote/demote round-trip.
 *
 * Plant morgan as an active member first via service-role so the
 * test isn't dependent on the join saga running in the same suite.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — admin role change', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// Insert morgan as a plain member of Sydney Run Club so the
		// admin's role-change UI has someone to operate on.
		const admin = getAdminClient();
		await admin.from('club_members').upsert(
			{
				club_id: SYDNEY_RUN_CLUB_ID,
				user_id: USER_C_PRO.id,
				role: 'member',
				status: 'active'
			},
			{ onConflict: 'club_id,user_id' }
		);
	});

	test.afterEach(async () => {
		// Sweep — ensures the planted row never lingers, regardless of
		// whether the test asserted before or after a failure.
		try {
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', SYDNEY_RUN_CLUB_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('owner promotes a member to admin via the role dropdown — change persists across reload', async ({
		page
	}) => {
		await page.goto('/clubs/sydney-run-club');
		await page.getByRole('button', { name: /^Members/ }).click();

		const morganRow = page.locator('.member-list .member', {
			hasText: 'Morgan'
		});
		await expect(morganRow).toBeVisible({ timeout: 10_000 });

		// Starting role is 'member' (planted by beforeEach).
		const select = morganRow.locator('select.role-select');
		await expect(select).toHaveValue('member');

		await select.selectOption('admin');

		// Reload → server-side state agrees, the dropdown still reads 'admin'.
		await page.reload();
		await page.getByRole('button', { name: /^Members/ }).click();
		const morganAfter = page.locator('.member-list .member', {
			hasText: 'Morgan'
		});
		await expect(morganAfter.locator('select.role-select'))
			.toHaveValue('admin', { timeout: 10_000 });
	});
});
