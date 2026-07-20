import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] Members tab — roster pagination.
 *
 * `fetchClubMembers` pages at ROSTER_PAGE_SIZE (50) rather than fetching
 * the full, ever-growing roster on every view (issue #342). This seeds a
 * club with well over one page of members and asserts the tab shows the
 * first page + a "Load more" affordance, then reveals the rest on click —
 * so a member past page 1 is reachable, not silently dropped.
 *
 * Before the fix the whole roster rendered at once (no Load more button,
 * >50 rows on first paint), so the page-1 assertions fail.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const SEED_COUNT = 60;
const PAGE_SIZE = 50;

// Members seeded with a fixed, long-past joined_at so they sort ahead of
// the club owner (secondary key user_id) and the ordering is deterministic:
// PgMember 00..49 land on page 1, PgMember 50..59 on page 2.
const seededUserIds: string[] = [];

test.describe.serial('/clubs/[slug] — members pagination', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const rows: { club_id: string; user_id: string; role: string; status: string; joined_at: string }[] =
			[];
		for (let i = 0; i < SEED_COUNT; i++) {
			const email = `pg-member-${i}-${Date.now()}@test.com`;
			const { data, error } = await admin.auth.admin.createUser({
				email,
				password: 'testtest',
				email_confirm: true
			});
			if (error || !data?.user) {
				throw new Error(`members-pagination: createUser #${i} failed: ${error?.message}`);
			}
			const id = data.user.id;
			seededUserIds.push(id);
			await admin.from('user_profiles').upsert({
				id,
				display_name: `PgMember ${String(i).padStart(2, '0')}`,
				preferred_unit: 'km',
				subscription_tier: 'free',
				onboarded_at: new Date().toISOString()
			});
			rows.push({
				club_id: RICHMOND_CLUB_ID,
				user_id: id,
				role: 'member',
				status: 'active',
				joined_at: new Date(Date.UTC(2000, 0, 1) + i * 60_000).toISOString()
			});
		}
		const { error: insErr } = await admin.from('club_members').insert(rows);
		if (insErr) throw new Error(`members-pagination: club_members insert failed: ${insErr.message}`);
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of seededUserIds) {
			try {
				await admin.from('club_members').delete().eq('club_id', RICHMOND_CLUB_ID).eq('user_id', id);
				await admin.auth.admin.deleteUser(id);
			} catch (_) {
				/* best-effort sweep */
			}
		}
	});

	test('first page caps at 50 with a Load more affordance; click reveals the rest', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Members/ }).click();

		const rows = page.locator('.member-list .member');
		await expect(rows.first()).toBeVisible({ timeout: 10_000 });

		// Page 1 is exactly one page — not the whole roster.
		await expect(rows).toHaveCount(PAGE_SIZE);
		await expect(page.getByText('PgMember 00')).toBeVisible();
		await expect(page.getByText('PgMember 55')).toHaveCount(0);

		const loadMore = page.getByRole('button', { name: /load more/i });
		await expect(loadMore).toBeVisible();
		await loadMore.click();

		// Page 2 appends the remaining members.
		await expect(page.getByText('PgMember 55')).toBeVisible();
		expect(await rows.count()).toBeGreaterThan(PAGE_SIZE);
	});
});
