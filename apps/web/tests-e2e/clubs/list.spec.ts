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

	test('Browse search narrows public clubs to a name match', async ({
		page
	}) => {
		// Browse search filters via browseClubs(search) — server-side
		// ilike on name + location. Typing "Tempo" should leave only
		// "Tempo Tuesday" visible from the seeded public clubs.
		await page.goto('/clubs');
		await page.getByRole('tab', { name: 'Browse', exact: true }).click();

		// Wait for browse to settle with multiple cards.
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByPlaceholder(/Search by name/).fill('Tempo');

		// Tempo Tuesday remains; Sydney Run Club gone (no match for Tempo).
		await expect(
			page.getByRole('heading', { name: 'Tempo Tuesday' })
		).toBeVisible({ timeout: 5_000 });
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toHaveCount(0);

		// Clear the search so the rest of the suite sees the full
		// browse list.
		await page.getByPlaceholder(/Search by name/).fill('');
	});

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

		await page.getByRole('tab', { name: 'Browse', exact: true }).click();
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

		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Drill into the slug-routed detail page.
		await page.getByRole('link', { name: /Sydney Run Club/ }).click();
		await expect(page).toHaveURL(/\/clubs\/sydney-run-club/);
	});

	test('My-clubs tab lists Friends of Jared (owner sees their private clubs here)', async ({
		page
	}) => {
		// Inverse of the Browse-hides-private test: in My clubs, the
		// owner sees their own private clubs. Pinning this catches a
		// regression that filtered private clubs out of My clubs too.
		await page.goto('/clubs');
		await expect(
			page.getByRole('heading', { name: 'Friends of Jared' })
		).toBeVisible({ timeout: 10_000 });
	});

	test('Create club button is reachable from /clubs', async ({ page }) => {
		await page.goto('/clubs');
		await expect(
			page.getByRole('link', { name: /Create club/ }).or(
				page.getByRole('button', { name: /Create club/ })
			)
		).toBeVisible({ timeout: 10_000 });
	});

	test('Browse search clearing the box restores the full club list', async ({
		page
	}) => {
		// Companion to the search-narrows test above. The reactive
		// $effect on the search box re-runs browseClubs(search='') when
		// the input clears. A regression that left a stale memoised
		// result would surface here as a list that doesn't grow back
		// when the user clears their query.
		await page.goto('/clubs');
		await page.getByRole('tab', { name: 'Browse', exact: true }).click();

		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByPlaceholder(/Search by name/).fill('Tempo');
		// Sydney Run Club is hidden under the Tempo filter.
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toHaveCount(0);

		// Clear the search; Sydney Run Club returns.
		await page.getByPlaceholder(/Search by name/).fill('');
		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });
	});
});
