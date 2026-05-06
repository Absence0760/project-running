import { expect, test } from '@playwright/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * /u/[id] — public user profile.
 *
 * Renders display_name, follower / following counts, recent public
 * runs in a card grid (mounting RunShareView in a modal on click),
 * and a Follow toggle (cross-user/follows.spec.ts covers the toggle
 * round-trip). This file holds the "page renders + tabs work + a
 * non-self viewer's view is correct" checks.
 *
 * Future depth: Followers + Following tabs render the seeded edges,
 * notifications tab gating (only visible to isSelf), the user's
 * runs grid showing Alex's recent public runs vs runner's pinned
 * one.
 */

test.describe('/u/[id] — viewing another user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('runner views alex profile: display_name + Follow button visible', async ({
		page
	}) => {
		// USER_A (runner) follows alex per seed, so alex's profile
		// shows the "Following" state on the toggle (not "Follow").
		await page.goto(`/u/${USER_B.id}`);

		// h1 reflects display_name. Pinned to "Alex Chen" in seed.sql.
		await expect(
			page.getByRole('heading', { name: 'Alex Chen', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Follow button is present (alex isn't isSelf for runner).
		// Runner already follows alex, so it reads "Following".
		await expect(page.locator('button.btn-follow')).toContainText('Following');

		// Three count buttons render: Runs / Followers / Following.
		// Clicking switches the tab; we just check the chrome — the
		// cross-user/follows spec exercises the toggle round-trip.
		await expect(page.locator('button.count')).toHaveCount(3);
		await expect(
			page.locator('button.count', { hasText: 'Followers' })
		).toBeVisible();
		await expect(
			page.locator('button.count', { hasText: 'Following' })
		).toBeVisible();
	});
});

test.describe('/u/[id] — viewing self', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('runner views own profile: no Follow button, notifications tab gated to self', async ({
		page
	}) => {
		// `isSelf = $derived(auth.user?.id === userId)` hides the
		// Follow button on your own profile and exposes the
		// Notifications tab. Pins both gates.
		await page.goto(`/u/${USER_A.id}`);

		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// No Follow button on own profile.
		await expect(page.locator('button.btn-follow')).toHaveCount(0);

		// Notifications tab — only present for isSelf. The .bell-btn
		// in the sidebar has the same accessible name; scope to the
		// page's .tabs container to disambiguate.
		await expect(
			page.locator('.tabs button.tab', { hasText: 'Notifications' })
		).toBeVisible();
	});
});
