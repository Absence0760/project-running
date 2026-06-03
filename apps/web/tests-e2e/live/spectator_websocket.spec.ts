import { expect, test } from '@playwright/test';

import { pushLivePing } from '../fixtures/livehub';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The real Go-hub WebSocket path end-to-end.
 *
 * The sharded spectator suite (live/spectator.spec.ts) exercises the
 * Supabase Realtime FALLBACK — it seeds live_run_pings rows directly
 * and PUBLIC_LIVE_HUB_URL is unset. This spec runs only under
 * playwright.livehub.config.ts, which boots the actual Go live-hub and
 * a dev server with PUBLIC_LIVE_HUB_URL set, so the spectator page
 * takes openLiveWebSocket() instead. Pings reach the page over a real
 * WebSocket from the real hub binary — nothing simulated.
 *
 * Coordinates are in Melbourne, well clear of the seeded Sydney
 * privacy zone on USER_A, so the hub's server-side zone clip
 * (Server.shouldDrop) publishes them rather than dropping. pushLivePing
 * throws if a point is clipped, so a regression that mis-sites the zone
 * fails loudly at the push, not as a badge timeout.
 */
const OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.816, lng: 144.97 },
	{ lat: -37.8175, lng: 144.972 },
	{ lat: -37.82, lng: 144.975 },
	{ lat: -37.823, lng: 144.978 }
];

test.describe('/live/[id] — Go-hub WebSocket path', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('replays the on-connect backlog over the WS then streams a new live ping', async ({
		page
	}) => {
		// Started 5 min ago, projected 60 min — in progress, so the page
		// must NOT short-circuit to the "finished" branch.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			// Push the backlog to the hub BEFORE the spectator connects.
			// The hub buffers these in its per-room ring; on WS connect the
			// server replays them (server.go handleSubscribe). Seeing the
			// LAST point's totals (3.00 km / 15:00) — not the first
			// (1.00 km / 5:00) — proves the ordered replay hydrated, not a
			// single snapshot dot.
			await pushLivePing(runId, { ...OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300 });
			await pushLivePing(runId, { ...OUT_OF_ZONE[1], distance_m: 2_000, elapsed_s: 600 });
			await pushLivePing(runId, { ...OUT_OF_ZONE[2], distance_m: 3_000, elapsed_s: 900 });

			await page.goto(`/live/${runId}`);

			// WS replay flips the badge to LIVE and lands the stats on the
			// last replayed ping.
			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 15_000
			});
			await expect(page.locator('.live-badge')).toContainText('LIVE');
			await expect(page.locator('.live-stat-value').first()).toContainText('3.00');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('15:00');

			// Anon viewer still sees the anonymous handle, not the
			// display_name — the privacy contract holds on the WS path too
			// (same ensureRunIsVisible gate as the Realtime path).
			await expect(page.locator('.live-runner-name')).toContainText('Runner #A1B2');

			// Now push a NEW ping AFTER the page is connected. It was never
			// in the connect-time replay buffer, so it can ONLY arrive over
			// the live subscribe stream — this is what proves the streaming
			// path, distinct from the on-connect replay above.
			await pushLivePing(runId, { ...OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350 });

			await expect(page.locator('.live-stat-value').first()).toContainText('4.5', {
				timeout: 15_000
			});
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('22:30');
		} finally {
			await deleteRun(runId);
		}
	});

	test('snapshot late-joiner: a ping pushed before load hydrates the page on the WS path', async ({
		page
	}) => {
		// A single point pushed before the spectator opens the page. The
		// page's hydrateBacklog() calls fetchLiveSnapshot() (real HTTP GET
		// to the hub's /snapshot) to decide the room is non-empty, and the
		// WS replay then renders it. The badge must flip to LIVE off that
		// one buffered point — never falling through to the 5 s demo
		// animation, which would mean the snapshot/WS path is dead.
		const startedAt = new Date(Date.now() - 3 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await pushLivePing(runId, { ...OUT_OF_ZONE[0], distance_m: 800, elapsed_s: 240 });

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 15_000
			});
			await expect(page.locator('.live-badge')).toContainText('LIVE');
			// Real source, not the demo: the demo ticker fabricates
			// monotonically climbing distance from a different origin and
			// would never settle on this exact 800 m / 4:00 readout.
			// (Sub-kilometre distance renders in metres, not "0.80 km".)
			await expect(page.locator('.live-stat-value').first()).toContainText('800 m');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('4:00');
		} finally {
			await deleteRun(runId);
		}
	});
});
