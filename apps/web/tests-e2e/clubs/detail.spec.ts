import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] — club detail. Split out from clubs/list.spec.ts now
 * that the surface has its own depth (Members tab + create/delete
 * round-trip via /clubs/new).
 *
 * Cross-user joins + member-role transitions are exercised in
 * cross-user/sagas/club-join.spec.ts; everything here is owner-only.
 *
 * Future depth: events tab (RSVP, recurrence), post composer
 * (compose + edit + delete), private invite-link rotate, role
 * transfer / remove member.
 */

const uniqueName = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/clubs/[slug]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Members tab on Sydney Run Club lists runner as the owner', async ({
		page
	}) => {
		// `enroll_club_owner_trigger` writes the owner row into
		// club_members on insert — the Members tab queries that table
		// via fetchClubMembers. The owner has role='owner'; the test
		// targets that role badge.
		await page.goto('/clubs/sydney-run-club');

		// Members tab — there's exactly one tab named "Members" on
		// this page.
		await page
			.getByRole('button', { name: 'Members', exact: true })
			.click();

		// Runner's display_name (Jared Howard, per seed) must surface in
		// the .member-list. Strong tag inside the link, so anchor the
		// query on the role text.
		const memberList = page.locator('.member-list');
		await expect(memberList).toBeVisible({ timeout: 10_000 });
		await expect(memberList.getByText('Jared Howard')).toBeVisible();
		await expect(memberList.getByText('owner', { exact: true })).toBeVisible();
	});

	test('club CRUD round-trip via /clubs/new → /clubs/[slug] → Delete club', async ({
		page
	}) => {
		// /clubs/new mounts <ClubEditor>. Filling Name + submitting
		// creates a clubs row + the owner club_members row (via the
		// enroll_club_owner_trigger), then navigates to /clubs/<slug>.
		// We delete it from the slug page so the suite stays
		// idempotent.
		const name = uniqueName('e2e-club');

		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);

		await page.getByRole('button', { name: 'Create club' }).click();

		// Slug is generated server-side from the name. The waitForURL
		// regex anchors on a digit so we don't accidentally match
		// /clubs/new still in flight.
		await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, {
			timeout: 10_000
		});

		// Header h1 = the club name; proves the slug page mounted with
		// the right row.
		await expect(
			page.getByRole('heading', { level: 1, name })
		).toBeVisible({ timeout: 10_000 });

		// ── Delete ──
		await page.getByRole('button', { name: 'Delete club' }).click();
		await expect(page.locator('.modal', { hasText: 'Delete club' }))
			.toBeVisible({ timeout: 5_000 });
		await page
			.locator('.modal')
			.getByRole('button', { name: 'Delete', exact: true })
			.click();

		await page.waitForURL(/\/clubs(\?.*)?$/, { timeout: 10_000 });

		// Switch to My-clubs (default) — the deleted club must not
		// appear.
		await expect(
			page.getByRole('heading', { name, exact: true })
		).toHaveCount(0);
	});
});
