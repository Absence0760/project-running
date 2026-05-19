import { expect, test } from '@playwright/test';

import { resetRateLimit } from '../fixtures/local-supabase';
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

	test.beforeEach(async () => {
		// 5 clubs/hour cap (migration 20260907_001) is shared across
		// every test file that creates clubs as USER_A in this shard.
		// new.spec.ts can push the counter to 5 before this file runs;
		// defensively reset so this file's lone Create-club test isn't
		// at the mercy of shard-distribution ordering.
		await resetRateLimit(USER_A.id, 'create_club');
	});

	test('Members tab on Sydney Run Club lists runner as the owner', async ({
		page
	}) => {
		// `enroll_club_owner_trigger` writes the owner row into
		// club_members on insert — the Members tab queries that table
		// via fetchClubMembers. The owner has role='owner'; the test
		// targets that role badge.
		await page.goto('/clubs/sydney-run-club');

		// Members tab — the tab label now includes the member count
		// (e.g. "Members (2)"), so anchor on the prefix via the
		// role="tab" ARIA contract.
		await page
			.getByRole('tab', { name: /^Members/ })
			.click();

		// Runner's display_name (Jared Howard, per seed) must surface in
		// the .member-list. Strong tag inside the link, so anchor the
		// query on the role text.
		const memberList = page.locator('.member-list');
		await expect(memberList).toBeVisible({ timeout: 10_000 });
		await expect(memberList.getByText('Jared Howard')).toBeVisible();
		await expect(memberList.getByText('owner', { exact: true })).toBeVisible();
	});

	test('Routes tab on Sydney Run Club: admin sees "+ New route" + "Transfer" affordances', async ({
		page
	}) => {
		// The Routes tab is admin-gated for the management affordances:
		// "New route" deeplinks to /routes/new?club=<id>, "Transfer" opens
		// a modal that lets the admin re-home one of their personal
		// routes. Pin both surfaces are visible for the owner so a
		// regression in the isAdmin guard surfaces here.
		await page.goto('/clubs/sydney-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('tab', { name: /^Routes/ }).click();

		// Both admin affordances mount.
		await expect(
			page.locator('.routes-actions a[href*="/routes/new?club="]')
		).toBeVisible({ timeout: 5_000 });
		await expect(
			page.getByRole('button', { name: /Transfer from My routes/ })
		).toBeVisible();
	});

	test('Events tab on Sydney Run Club: admin "New event" button opens the EventEditor modal', async ({
		page
	}) => {
		// Admin gating: the "New event" button at the top of /clubs/[slug]
		// is rendered only when isAdmin. Clicking it sets showEventModal
		// = true which mounts the EventEditor modal. Pin both the
		// affordance and the modal launch — a regression that broke
		// isAdmin or the showEventModal binding would surface here.
		await page.goto('/clubs/sydney-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /New event/ }).first().click();
		await expect(
			page.locator('.modal-header h2', { hasText: 'New event' })
		).toBeVisible({ timeout: 5_000 });
		// Cancel out of the modal so subsequent tests start clean.
		await page.locator('.modal-close').click();
		await expect(page.locator('.modal')).toHaveCount(0);
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
