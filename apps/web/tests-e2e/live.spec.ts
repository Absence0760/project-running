import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';
import { deleteRun, insertLivePings, insertRun } from './fixtures/simulate';
import { USER_A } from './fixtures/users';

/**
 * /live/[id] — anon spectator page for a public run that's broadcasting.
 *
 * This is one of the few pages that's intentionally public (the
 * layout's auth guard's `isPublic` includes /live/). Web has no
 * "start a broadcast" UI by design ([decisions § 24](docs/decisions.md))
 * — broadcasting is a mobile/watch capability. Tests here cover the
 * spectator side only; the recorder side runs through service-role
 * `simulate.insertLivePings` to fan out via Realtime without spinning
 * up a real recorder.
 */

test.describe('/live/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visit to a public run live page mounts with status badge', async ({
		page
	}) => {
		// Without active broadcast pings the badge stays "Connecting..."
		// then transitions to "Demo" after the in-page timer fires.
		// We just assert the shell mounts — the brand label, badge
		// container, and stat tiles all exist regardless of connection
		// state.
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-badge')).toBeVisible();
		// Three stat tiles: Distance / Elapsed / Pace.
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
	});

	test('planted live_run_pings hydrate the backlog: distance + elapsed render, badge flips to LIVE', async ({
		page
	}) => {
		// Plant a public run + a sequence of live_run_pings, then visit
		// /live/[id] as anon. hydrateBacklog fetches the rows on mount,
		// pushPing fills the stat strip, and the status flips from
		// 'connecting' → 'live'. Coordinates clear of runner's seeded
		// privacy zone in Sydney CBD; they're chosen near Melbourne CBD
		// (the page's fallback centre) so the in-zone-drop trigger
		// can't silently swallow the points.
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ lat: -37.8140, lng: 144.9633, distance_m: 1_000, elapsed_s: 300 },
					{ lat: -37.8145, lng: 144.9640, distance_m: 2_000, elapsed_s: 600 },
					{ lat: -37.8150, lng: 144.9650, distance_m: 3_000, elapsed_s: 900 },
					{ lat: -37.8155, lng: 144.9660, distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);
			await page.waitForLoadState('networkidle');

			// Badge: hydrateBacklog returning rows flips status='live'.
			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});
			await expect(page.locator('.live-badge')).toContainText('LIVE');

			// Distance stat reads the LATEST ping's distance_m. seed in
			// km units → "4.5 km" formatted by formatDistance.
			await expect(page.locator('.live-stat-value').first())
				.toContainText('4.5');

			// Elapsed shows formatDuration(1350) = "22:30".
			await expect(page.locator('.live-stat-value').nth(1))
				.toContainText('22:30');
		} finally {
			// Cascade: deleting the run drops every live_run_pings row
			// via the FK on delete cascade.
			await deleteRun(runId);
		}
	});

	test('private run with planted pings does NOT leak distance/elapsed to anon', async ({
		page
	}) => {
		// /live/[id] for a NON-public run must not surface ping data to
		// an anon viewer. RLS blocks the hydrateBacklog read; the page
		// stays in connecting/demo with zeroed stats. Regression risk:
		// a refactor that lets a SECURITY DEFINER bypass leak the rows
		// would silently turn private runs into anon-watchable broadcasts.
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ lat: -37.8140, lng: 144.9633, distance_m: 1_000, elapsed_s: 300 },
					{ lat: -37.8150, lng: 144.9650, distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);
			await page.waitForLoadState('networkidle');
			// Stat strip exists but the values must not include the
			// planted ping data. The badge must NOT be in the .active
			// (LIVE) state — anon shouldn't see live truthful state.
			await expect(page.locator('.live-badge')).not.toHaveClass(/active/, {
				timeout: 10_000
			});
			// Distance stat must not show the leaked 4.5 km value.
			await expect(page.locator('.live-stat-value').first()).not.toContainText('4.5');
		} finally {
			await deleteRun(runId);
		}
	});

	test('unknown run id mounts the shell without crashing', async ({ page }) => {
		// Stale-link landing: a deleted/never-existed run id should not
		// crash the page. The /live/[id] route mounts the shell and
		// stays in connecting / demo state because there's nothing to
		// hydrate. We pin "shell mounts" via the brand label + three
		// stat tiles, and "no live data" via the badge not flipping
		// to LIVE.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/live/${bogusId}`);
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
		await expect(page.locator('.live-badge')).not.toHaveClass(/active/);
	});

	test('document title reflects "Live" so a tab in the background reads as the spectator surface', async ({
		page
	}) => {
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');
		// Tab title is the user's cue when they switch back. Pin a
		// stable substring rather than the exact copy.
		await expect(page).toHaveTitle(/Live|Run Onward/i);
	});
});
