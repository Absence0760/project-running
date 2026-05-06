import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Clubs journey — full lifecycle of a brand-new club, walked through
 * every surface a club appears on:
 *   1. Create via /clubs/new (ClubEditor → clubs row + owner
 *      club_members row via enroll_club_owner_trigger).
 *   2. Lands on /clubs/[slug] with the name as h1.
 *   3. Post a message on the Feed tab via the post composer; verify
 *      the post body appears in the post list (createClubPost +
 *      realtime push or list re-fetch).
 *   4. /clubs My-tab includes the new club in the grid.
 *   5. Delete via the slug-page admin button → ConfirmDialog →
 *      navigates back to /clubs, the club is gone from the list.
 *
 * Heavier than the batch-8 detail.spec.ts CRUD round-trip because it
 * additionally exercises the post-composer + the My-tab list refresh.
 */

const uniqueName = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('clubs journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('create → post → /clubs lists it → delete → /clubs reverts', async ({
		page
	}) => {
		const name = uniqueName('e2e-journey-club');
		const postBody = `Hello from journey-test ${Date.now()}`;

		// ── Create ─────────────────────────────────────────────────
		await test.step('create the club via /clubs/new', async () => {
			await page.goto('/clubs/new');
			await page.locator('input[type="text"]').first().fill(name);
			await page.getByRole('button', { name: 'Create club' }).click();
			// Slug is generated server-side; anchor on a digit so the
			// regex doesn't match /clubs/new still in flight.
			await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, { timeout: 10_000 });
			await expect(page.getByRole('heading', { level: 1, name }))
				.toBeVisible({ timeout: 10_000 });
		});

		// ── Post on Feed tab ───────────────────────────────────────
		await test.step('post a message on the Feed tab', async () => {
			// Feed is the default tab. Composer lives at .post-form
			// with a textarea that has the seeded placeholder
			// "Share an update with members…".
			const textarea = page.locator('.post-form textarea').first();
			await expect(textarea).toBeVisible({ timeout: 10_000 });
			await textarea.fill(postBody);
			await page.locator('.post-form button[type="submit"]').click();

			// The post body should appear in the posts list. The
			// realtime channel pushes the new row + fetchClubPosts
			// re-runs after createClubPost resolves.
			await expect(page.getByText(postBody)).toBeVisible({ timeout: 10_000 });
		});

		// ── /clubs My tab includes it ──────────────────────────────
		await test.step('/clubs My-tab includes the new club', async () => {
			await page.goto('/clubs');
			await expect(
				page.getByRole('heading', { name, exact: true })
			).toBeVisible({ timeout: 10_000 });
		});

		// ── Delete + verify the list reverts ───────────────────────
		await test.step('delete the club from /clubs/[slug]', async () => {
			// Drill back into the detail page via the My-tab card link.
			await page.getByRole('link', { name }).click();
			await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, { timeout: 10_000 });

			await page.getByRole('button', { name: 'Delete club' }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete club' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await page.waitForURL(/\/clubs(\?.*)?$/, { timeout: 10_000 });
		});

		await test.step('/clubs no longer lists the deleted club', async () => {
			await expect(
				page.getByRole('heading', { name, exact: true })
			).toHaveCount(0);
		});
	});
});
