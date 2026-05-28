import { expect, test } from '@playwright/test';

import { setClubMemberRole } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * event_organiser is a delegated role that the DB RLS (is_event_organiser)
 * already permits to manage events. The web guards on /clubs/[slug] (the
 * "New event" button) and the standalone /clubs/[slug]/events/new route used
 * to gate on owner/admin only, locking the delegated organiser out of the one
 * deep-linkable create path. These tests pin both the positive (organiser can
 * reach the create surface) and negative (a plain member is still redirected).
 *
 * USER_B is a seeded active 'member' of Richmond Run Club (c1111…001). Each
 * test mutates that role via service-role and reverts in afterEach.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug] — event_organiser create access', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.afterEach(async () => {
		await setClubMemberRole(RICHMOND_CLUB_ID, USER_B.id, 'member');
	});

	test('event_organiser can open the standalone create-event page', async ({ page }) => {
		await setClubMemberRole(RICHMOND_CLUB_ID, USER_B.id, 'event_organiser');

		await page.goto('/clubs/richmond-run-club/events/new');

		// The page must NOT redirect back to the club home; the New-event
		// header + EventEditor stay mounted.
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});
		expect(new URL(page.url()).pathname).toBe('/clubs/richmond-run-club/events/new');
	});

	test('event_organiser sees the New-event button on the club page', async ({ page }) => {
		await setClubMemberRole(RICHMOND_CLUB_ID, USER_B.id, 'event_organiser');

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: /New event/ })).toBeVisible();
	});

	test('a plain member is still redirected away from the create page', async ({ page }) => {
		// Role left at the seeded 'member' — the guard must bounce them.
		await page.goto('/clubs/richmond-run-club/events/new');
		await page.waitForURL('**/clubs/richmond-run-club', { timeout: 10_000 });
		expect(new URL(page.url()).pathname).toBe('/clubs/richmond-run-club');
	});
});
