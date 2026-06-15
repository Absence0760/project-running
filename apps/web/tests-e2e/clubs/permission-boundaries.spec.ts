import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug] — owner vs admin vs plain-member permission boundaries.
 *
 * The UI gates every management affordance on `isAdmin`
 * (viewer_role ∈ {owner, admin}) or `canManageEvents` (+ event_organiser).
 * This file pins the NEGATIVE side for a plain member and the POSITIVE
 * side for a promoted admin who is NOT the owner — the cases the
 * single-owner specs (detail/members) don't cover:
 *
 *   - a plain member sees the club, the feed composer, and the members
 *     list, but NONE of: Edit club, Delete club, New event, the
 *     pending-requests panel, the invite-link panel, per-row role
 *     selects, or the Remove-member button.
 *   - a promoted admin (role='admin', not owner) DOES see the admin
 *     affordances — except Delete club, which stays owner-only.
 *
 * Alex (USER_B) is a seeded active member of Richmond Run Club. Morgan
 * (USER_C_PRO) is planted as a non-owner admin for the admin-positive
 * test, then swept.
 */

const RICHMOND_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — plain member cannot reach admin affordances', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('member sees feed composer + members list but no management controls', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Active membership → the post composer mounts.
		await expect(page.locator('.post-form textarea').first()).toBeVisible({
			timeout: 10_000
		});

		// None of the admin/owner action buttons in the hero.
		await expect(page.getByRole('button', { name: 'Edit club' })).toHaveCount(0);
		await expect(page.getByRole('button', { name: 'Delete club' })).toHaveCount(0);
		await expect(page.getByRole('button', { name: /New event/ })).toHaveCount(0);

		// No admin panels (pending requests, invite link).
		await expect(
			page.locator('section.admin-card', { hasText: /Pending requests/ })
		).toHaveCount(0);
		await expect(
			page.locator('section.admin-card', { hasText: /Invite link/ })
		).toHaveCount(0);

		// Members tab: the owner row shows, but NO role <select> and NO
		// Remove-member button anywhere (those are isAdmin-gated).
		await page.getByRole('tab', { name: /^Members/ }).click();
		const memberList = page.locator('.member-list');
		await expect(memberList).toBeVisible({ timeout: 10_000 });
		await expect(memberList.locator('select.role-select')).toHaveCount(0);
		await expect(
			page.getByRole('button', { name: 'Remove member' })
		).toHaveCount(0);
	});

	test('member is offered the Report-club affordance (the non-admin escape hatch)', async ({
		page
	}) => {
		// The flag/report button is rendered for any logged-in non-admin.
		// Pins that a plain member isn't left with zero affordances — they
		// can report, just not manage.
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('button', { name: 'Report this club' })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/clubs/[slug] — promoted (non-owner) admin gets admin powers but not Delete', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('club_members').upsert(
			{
				club_id: RICHMOND_ID,
				user_id: USER_C_PRO.id,
				role: 'admin',
				status: 'active'
			},
			{ onConflict: 'club_id,user_id' }
		);
		// Richmond is open-policy, so plant a pending requester (alex would
		// already be active here; use a synthetic pending row on a fresh
		// user is overkill — instead flip the invite token so the invite
		// panel renders for the admin-positive assertion).
		await admin
			.from('clubs')
			.update({ invite_token: 'e2eadminpanel00000000000000000aa' })
			.eq('id', RICHMOND_ID);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		try {
			await admin
				.from('club_members')
				.delete()
				.eq('club_id', RICHMOND_ID)
				.eq('user_id', USER_C_PRO.id);
			await admin
				.from('clubs')
				.update({ invite_token: null })
				.eq('id', RICHMOND_ID);
		} catch (_) {
			/* best-effort */
		}
	});

	test('a non-owner admin sees Edit club + New event + invite panel, but NOT Delete club', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Admin affordances present.
		await expect(
			page.getByRole('button', { name: 'Edit club' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('button', { name: /New event/ }).first()
		).toBeVisible();
		await expect(
			page.locator('section.admin-card', { hasText: /Invite link/ })
		).toBeVisible({ timeout: 10_000 });

		// Delete club is OWNER-ONLY — a non-owner admin must NOT see it.
		await expect(
			page.getByRole('button', { name: 'Delete club' })
		).toHaveCount(0);

		// Members tab: the admin gets role selects on non-owner rows.
		await page.getByRole('tab', { name: /^Members/ }).click();
		await expect(page.locator('.member-list')).toBeVisible({ timeout: 10_000 });
		// At least the owner row is present; the role-select shows on
		// non-owner rows (e.g. alex) — assert at least one exists.
		await expect(
			page.locator('.member-list select.role-select').first()
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/clubs/[slug] — role demote round-trip (admin → member)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// Plant alex... no, alex is seeded. Plant morgan as an admin so the
		// owner can demote her back to member through the dropdown.
		await getAdminClient().from('club_members').upsert(
			{
				club_id: RICHMOND_ID,
				user_id: USER_C_PRO.id,
				role: 'admin',
				status: 'active'
			},
			{ onConflict: 'club_id,user_id' }
		);
	});

	test.afterEach(async () => {
		try {
			await getAdminClient()
				.from('club_members')
				.delete()
				.eq('club_id', RICHMOND_ID)
				.eq('user_id', USER_C_PRO.id);
		} catch (_) {
			/* best-effort */
		}
	});

	test('owner demotes an admin back to member; the change persists across reload', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Members/ }).click();

		const morganRow = page.locator('.member-list .member', {
			hasText: 'Morgan'
		});
		await expect(morganRow).toBeVisible({ timeout: 10_000 });
		const select = morganRow.locator('select.role-select');
		await expect(select).toHaveValue('admin');

		await select.selectOption('member');

		await page.reload();
		await page.getByRole('tab', { name: /^Members/ }).click();
		const after = page.locator('.member-list .member', { hasText: 'Morgan' });
		await expect(after.locator('select.role-select')).toHaveValue('member', {
			timeout: 10_000
		});

		// DB sanity.
		const { data } = await getAdminClient()
			.from('club_members')
			.select('role')
			.eq('club_id', RICHMOND_ID)
			.eq('user_id', USER_C_PRO.id)
			.single();
		expect(data?.role).toBe('member');
	});
});
