import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /runs/[id] — RunSegmentEfforts panel.
 *
 * When a run carries `route_id`, the detail page mounts
 * `RunSegmentEfforts.svelte` which (a) tries to auto-compute new
 * efforts via `computeSegmentEffortsForRun` against the track, then
 * (b) renders the list of efforts that exist for the run.
 *
 * The seed does not link any run to a route, and none of the seeded
 * routes have segments — both pieces of fixture setup are planted
 * via service-role here so the visible-render path is reachable.
 *
 * Test surface:
 *   - Section header + .efforts list renders when efforts exist.
 *   - Each row shows the segment name + length + rank pill + time.
 *   - Rank pill class colour-codes top-3 (.gold / .silver / .bronze)
 *     and >=11 (no class).
 *   - Empty-state copy when route_id is set but no efforts.
 *   - "Link this run to a saved route" copy when route_id is null.
 *   - Rows link to /routes/[id]#segment-[segId].
 *
 * Cleanup via afterAll keeps the seed pristine.
 */

// Resolved at beforeAll. seed.sql plants Battersea Park with a generated
// uuid that drifts on every fresh seed, so hardcoding the id leads to
// segments_route_id_fkey violations.
let BATTERSEA_ROUTE_ID = '';
let segmentId: string;
let plantedRunIds: string[] = [];
let myRunId: string;

test.describe('/runs/[id] — RunSegmentEfforts panel', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.beforeAll(async () => {
		const admin = getAdminClient();

		const { data: bRoute, error: bErr } = await admin
			.from('routes')
			.select('id')
			.eq('name', 'Battersea Park Out & Back')
			.eq('user_id', USER_A.id)
			.single();
		if (bErr || !bRoute) {
			throw new Error(
				`segment-efforts.spec: could not resolve Battersea Park route id from seed (${bErr?.message ?? 'no row'}).`
			);
		}
		BATTERSEA_ROUTE_ID = (bRoute as { id: string }).id;

		// Plant a segment on the Battersea Park route.
		const { data: segRow, error: segErr } = await admin
			.from('segments')
			.insert({
				route_id: BATTERSEA_ROUTE_ID,
				name: 'e2e-Hill Sprint',
				start_distance_m: 2000,
				end_distance_m: 3000,
				created_by: USER_A.id
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		segmentId = (segRow as { id: string }).id;

		// Plant three runs (USER_A as the viewer, plus USER_B + USER_C)
		// with one effort each. Times: 240/260/300 → ranks 1/2/3.
		// Caller (USER_A) is rank-1 → .gold rank pill on their run.
		const users = [
			{ user: USER_A, time: 240 },
			{ user: USER_B, time: 260 },
			{ user: USER_C_PRO, time: 300 }
		];
		const startTs = new Date('2026-04-11T08:00:00Z').getTime();
		for (let i = 0; i < users.length; i++) {
			const { user, time } = users[i];
			const startedAt = new Date(startTs + i * 60_000).toISOString();
			const { data: runRow, error: runErr } = await admin
				.from('runs')
				.insert({
					user_id: user.id,
					started_at: startedAt,
					duration_s: 1800,
					distance_m: 7800,
					source: 'app',
					is_public: true,
					metadata: { activity_type: 'run' },
					route_id: BATTERSEA_ROUTE_ID
				})
				.select('id')
				.single();
			if (runErr) throw runErr;
			const runId = (runRow as { id: string }).id;
			plantedRunIds.push(runId);
			if (user.id === USER_A.id) myRunId = runId;
			await admin.from('segment_efforts').insert({
				segment_id: segmentId,
				run_id: runId,
				user_id: user.id,
				time_seconds: time,
				started_at: startedAt
			});
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (segmentId) {
			await admin.from('segments').delete().eq('id', segmentId);
		}
		if (plantedRunIds.length > 0) {
			await admin.from('runs').delete().in('id', plantedRunIds);
		}
	});

	test('section mounts under /runs/[id] for a route-linked run', async ({
		page
	}) => {
		// The host renders `<section class="section"><h2>Segments</h2>
		// <RunSegmentEfforts.../></section>` only when run.route_id is
		// set. Pin the section header so a regression that removed the
		// guard or the import would surface here.
		await page.goto(`/runs/${myRunId}`);
		await expect(
			page.locator('section h2', { hasText: /^Segments$/ })
		).toBeVisible({ timeout: 10_000 });
	});

	test('caller\'s own effort renders the rank-1 .gold pill', async ({ page }) => {
		// Caller's effort was planted at 240s (fastest). The component
		// renders `.rank-pill.gold` for rank 1. Pin the pill class +
		// the rank text.
		await page.goto(`/runs/${myRunId}`);
		await page.waitForLoadState('networkidle');
		const goldPill = page.locator('.efforts li .rank-pill.gold').first();
		await expect(goldPill).toBeVisible({ timeout: 10_000 });
		await expect(goldPill).toHaveText('#1');
	});

	test('row renders segment name + length + time in mm:ss', async ({
		page
	}) => {
		// Caller's effort: segment "e2e-Hill Sprint", length 1000m
		// (1.00 km in the runner@test.com preferred-unit pref), time
		// 240s → 4:00.
		await page.goto(`/runs/${myRunId}`);
		await page.waitForLoadState('networkidle');
		const row = page.locator('.efforts li .effort-row').first();
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row.locator('.effort-meta strong'))
			.toHaveText('e2e-Hill Sprint');
		// Length is rendered via distanceInPreferred — 1.00 km for km-
		// preferring user. Match the prefix so the unit-pref is honoured
		// without hardcoding km/mi.
		await expect(row.locator('.effort-meta .muted.small'))
			.toContainText(/1\.0[01]?\s*(km|mi)/);
		await expect(row.locator('.time')).toHaveText('4:00');
	});

	test('effort row links to /routes/[id]#segment-[segId]', async ({
		page
	}) => {
		// `<a class="effort-row" href="/routes/{route_id}#segment-{segId}">`.
		// Pin the href fragment so a regression in the anchor would
		// silently break "tap-through" to the leaderboard.
		await page.goto(`/runs/${myRunId}`);
		await page.waitForLoadState('networkidle');
		const expectedHref =
			`/routes/${BATTERSEA_ROUTE_ID}#segment-${segmentId}`;
		await expect(
			page.locator(`.efforts a.effort-row[href="${expectedHref}"]`)
		).toBeVisible({ timeout: 10_000 });
	});

	test('Empty-state copy renders when route_id is set but no efforts', async ({
		page
	}) => {
		// Plant a run with route_id but no segment_efforts. The component
		// branches to the "No segment efforts on this run" copy.
		const admin = getAdminClient();
		const { data: emptyRun } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				duration_s: 1500,
				distance_m: 5000,
				source: 'app',
				is_public: false,
				metadata: { activity_type: 'run' },
				route_id: BATTERSEA_ROUTE_ID
			})
			.select('id')
			.single();
		const emptyRunId = (emptyRun as { id: string }).id;
		try {
			await page.goto(`/runs/${emptyRunId}`);
			// Section header still mounts; the body shows the empty copy.
			await expect(
				page.locator('section h2', { hasText: /^Segments$/ })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByText(/No segment efforts on this run/i)
			).toBeVisible();
		} finally {
			await admin.from('runs').delete().eq('id', emptyRunId);
		}
	});

	test('"Link to a saved route" copy renders when route_id is null', async ({
		page
	}) => {
		// Without a route_id, the Segments section itself is gated off
		// by `{#if run.route_id}` on /runs/[id]. The component's third
		// branch ("Segments are matched per route — link this run…") is
		// reachable when the section host changes but route_id stays
		// null. Currently the host gates the section out entirely, so
		// the third branch is NOT reachable through normal navigation.
		// Pin the negative: a regression that mounted the section on a
		// route-less run would surface here as the absence of the
		// segments header.
		const admin = getAdminClient();
		const { data: solo } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				duration_s: 1500,
				distance_m: 5000,
				source: 'app',
				is_public: false,
				metadata: { activity_type: 'run' }
				// route_id intentionally omitted
			})
			.select('id')
			.single();
		const soloId = (solo as { id: string }).id;
		try {
			await page.goto(`/runs/${soloId}`);
			await expect(
				page.locator('section h2', { hasText: /^Segments$/ })
			).toHaveCount(0);
		} finally {
			await admin.from('runs').delete().eq('id', soloId);
		}
	});

	test('Caller drops to rank 2 → .silver pill (rank-class swap)', async ({
		page
	}) => {
		// rankClass() in RunSegmentEfforts.svelte: 1 → gold, 2-3 →
		// silver, 4-10 → bronze, 11+ → no class. The default fixture
		// plants USER_A at rank 1 (gold). Swap USER_A's time slower
		// than USER_B so USER_A drops to rank 2 → .silver. Pin both
		// the class change AND the rank text. (Bronze/no-class
		// branches require >=4 efforts to reach rank >=4 — covered by
		// `rankClass` unit tests in `segments_test.dart`.)
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('segment_efforts')
			.select('id')
			.eq('segment_id', segmentId)
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const effortId = (row as { id: string }).id;
		try {
			// USER_A → 270s (slower than USER_B's 260s, faster than
			// USER_C's 300s) → rank 2 → silver.
			await admin
				.from('segment_efforts')
				.update({ time_seconds: 270 })
				.eq('id', effortId);
			await page.goto(`/runs/${myRunId}`);
			await page.waitForLoadState('networkidle');
			const silver = page.locator('.efforts li .rank-pill.silver').first();
			await expect(silver).toBeVisible({ timeout: 10_000 });
			await expect(silver).toHaveText('#2');
			// The .gold pill is no longer present on this run's row.
			await expect(
				page.locator('.efforts li .rank-pill.gold')
			).toHaveCount(0);
		} finally {
			// Restore the rank-1 fixture so the suite-level invariants
			// hold for any subsequent test.
			await admin
				.from('segment_efforts')
				.update({ time_seconds: 240 })
				.eq('id', effortId);
		}
	});
});
