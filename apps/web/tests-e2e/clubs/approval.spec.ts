import { expect, test } from '@playwright/test';

import { setClubMemberStatus } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /clubs/[slug] — admin approves a pending join request.
 *
 * Tempo Tuesday is seeded with `join_policy='request'`; alex is
 * pre-enrolled with `status='pending'` so the admin pending-requests
 * panel has something to act on without needing a saga that drives
 * Alex through the join request flow.
 *
 * Owner runner approves alex → alex flips to active → pending count
 * drops to 0. afterEach restores alex to pending so the seed shape
 * is intact for downstream tests.
 */

const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

test.describe('/clubs/[slug] — approval flow', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		try {
			await setClubMemberStatus(TEMPO_TUESDAY_ID, USER_B.id, 'pending');
		} catch (_) {
			/* best-effort */
		}
	});

	test('admin approves the pending request → member moves to active, pending panel clears', async ({
		page
	}) => {
		await page.goto('/clubs/tempo-tuesday');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Tempo Tuesday' })
		).toBeVisible({ timeout: 10_000 });

		// Pending requests panel renders for admins when there's at
		// least one pending member. Alex is the seeded one.
		const pendingPanel = page.locator('section.admin-card', {
			hasText: /Pending requests/
		});
		await expect(pendingPanel).toBeVisible({ timeout: 10_000 });
		await expect(pendingPanel).toContainText('Pending requests (1)');
		await expect(pendingPanel.locator('.pending-row')).toContainText('Alex Chen');

		// Approve. The handler calls approveMember (RPC) which flips
		// `status` to 'active' on the club_members row.
		await pendingPanel.getByRole('button', { name: 'Approve' }).click();

		// Panel disappears (no more pending requests) — the {#if
		// pending.length > 0} guard hides the whole section.
		await expect(pendingPanel).toHaveCount(0, { timeout: 10_000 });

		// Alex now appears in the Members tab (member-list renders a
		// .member row per active club_members row).
		await page.getByRole('button', { name: /^Members/ }).click();
		await expect(
			page.locator('.member-list .member', { hasText: 'Alex Chen' })
		).toBeVisible({ timeout: 10_000 });
	});
});
