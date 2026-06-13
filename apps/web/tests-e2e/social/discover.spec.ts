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

/**
 * Proximity ("near me") filter (migration 20270112_001). Seeds a public club
 * anchored at a geocoded point (NYC) + an event in it, then drives the filter
 * via the browser geolocation override + the "Use my location" button (no live
 * geocoder needed): a near fix surfaces the event with a distance label, a far
 * fix hides it. Filters by the CLUB location, never the event's meet point.
 */
const NYC = { longitude: -73.9857, latitude: 40.7484 };
const LONDON = { longitude: -0.1276, latitude: 51.5072 };

test.describe('/social — proximity discovery', () => {
	test.use({
		storageState: USER_A.storageStatePath,
		permissions: ['geolocation'],
		geolocation: NYC,
	});

	let clubId: string | null = null;
	let eventId: string | null = null;
	const stamp = Date.now();
	const discipline = `E2E Near Run ${stamp}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: club } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `E2E Geo Club ${stamp}`,
				slug: `e2e-geo-club-${stamp}`,
				is_public: true,
				location_point: `SRID=4326;POINT(${NYC.longitude} ${NYC.latitude})`,
			})
			.select('id')
			.single();
		clubId = (club as { id: string }).id;

		const { data: event } = await admin
			.from('events')
			.insert({
				club_id: clubId,
				author_id: USER_A.id,
				title: 'E2E Near Event',
				category: 'run',
				discipline,
				starts_at: new Date(stamp + 2 * 86_400_000).toISOString(),
				recurrence_freq: 'weekly',
				recurrence_byday: ['SU'],
			})
			.select('id')
			.single();
		eventId = (event as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (eventId) await admin.from('events').delete().eq('id', eventId);
		if (clubId) await admin.from('clubs').delete().eq('id', clubId);
	});

	test('"Use my location" surfaces a nearby club event and hides a far one', async ({
		page,
		context,
	}) => {
		await page.goto('/social?tab=discover');

		// Narrow to the seeded event by discipline so other public events near
		// the fix don't interfere with the visibility assertions.
		await page.getByTestId('discover-search').fill(discipline);
		const results = page.getByTestId('discover-results');
		const row = results.getByRole('link', { name: new RegExp(discipline) });
		await expect(row).toBeVisible({ timeout: 10_000 });

		// Near fix (NYC) → still visible, now with a distance label.
		await page.getByTestId('discover-use-location').click();
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('discover-distance').first()).toBeVisible();

		// Far fix (London, well outside the default 50km radius) → hidden.
		// Reload first: the code caches a fix up to 60s (maximumAge) for fast
		// repeat clicks, so a fresh document is needed to pick up the new fix.
		await context.setGeolocation(LONDON);
		await page.reload();
		await page.getByTestId('discover-search').fill(discipline);
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-use-location').click();
		await expect(row).toBeHidden({ timeout: 10_000 });
	});
});
