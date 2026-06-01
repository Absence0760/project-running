import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

const MELBOURNE_NEARBY_OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.8160, lng: 144.9700 },
	{ lat: -37.8175, lng: 144.9720 },
	{ lat: -37.8200, lng: 144.9750 },
	{ lat: -37.8230, lng: 144.9780 }
];

test.describe('/live/[id] — anon spectator', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('shell mounts (logo + badge + stat tiles) for a public seeded run', async ({
		page
	}) => {
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);

		await expect(page.locator('.live-logo')).toContainText('Threkir');
		await expect(page.locator('.live-badge')).toBeVisible();
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
	});

	test('document title reflects "Live" so a backgrounded tab reads as the spectator surface', async ({
		page
	}) => {
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await expect(page).toHaveTitle(/Live|Threkir/i);
	});

	test('in-progress run: planted live pings hydrate distance + elapsed and flip badge to LIVE', async ({
		page
	}) => {
		// Started 5 min ago, projected duration 60 min — the run is
		// still in progress so the page must NOT treat it as finished.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[1], distance_m: 2_000, elapsed_s: 600 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[2], distance_m: 3_000, elapsed_s: 900 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});
			await expect(page.locator('.live-badge')).toContainText('LIVE');

			// Persona-hunt Round 3 finding Privacy #5. Anon viewers see
			// `Runner #ABCD` (4-hex-char handle derived from the
			// runner's uuid), NOT the runner's display_name. USER_A's
			// uuid is `a1b2c3d4-...` so the handle is `Runner #A1B2`.
			// A regression that surfaced "Jared Howard" to anon would
			// re-leak the runner's real name on every shared live URL.
			await expect(page.locator('.live-runner-name')).toContainText('Runner #A1B2');
			await expect(page.locator('.live-runner-name')).not.toContainText(
				'Jared Howard'
			);

			await expect(page.locator('.live-stat-value').first()).toContainText('4.5');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('22:30');
			await expect(page.locator('.live-stat-value').nth(2)).not.toContainText('--');

			await expect(page.locator('.live-runner-sub')).toContainText(/Live from the runner/i);
		} finally {
			await deleteRun(runId);
		}
	});

	test('crew joining mid-run hydrates the full backlog on load, not just the latest point', async ({
		page
	}) => {
		// Persona round-5 runner-ultra. A crew member opening the page
		// late in a long run must see the whole traversed course
		// hydrated at load — the page replays every retained ping in
		// chronological order, so the headline stats land on the LAST
		// ping's totals (proving the full ordered backlog was ingested,
		// not a single most-recent snapshot). The Supabase Realtime
		// path is exercised here (no PUBLIC_LIVE_HUB_URL in the test
		// env); the Go-hub path replays the same history server-side
		// over the WS on connect.
		const startedAt = new Date(Date.now() - 90 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 20_000,
			duration_s: 7_200,
			is_public: true
		});
		try {
			// A spread of ordered points so the backlog is unambiguous —
			// the final point (8 × 1500 m = 12.00 km, 8 × 562 s = 1:14:56)
			// is the only one that yields that readout, so seeing it proves
			// the whole history hydrated rather than an early/snapshot point.
			const lat0 = -37.82;
			const lng0 = 144.97;
			const points = Array.from({ length: 8 }, (_, i) => ({
				lat: lat0 - i * 0.002,
				lng: lng0 + i * 0.002,
				distance_m: (i + 1) * 1_500,
				elapsed_s: (i + 1) * 562
			}));
			await insertLivePings({ run_id: runId, user_id: USER_A.id, points });

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});
			// Last point: 8 * 1500 = 12000 m → 12.00 km; 8 * 562 = 4496 s
			// → 1:14:56. The first point would read 1.50 km / 9:22, so
			// these assertions fail if only the snapshot/first point
			// hydrated.
			await expect(page.locator('.live-stat-value').first()).toContainText('12');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('1:14:56');
		} finally {
			await deleteRun(runId);
		}
	});

	test('finished run: saved totals render with "Finished" badge', async ({ page }) => {
		const startedAt = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 10_000,
			duration_s: 3_000,
			is_public: true
		});
		try {
			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/finished/, {
				timeout: 10_000
			});
			await expect(page.locator('.live-badge')).toContainText(/Finished/i);

			await expect(page.locator('.live-stat-value').first()).toContainText('10');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('50:00');

			await expect(page.locator('.live-runner-sub')).toContainText(/Run finished/i);
		} finally {
			await deleteRun(runId);
		}
	});

	test('private run renders the not-broadcasting empty state to anon', async ({ page }) => {
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
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300 },
					{ ...MELBOURNE_NEARBY_OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350 }
				]
			});

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/not-found/, {
				timeout: 10_000
			});
			await expect(page.getByRole('heading', { name: /isn't broadcasting/i })).toBeVisible();
			await expect(page.locator('.live-stat-label')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
		}
	});

	test('unknown run id renders the not-broadcasting empty state', async ({ page }) => {
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/live/${bogusId}`);
		await expect(page.locator('.live-logo')).toContainText('Threkir');
		await expect(page.locator('.live-badge')).toHaveClass(/not-found/, {
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: /isn't broadcasting/i })).toBeVisible();
		await expect(page.getByRole('link', { name: /Back to Threkir/ })).toHaveAttribute(
			'href',
			'/'
		);
	});

	test('malformed (non-UUID) run id falls into not-broadcasting without crashing', async ({
		page
	}) => {
		// Different route shape from "valid UUID, no row". A regression
		// that didn't validate the id param could 500 the page or
		// surface a raw Postgres error string. Pin that the page still
		// renders the shell + the not-found empty state.
		await page.goto('/live/not-a-uuid');
		await expect(page.locator('.live-logo')).toContainText('Threkir');
		await expect(page.locator('.live-badge')).toHaveClass(/not-found/, {
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: /isn't broadcasting/i })).toBeVisible();
	});

	test('in-progress run with no pings yet keeps the badge in a pre-LIVE state', async ({
		page
	}) => {
		// The page has six states: connecting / live / finished / demo /
		// error / not-found. The existing tests cover live, finished,
		// not-found. This one pins the `connecting` branch: a public
		// run that's started recently but for which the spectator
		// page hasn't seen any pings yet — the badge MUST NOT flip to
		// LIVE (no pings) NOR finished (elapsed < duration) NOR
		// not-found (row exists, public). A regression that defaulted
		// the badge to LIVE before any ping arrived would show stale
		// content for any spectator who opens the page before the
		// runner has moved.
		const startedAt = new Date(Date.now() - 2 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await page.goto(`/live/${runId}`);

			const badge = page.locator('.live-badge');
			await expect(badge).toBeVisible();
			// Negative-shape pin — none of the terminal states are set.
			await expect(badge).not.toHaveClass(/active/);
			await expect(badge).not.toHaveClass(/finished/);
			await expect(badge).not.toHaveClass(/not-found/);
			// The runner sub-line still shows the connecting copy, not
			// the live or finished copy.
			await expect(page.locator('.live-runner-sub')).not.toContainText(
				/Run finished/i
			);
		} finally {
			await deleteRun(runId);
		}
	});

	test('pings without distance_m / elapsed_s keep the trace LIVE but freeze the stat tiles at 0', async ({
		page
	}) => {
		// A ping carries lat/lng for the trace plus OPTIONAL distance_m
		// + elapsed_s for the headline stats. Watch / mobile clients
		// that push raw GPS without an integrated odometer leave the
		// numeric fields null. Pin the page's actual behaviour:
		//
		//   1. Trace + LIVE badge fire because pings exist (lat/lng
		//      is enough to flip status from connecting → live).
		//   2. Distance / elapsed state vars stay at their initial 0
		//      because the per-ping write only fires when the field
		//      is non-null (see +page.svelte:77-78). So the stat tiles
		//      render "0 m" / "0:00" — NOT NaN, NOT undefined, NOT a
		//      crash.
		//
		// This is the documented contract (lat/lng-only pings are
		// valid). A regression that flipped the stat path to crash on
		// null, or that coerced via String(null) → "null", would fail
		// here. The product question of "should this render em-dash
		// instead of 0?" is real but separate; this test pins TODAY's
		// behaviour so a stealth change has to come with a deliberate
		// pin update.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				// No distance_m, no elapsed_s — the simulate helper
				// passes through `?? null` for both.
				points: [
					MELBOURNE_NEARBY_OUT_OF_ZONE[0],
					MELBOURNE_NEARBY_OUT_OF_ZONE[1]
				]
			});

			await page.goto(`/live/${runId}`);

			// LIVE badge — pings exist so the runner is broadcasting.
			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});

			// Distance + elapsed tiles render gracefully (no NaN, no
			// crash). The exact rendering is "0 m" / "0:00" today —
			// pinned as a regression net, not a UX endorsement.
			const stats = page.locator('.live-stat-value');
			const distanceText = (await stats.first().innerText()).trim();
			const elapsedText = (await stats.nth(1).innerText()).trim();
			expect(distanceText).not.toMatch(/NaN|undefined|null/);
			expect(elapsedText).not.toMatch(/NaN|undefined|null/);
			// Pin the specific shape so a future change to em-dash
			// fails this test and forces a deliberate update.
			expect(distanceText).toMatch(/^0\s*m$/);
			expect(elapsedText).toMatch(/^0:00$/);
		} finally {
			await deleteRun(runId);
		}
	});
});

test.describe('/live/[id] — friend spectator sees the display_name', () => {
	// Persona-hunt Round 3 finding Privacy #5. The second half of the
	// reveal contract: a viewer with a one-way follow edge in either
	// direction (or the runner viewing their own live) MUST see the
	// display_name, not the anonymous handle. USER_B (alex) follows
	// USER_A (runner) per the seed, so this storageState exercises
	// the viewer→runner follow branch.
	test.use({ storageState: USER_B.storageStatePath });

	test('alex follows runner per seed → live page reveals "Jared Howard", not the handle', async ({
		page,
	}) => {
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true,
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{
						lat: -37.816,
						lng: 144.97,
						distance_m: 1_000,
						elapsed_s: 300,
					},
				],
			});

			await page.goto(`/live/${runId}`);

			// Friend viewer — name is revealed.
			await expect(page.locator('.live-runner-name')).toContainText(
				'Jared Howard',
				{ timeout: 10_000 }
			);
			// Negative pin — the handle must NOT show up. A regression
			// that fell through to the handle path even for friends
			// would hide friendly identifiers and surprise users who
			// expected to recognise the runner they were tracking.
			await expect(page.locator('.live-runner-name')).not.toContainText(
				'Runner #'
			);
		} finally {
			await deleteRun(runId);
		}
	});
});
