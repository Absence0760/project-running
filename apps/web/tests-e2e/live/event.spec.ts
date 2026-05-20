import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	insertEvent,
	insertRacePings,
	insertRaceSession
} from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

const OUT_OF_ZONE_LAT = -37.8200;
const OUT_OF_ZONE_LNG = 144.9800;

async function deleteRaceState(eventId: string, instanceStart: string) {
	const admin = getAdminClient();
	await admin
		.from('race_pings')
		.delete()
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart);
	await admin
		.from('race_sessions')
		.delete()
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart);
	await admin.from('events').delete().eq('id', eventId);
}

test.describe('/live/event/[id]/[instance]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('mounts the pre-race empty state when no race_session exists for the instance', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e live-event pre-race ${Date.now()}`,
			starts_at: startsAt
		});
		const instance = encodeURIComponent(startsAt);

		try {
			await page.goto(`/live/event/${eventId}/${instance}`);

			await expect(
				page.getByText(/Organiser hasn’t armed the race timer/)
			).toBeVisible({ timeout: 10_000 });
			await expect(page.getByText(/No live position data yet/)).toBeVisible();
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});

	test('running race + 3 runners: status pill reads Running and leaderboard sorts distance-desc', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e live-event running ${Date.now()}`,
			starts_at: startsAt
		});

		try {
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'running',
				started_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
				started_by: USER_A.id
			});

			await insertRacePings({
				event_id: eventId,
				instance_start: startsAt,
				runners: [
					{
						user_id: USER_B.id,
						points: [
							{
								lat: OUT_OF_ZONE_LAT,
								lng: OUT_OF_ZONE_LNG,
								distance_m: 3_500,
								elapsed_s: 600
							}
						]
					},
					{
						user_id: USER_C_PRO.id,
						points: [
							{
								lat: OUT_OF_ZONE_LAT + 0.001,
								lng: OUT_OF_ZONE_LNG + 0.001,
								distance_m: 5_200,
								elapsed_s: 580
							}
						]
					},
					{
						user_id: USER_A.id,
						points: [
							{
								lat: OUT_OF_ZONE_LAT - 0.05,
								lng: OUT_OF_ZONE_LNG - 0.05,
								distance_m: 1_800,
								elapsed_s: 600
							}
						]
					}
				]
			});

			await page.goto(
				`/live/event/${eventId}/${encodeURIComponent(startsAt)}`
			);

			await expect(page.locator('.status-label')).toContainText(/Running/, {
				timeout: 10_000
			});
			await expect(page.locator('.status-dot.status-running')).toBeVisible();

			const runners = page.locator('.leaderboard .runner');
			await expect(runners).toHaveCount(3);

			await expect(runners.nth(0).locator('.name')).toContainText('Morgan Lee');
			await expect(runners.nth(0).locator('.dist')).toContainText('5.20');
			await expect(runners.nth(1).locator('.name')).toContainText('Alex Chen');
			await expect(runners.nth(1).locator('.dist')).toContainText('3.50');
			await expect(runners.nth(2).locator('.name')).toContainText('Jared Howard');
			await expect(runners.nth(2).locator('.dist')).toContainText('1.80');

			await expect(runners.nth(0).locator('.pos')).toContainText('1');
			await expect(runners.nth(2).locator('.pos')).toContainText('3');

			const computedColors = await Promise.all(
				[0, 1, 2].map((i) =>
					runners
						.nth(i)
						.locator('.avatar')
						.evaluate((el) => getComputedStyle(el).color)
				)
			);
			expect(new Set(computedColors).size).toBe(3);
			for (const c of computedColors) {
				expect(c).toMatch(/rgb/);
			}

			await expect(page.locator('.section-head .count').first()).toContainText('3');
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});
});
