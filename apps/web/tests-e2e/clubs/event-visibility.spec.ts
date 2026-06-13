import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Event-level visibility (migration 20270113_001): a PUBLIC club can mark an
 * individual event members-only. USER_A is an admin of the public
 * `richmond-run-club`, so the EventEditor shows the members-only toggle.
 *
 * Test 1 pins the UI write path end-to-end (toggle → createEvent → is_public
 * false → "members only" badge on the detail page, visible to the owner).
 * Test 2 pins that a members-only event is excluded from /social Discover even
 * for a member, while a public sibling surfaces.
 */
const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs — event-level visibility', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('members-only toggle creates a private event; owner sees the badge; DB is_public=false', async ({
		page
	}) => {
		const title = `e2e-members-only ${Date.now()}`;
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);
		let eventId = '';
		try {
			await page.goto('/clubs/richmond-run-club');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
			).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: /New event/ }).click();
			const modal = page.locator('.modal', { hasText: 'New event' });
			await expect(modal).toBeVisible({ timeout: 5_000 });

			await modal.getByPlaceholder('Sunday long run').fill(title);
			await modal.locator('input[type="date"]').first().fill(dayIso);
			await modal.locator('input[type="time"]').first().fill('07:30');

			// The members-only toggle is present because richmond-run-club is public.
			await modal.getByTestId('members-only-toggle').check();

			await modal.getByRole('button', { name: /Create event/ }).click();
			await expect(modal).toHaveCount(0, { timeout: 10_000 });

			await page.getByRole('tab', { name: /^Events/ }).click();
			const row = page.locator('a[href*="/events/"]', { hasText: title });
			await expect(row).toBeVisible({ timeout: 10_000 });
			const href = (await row.getAttribute('href')) ?? '';
			eventId = href.match(/\/events\/([0-9a-f-]+)$/)![1];

			// Owner opens the detail page → the "members only" badge is shown.
			await row.click();
			await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('members-only-badge')).toBeVisible();

			// DB confirms the write.
			const admin = getAdminClient();
			const { data } = await admin
				.from('events')
				.select('is_public')
				.eq('id', eventId)
				.single();
			expect((data as { is_public: boolean }).is_public).toBe(false);
		} finally {
			if (eventId) await getAdminClient().from('events').delete().eq('id', eventId);
		}
	});

	test('discovery excludes a members-only event but includes a public sibling', async ({
		page
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const pubDisc = `E2E Vis Public ${stamp}`;
		const privDisc = `E2E Vis Private ${stamp}`;
		const startsAt = new Date(stamp + 2 * 24 * 3600 * 1000).toISOString();

		const { data: pub } = await admin
			.from('events')
			.insert({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title: 'Vis Public',
				category: 'class',
				discipline: pubDisc,
				starts_at: startsAt,
				recurrence_freq: 'weekly',
				recurrence_byday: ['SU'],
				is_public: true
			})
			.select('id')
			.single();
		const { data: priv } = await admin
			.from('events')
			.insert({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title: 'Vis Private',
				category: 'class',
				discipline: privDisc,
				starts_at: startsAt,
				recurrence_freq: 'weekly',
				recurrence_byday: ['SU'],
				is_public: false
			})
			.select('id')
			.single();
		const pubId = (pub as { id: string }).id;
		const privId = (priv as { id: string }).id;

		try {
			await page.goto('/social?tab=discover');
			const results = page.getByTestId('discover-results');

			// The public event surfaces.
			await page.getByTestId('discover-search').fill(pubDisc);
			await expect(results.getByRole('link', { name: new RegExp(pubDisc) })).toBeVisible({
				timeout: 10_000
			});

			// The members-only event never surfaces — even though USER_A is a
			// member of the club, discovery filters on is_public.
			await page.getByTestId('discover-search').fill(privDisc);
			await expect(
				page.getByRole('link', { name: new RegExp(privDisc) })
			).toHaveCount(0, { timeout: 10_000 });
		} finally {
			await admin.from('events').delete().eq('id', pubId);
			await admin.from('events').delete().eq('id', privId);
		}
	});
});
