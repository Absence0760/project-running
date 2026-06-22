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
			author_id: USER_A.id,
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
			author_id: USER_A.id,
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

	// A runner whose last ping aged past the stale window (signal loss in a
	// backcountry race) must read DELAYED + "Updated N min ago", never a
	// fresh-looking row — the staleness-honesty contract mirrored from
	// /live/[id].
	test('a runner whose last ping is old is flagged DELAYED on the leaderboard', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e live-event stale ${Date.now()}`,
			starts_at: startsAt
		});

		try {
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'running',
				started_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
				started_by: USER_A.id
			});

			const staleAt = new Date(Date.now() - 12 * 60 * 1000).toISOString();
			const freshAt = new Date(Date.now() - 5 * 1000).toISOString();
			await insertRacePings({
				event_id: eventId,
				instance_start: startsAt,
				runners: [
					{
						user_id: USER_C_PRO.id,
						points: [
							{
								lat: OUT_OF_ZONE_LAT + 0.001,
								lng: OUT_OF_ZONE_LNG + 0.001,
								distance_m: 5_200,
								elapsed_s: 580,
								at: freshAt
							}
						]
					},
					{
						user_id: USER_B.id,
						points: [
							{
								lat: OUT_OF_ZONE_LAT,
								lng: OUT_OF_ZONE_LNG,
								distance_m: 3_500,
								elapsed_s: 600,
								at: staleAt
							}
						]
					}
				]
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			const runners = page.locator('.leaderboard .runner');
			await expect(runners).toHaveCount(2, { timeout: 10_000 });

			// The leader's ping is fresh -> no stale class, no DELAYED badge.
			await expect(runners.nth(0)).not.toHaveClass(/stale/);
			await expect(runners.nth(0).locator('.stale-badge')).toHaveCount(0);

			// The back-of-pack runner's ping is 12 min old -> stale row +
			// DELAYED badge + an honest "Updated N min ago" readout.
			await expect(runners.nth(1)).toHaveClass(/stale/);
			await expect(runners.nth(1).locator('.stale-badge')).toContainText('DELAYED');
			await expect(runners.nth(1).locator('.freshness')).toContainText(/Updated \d+ min ago/);
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});

	// The per-row DNF/DNS status renders a localized label, not the raw DB
	// enum uppercased.
	test('a DNF result row shows a localized status label', async ({ page }) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e live-event dnf ${Date.now()}`,
			starts_at: startsAt
		});

		try {
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'finished',
				started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
				finished_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
				started_by: USER_A.id
			});
			await getAdminClient().from('event_results').insert({
				id: crypto.randomUUID(),
				event_id: eventId,
				instance_start: startsAt,
				user_id: USER_A.id,
				duration_s: 0,
				distance_m: 0,
				finisher_status: 'dnf'
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			const dnfRow = page.locator('.results .runner.dnf-row');
			await expect(dnfRow).toHaveCount(1, { timeout: 10_000 });
			await expect(dnfRow.locator('.dnf')).toHaveText('DNF');
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});
});

// CRITICAL privacy: the event live-leaderboard is anon-accessible and the
// URL is shareable, so an anonymous worldwide viewer must NOT see any
// runner's real display_name — only the anonymous `Runner #XXXX` handle,
// mirroring the /live/[id] solo-page contract. Run as an anon visitor.
test.describe('/live/event/[id]/[instance] — anon leaderboard privacy', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon viewer sees Runner #XXXX handles on the leaderboard, never a real display_name', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e live-event anon-privacy ${Date.now()}`,
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
							{ lat: OUT_OF_ZONE_LAT, lng: OUT_OF_ZONE_LNG, distance_m: 3_500, elapsed_s: 600 }
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
					}
				]
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			const runners = page.locator('.leaderboard .runner');
			await expect(runners).toHaveCount(2, { timeout: 10_000 });

			// USER_C (morgan, b…→ uuid c3d4…) leads at 5.20 km, USER_B
			// (alex, uuid b2c3…) second at 3.50 km. The anon viewer follows
			// no one, so each row must read its `Runner #XXXX` handle (first
			// 4 hex chars of the uuid, upper-cased), NOT the seeded name.
			await expect(runners.nth(0).locator('.name')).toContainText('Runner #C3D4');
			await expect(runners.nth(1).locator('.name')).toContainText('Runner #B2C3');

			// The negative pins are the actual leak guard: a regression that
			// surfaced the real names to anon would re-open the critical bug.
			await expect(page.locator('.leaderboard')).not.toContainText('Morgan Lee');
			await expect(page.locator('.leaderboard')).not.toContainText('Alex Chen');
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});
});

// audit-findings 2026-05-30 High [cookie-consent]: this event spectator
// page is anon-accessible and MapTiler logs the requester IP per tile
// fetch, so the map must NOT mount before consent — mirroring the
// already-gated /live/[id] sibling. Run as an anon visitor with no prior
// consent stored so the per-page "Load map" veil is the only path.
test.describe('/live/event/[id]/[instance] — MapTiler consent gate', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees a Load-map veil; map only mounts after opting in', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e live-event consent ${Date.now()}`,
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
							{ lat: OUT_OF_ZONE_LAT, lng: OUT_OF_ZONE_LNG, distance_m: 3_500, elapsed_s: 600 }
						]
					}
				]
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			// Pings exist, so the map WOULD render — but without consent the
			// veil shows and the MapLibre container is never mounted (no
			// MapTiler tile fetch, hence no IP leak).
			const loadMap = page.getByRole('button', { name: 'Load map' });
			await expect(loadMap).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.race-map')).toHaveCount(0);

			// Opting in mounts the map.
			await loadMap.click();
			await expect(page.locator('.race-map')).toHaveCount(1);
		} finally {
			await deleteRaceState(eventId, startsAt);
		}
	});
});
