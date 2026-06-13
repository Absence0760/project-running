import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Cross-club activity discovery (migration 20270110_001) — the /social Discover
 * tab over search_public_events. Seeds a public-club class event and confirms
 * it surfaces and responds to the discipline search + category + weekday
 * filters. Richmond Run Club (seed) is public, so its events are discoverable.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/social — activity discovery', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	const discipline = `E2E Pilates ${Date.now()}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('events')
			.insert({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title: 'E2E Discover Class',
				category: 'class',
				discipline,
				// 23:00 UTC = 19:00 America/New_York (EDT) → evening, local.
				starts_at: '2026-07-05T23:00:00.000Z',
				timezone: 'America/New_York',
				recurrence_freq: 'weekly',
				recurrence_byday: ['SU'],
			})
			.select('id')
			.single();
		eventId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (eventId) await admin.from('events').delete().eq('id', eventId);
	});

	test('discipline search + category + weekday filters surface a public class', async ({
		page,
	}) => {
		await page.goto('/social?tab=discover');

		// Search by discipline → the seeded class surfaces, linking to its event.
		await page.getByTestId('discover-search').fill(discipline);
		const results = page.getByTestId('discover-results');
		const row = results.getByRole('link', { name: new RegExp(discipline) });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row).toHaveAttribute(
			'href',
			new RegExp(`/clubs/richmond-run-club/events/${eventId}`)
		);

		// Category 'class' keeps it; 'run' filters it out.
		await page.getByTestId('discover-cat-class').click();
		await expect(row).toBeVisible();
		await page.getByTestId('discover-cat-run').click();
		await expect(row).toBeHidden({ timeout: 10_000 });

		// Back to class; the Sunday weekday filter keeps it, Monday drops it.
		await page.getByTestId('discover-cat-class').click();
		await page.getByTestId('discover-day').selectOption('SU');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-day').selectOption('MO');
		await expect(row).toBeHidden({ timeout: 10_000 });

		// Time-of-day resolves the event's LOCAL hour (19:00 New York), not the
		// 23:00 UTC instant: evening keeps it, morning drops it.
		await page.getByTestId('discover-day').selectOption('');
		await page.getByTestId('discover-time').selectOption('evening');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-time').selectOption('morning');
		await expect(row).toBeHidden({ timeout: 10_000 });
	});
});
