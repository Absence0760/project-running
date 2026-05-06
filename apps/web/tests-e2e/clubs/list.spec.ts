import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs — tabbed list (My clubs / Browse). My-clubs surfaces the
 * authed user's club_members rows (owner included via
 * enroll_club_owner_trigger). Drills into /clubs/[slug] in the same
 * test until a dedicated detail file is split out.
 *
 * Future depth: events tab, members tab, post composer, club editor,
 * private invite-link join (/clubs/join/[token]).
 */

test.describe('/clubs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Browse tab shows public clubs + hides private "Friends of Jared"', async ({
		page
	}) => {
		// Seeded clubs: Sydney Run Club (public open), Tempo Tuesday
		// (public request), Friends of Jared (private invite). Browse
		// fetches via browseClubs(search) which filters on
		// is_public=true — private clubs must NOT appear here even
		// for the owner. (My clubs tab IS the place owners see their
		// private clubs.)
		await page.goto('/clubs');
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: /Browse/, exact: true }).click();
		// Wait for the browse fetch to settle.
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('heading', { name: 'Tempo Tuesday' })
		).toBeVisible();
		// Private club must NOT surface in Browse.
		await expect(
			page.getByRole('heading', { name: 'Friends of Jared' })
		).toHaveCount(0);
	});

	test('seeded Sydney Run Club renders + drill into slug detail', async ({
		page
	}) => {
		// Runner owns three seeded clubs (Sydney Run Club / Tempo
		// Tuesday / Friends of Jared). Empty state would mean either
		// fetchMyClubs broke or the auth-race patched in /clubs/+page
		// regressed (see docs/testing.md production-bugs § /clubs).
		await page.goto('/clubs');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Drill into the slug-routed detail page.
		await page.getByRole('link', { name: /Sydney Run Club/ }).click();
		await expect(page).toHaveURL(/\/clubs\/sydney-run-club/);
		await page.waitForLoadState('networkidle');
	});
});
