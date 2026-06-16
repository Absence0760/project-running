import { gunzipSync } from 'node:zlib';

import { expect, test, type BrowserContext } from '@playwright/test';

import { clipPointsToZones, isInAnyZone } from '../../src/lib/routes/privacy';
import { getAdminClient, getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import {
	insertRun,
	deleteRun,
	setUserSetting,
	insertLivePings
} from '../fixtures/simulate';

/**
 * Privacy-zone track clipping — the SAME-RUN, EVERY-SURFACE journey.
 *
 * decisions §33: a track that passes through the owner's privacy zone
 * must reach the OWNER unclipped (their own /runs/[id] + their owner
 * branch of RunShareView), but reach every OTHER viewer with the
 * in-zone leading/trailing points removed — on /share/run/[id], on the
 * profile/feed run modal (the RunShareView modal on /u/[id]), and on
 * /live/[id]. The isolated guard specs each pin one surface
 * (`privacy-zones.spec.ts` pins the EF subset + the owner share dialog,
 * `clip-public-track-guards.spec.ts` pins the EF's pre-side-effect
 * gates, `public-runs-view.spec.ts` pins the metadata strip). None of
 * them walks the run from owner-full → non-owner-clipped across all
 * four render sites as one security story, asserting the clip is
 * *consistent* surface-to-surface — a single surface serving the
 * unclipped blob to a non-owner is a home-address leak.
 *
 * Two saga users:
 *   - owner — has a privacy zone; owns a public run whose track
 *     straddles the zone, and a public live session whose pings do too.
 *   - viewer — a different, signed-in non-owner (a "follower viewing
 *     your run").
 *
 * The four render surfaces resolve the track through three distinct
 * code paths, all exercised here:
 *   1. /runs/[id] (owner)      — fetchRunById's owner-only
 *      `.eq('user_id', userId)` row read + direct Storage download
 *      (data.ts:186). A non-owner gets `run = null` here, so the
 *      owner-full leg is grounded by the owner-JWT clip-public-track
 *      call returning ALL points (the EF's `isOwnerBypass`), which is
 *      the same blob the owner Storage path renders.
 *   2. /share/run/[id] + the /u/[id] run modal (non-owner) —
 *      RunShareView's non-owner branch → fetchClippedTrackForRun →
 *      the `clip-public-track` Edge Function (data.ts:280,
 *      RunShareView.svelte:66-79).
 *   3. /live/[id] (spectator)  — hydrates from `live_run_pings`, which
 *      the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger clips at
 *      WRITE time. Since the SAR last-seen carve-out (migration
 *      20270121_001) an in-zone ping is no longer hard-dropped: its
 *      lat/lng is COARSENED to a ~1.1 km grid and the latest one is kept
 *      as a single forward-moving "last-seen" row. So no PRECISE in-zone
 *      coordinate ever reaches the table — for owner or spectator — but a
 *      coarsened safety-net point does.
 *
 * Why service-role plant: the privacy-zone picker is a MapLibre canvas
 * (hard to drive), so the zone is planted via setUserSetting against
 * the real `privacy_zones` pref key (privacy.ts PRIVACY_ZONES_KEY).
 * The run + track are planted via insertRun's `track` option (a real
 * gzipped blob in the `runs` bucket) so every clip path runs unmodified.
 */

// A zone well clear of the seed's Melbourne/Sydney zones so it only
// applies to this saga owner. Radius matched to what the picker writes.
const ZONE_LAT = 51.5074;
const ZONE_LNG = -0.1278;
const ZONE_RADIUS_M = 200;
const ZONE = { lat: ZONE_LAT, lng: ZONE_LNG, radius_m: ZONE_RADIUS_M };

// Track straddles the zone: two points dead-centre on it (leading,
// in-zone), then five well clear (~2 km north, out of zone).
// clipPointsToZones drops the leading in-zone run and keeps the
// contiguous out-of-zone middle — so a clipped reader gets exactly the
// five outside points, an owner gets all seven.
const IN_ZONE = [
	{ lat: ZONE_LAT, lng: ZONE_LNG, ele: 10 },
	{ lat: ZONE_LAT + 0.0001, lng: ZONE_LNG + 0.0001, ele: 10 }
];
const OUT_OF_ZONE = [
	{ lat: ZONE_LAT + 0.02, lng: ZONE_LNG, ele: 12 },
	{ lat: ZONE_LAT + 0.021, lng: ZONE_LNG + 0.001, ele: 14 },
	{ lat: ZONE_LAT + 0.022, lng: ZONE_LNG + 0.002, ele: 16 },
	{ lat: ZONE_LAT + 0.023, lng: ZONE_LNG + 0.003, ele: 18 },
	{ lat: ZONE_LAT + 0.024, lng: ZONE_LNG + 0.004, ele: 20 }
];
const PLANTED_TRACK = [...IN_ZONE, ...OUT_OF_ZONE];

// The pure reference for what a non-owner MUST receive on every surface.
const EXPECTED_CLIPPED = clipPointsToZones(PLANTED_TRACK, [ZONE]);

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

async function newAcceptedContext(
	browser: import('@playwright/test').Browser,
	storageStatePath?: string
): Promise<BrowserContext> {
	const ctx = await browser.newContext(
		storageStatePath ? { storageState: storageStatePath } : {}
	);
	// Pre-accept the cookie banner (role="dialog", floats over modals
	// and the live page's "Load map" consent gate).
	await ctx.addInitScript(setConsentAccepted);
	return ctx;
}

/** Invoke the clip-public-track EF with a given user's JWT. */
async function clipPointsViaEf(
	user: { email: string; password: string } | null,
	runId: string
): Promise<{ status: number; points: { lat: number; lng: number }[] }> {
	const { url, anonKey } = loadSupabaseEnv();
	let authHeader = `Bearer ${anonKey}`;
	if (user) {
		const client = await getUserClient({ email: user.email, password: user.password });
		const tok = (await client.auth.getSession()).data.session?.access_token;
		if (!tok) throw new Error('failed to mint user JWT for clip-public-track');
		authHeader = `Bearer ${tok}`;
	}
	const res = await fetch(`${url}/functions/v1/clip-public-track`, {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			apikey: anonKey,
			Authorization: authHeader
		},
		body: JSON.stringify({ run_id: runId })
	});
	const body = res.ok ? ((await res.json()) as { points?: { lat: number; lng: number }[] }) : null;
	return { status: res.status, points: body?.points ?? [] };
}

test.describe('privacy-zone clipping — every viewer surface', () => {
	test('owner sees the full track; a non-owner sees it clipped on /share, the profile run modal, and /live', async ({
		browser
	}) => {
		let users: SagaUser[] = [];
		let runId: string | null = null;

		try {
			users = await createSagaUsers(2, { displayNames: ['Zone Owner', 'Run Viewer'] });
			const owner = users[0];
			const viewer = users[1];

			await test.step('owner has a privacy zone covering their home', async () => {
				// Plant against the real `privacy_zones` pref key the picker
				// + clip RPC + drop-in-zone trigger all read.
				await setUserSetting(owner.id, 'privacy_zones', [ZONE]);
			});

			await test.step('owner has a public run whose track passes through the zone', async () => {
				// `started_at` must be recent: /live/[id] reads the run as
				// "finished" (badge "Finished", never "LIVE") when
				// started_at + duration_s is >2 min in the past
				// (runIsFinished, +page.svelte:486). A near-now start keeps
				// the saga's live leg in the broadcasting state.
				runId = await insertRun({
					user_id: owner.id,
					started_at: new Date(Date.now() - 60_000).toISOString(),
					duration_s: 3600,
					distance_m: 5000,
					is_public: true,
					metadata: { activity_type: 'run', title: 'e2e clip-journey run' },
					track: PLANTED_TRACK
				});

				// Ground the fixture: the stored blob (owner's source of
				// truth, what /runs/[id]'s owner Storage read renders) holds
				// EVERY planted point, including the in-zone ones.
				const admin = getAdminClient();
				const dl = await admin.storage.from('runs').download(`${owner.id}/${runId}.json.gz`);
				expect(dl.data, 'owner track blob must exist in Storage').not.toBeNull();
				const raw = await dl.data!.arrayBuffer();
				const stored = JSON.parse(gunzipSync(Buffer.from(raw)).toString('utf-8')) as {
					lat: number;
					lng: number;
				}[];
				expect(stored.length).toBe(PLANTED_TRACK.length);
				// At least one stored point is inside the zone — proving the
				// owner's durable track is unclipped and the clip is a
				// read-/viewer-time operation, not a write-time one.
				expect(stored.some((p) => isInAnyZone(p, [ZONE]))).toBe(true);
			});

			await test.step('SURFACE 1 — owner gets the FULL track (the /runs/[id] + owner-share branch)', async () => {
				// The owner-JWT clip-public-track call hits the EF's
				// `isOwnerBypass` and returns the unclipped points — the
				// same blob fetchRunById + the RunShareView owner branch
				// render for the owner. This is the "owner sees everything"
				// half of the security contract.
				const { status, points } = await clipPointsViaEf(owner, runId!);
				expect(status).toBe(200);
				expect(points.length).toBe(PLANTED_TRACK.length);
				expect(points.some((p) => isInAnyZone(p, [ZONE]))).toBe(true);
			});

			// The owner's own /runs/[id] is owner-only (fetchRunById
			// `.eq('user_id', userId)`), so render it as the owner and
			// confirm the run mounts with its map (the full-track surface
			// a non-owner can never reach here at all).
			await test.step('SURFACE 1 (DOM) — owner /runs/[id] mounts the run + its map', async () => {
				const ctx = await newAcceptedContext(browser, owner.storageStatePath);
				const page = await ctx.newPage();
				try {
					await page.goto(`/runs/${runId}`);
					await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
						timeout: 15_000
					});
					await expect(page.getByText('e2e clip-journey run')).toBeVisible();
					// The owner has a usable track (>=2 points) → the
					// run-detail RunMap container mounts (consent is
					// pre-accepted, so it doesn't sit behind "Load map").
					await expect(page.locator('.run-map').first()).toBeVisible({
						timeout: 15_000
					});
				} finally {
					await ctx.close();
				}
			});

			let sharePoints: { lat: number; lng: number }[] = [];
			await test.step('SURFACE 2 — /share/run/[id] serves the CLIPPED track to a non-owner', async () => {
				const ctx = await newAcceptedContext(browser, viewer.storageStatePath);
				const page = await ctx.newPage();
				try {
					// Capture the clip EF response the non-owner share branch
					// fires (RunShareView.svelte:74 fetchClippedTrackForRun).
					const efPromise = page.waitForResponse(
						(r) =>
							r.url().includes('/functions/v1/clip-public-track') &&
							r.request().method() === 'POST',
						{ timeout: 15_000 }
					);
					await page.goto(`/share/run/${runId}`);
					const ef = await efPromise;
					expect(ef.status()).toBe(200);
					sharePoints = ((await ef.json()) as { points: { lat: number; lng: number }[] }).points;

					// Clipped: strict subset, non-empty, and — the load-bearing
					// assertion — NO returned point inside the zone.
					expect(sharePoints.length).toBeLessThan(PLANTED_TRACK.length);
					expect(sharePoints.length).toBe(EXPECTED_CLIPPED.length);
					for (const p of sharePoints) {
						expect(
							isInAnyZone(p, [ZONE]),
							'a /share point fell inside the privacy zone — home-coords leak'
						).toBe(false);
					}

					// Page rendered (run meta present, the run is reachable).
					await expect(page.getByText('e2e clip-journey run')).toBeVisible({
						timeout: 15_000
					});
				} finally {
					await ctx.close();
				}
			});

			await test.step('SURFACE 3 — the profile/feed run modal (RunShareView on /u/[id]) clips identically', async () => {
				const ctx = await newAcceptedContext(browser, viewer.storageStatePath);
				const page = await ctx.newPage();
				try {
					await page.goto(`/u/${owner.id}`);
					await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
						timeout: 15_000
					});

					// Opening the run card mounts the SAME RunShareView the
					// feed uses, which fires its own clip-public-track call.
					const efPromise = page.waitForResponse(
						(r) =>
							r.url().includes('/functions/v1/clip-public-track') &&
							r.request().method() === 'POST',
						{ timeout: 15_000 }
					);
					await page.locator('button.run-card').first().click();
					const ef = await efPromise;
					expect(ef.status()).toBe(200);
					const modalPoints = ((await ef.json()) as {
						points: { lat: number; lng: number }[];
					}).points;

					// Consistency: the modal surface must clip the same way
					// /share did — same count, none in-zone. A drift here is
					// exactly the cross-surface inconsistency the isolated
					// specs can't catch.
					expect(modalPoints.length).toBe(sharePoints.length);
					expect(modalPoints.length).toBe(EXPECTED_CLIPPED.length);
					for (const p of modalPoints) {
						expect(
							isInAnyZone(p, [ZONE]),
							'a run-modal point fell inside the privacy zone — home-coords leak'
						).toBe(false);
					}

					// The modal body rendered the run.
					await expect(page.locator('.modal').getByText('e2e clip-journey run')).toBeVisible({
						timeout: 15_000
					});
				} finally {
					await ctx.close();
				}
			});

			await test.step('SURFACE 4 — /live/[id] never persists a PRECISE in-zone ping (SAR last-seen is coarsened)', async () => {
				// Plant a live ping sequence that straddles the zone the same
				// way the track does. The `live_run_pings_drop_in_zone` trigger
				// fires on each service-role insert. Since migration
				// 20270121_001 (the SAR last-seen carve-out) it no longer just
				// drops in-zone rows: it COARSENS the in-zone ping's lat/lng to
				// 2 decimal places (~1.1 km grid) and keeps the LATEST one as a
				// single forward-moving "last-seen" row, dropping any prior
				// coarse row so it can't accumulate. So of the two in-zone
				// pings, exactly one coarsened last-seen row survives — never a
				// precise in-zone coordinate. The privacy guarantee is unchanged
				// (no precise home coord leaks); the SAR safety net is the new
				// behaviour this surface must reflect, not the old hard drop.
				await insertLivePings({
					run_id: runId!,
					user_id: owner.id,
					points: PLANTED_TRACK.map((p, i) => ({
						lat: p.lat,
						lng: p.lng,
						distance_m: i * 200,
						elapsed_s: i * 60
					}))
				});

				// Data layer: the 5 out-of-zone pings verbatim + exactly ONE
				// coarsened last-seen row (the two in-zone pings collapse to it).
				const admin = getAdminClient();
				const { data: rows } = await admin
					.from('live_run_pings')
					.select('lat, lng')
					.eq('run_id', runId!);
				const persisted = (rows ?? []) as { lat: number; lng: number }[];
				expect(persisted.length).toBe(OUT_OF_ZONE.length + 1);

				// The load-bearing privacy assertion: NO persisted ping carries a
				// precise in-zone coordinate. The coarsened last-seen row rounds
				// to 2 dp, which for this 200 m zone lands clear of it.
				for (const p of persisted) {
					expect(
						isInAnyZone(p, [ZONE]),
						'an in-zone live ping reached the table — the drop/coarsen trigger regressed'
					).toBe(false);
					expect(
						IN_ZONE.some((iz) => iz.lat === p.lat && iz.lng === p.lng),
						'a PRECISE in-zone ping coordinate reached the table — home-coords leak'
					).toBe(false);
				}

				// Exactly one coarsened SAR last-seen row, at the 2-dp grid point.
				const round2 = (n: number) => Math.round(n * 100) / 100;
				const coarse = persisted.filter(
					(p) => p.lat === round2(ZONE_LAT) && p.lng === round2(ZONE_LNG)
				);
				expect(coarse.length, 'expected exactly one coarsened SAR last-seen ping').toBe(1);

				// Spectator DOM: a non-owner opens the public live page; with
				// pings present it hydrates to the LIVE badge (the trace is a
				// MapLibre canvas, asserted at the data layer above).
				const ctx = await newAcceptedContext(browser, viewer.storageStatePath);
				const page = await ctx.newPage();
				try {
					await page.goto(`/live/${runId}`);
					await expect(page.getByText('LIVE', { exact: true })).toBeVisible({
						timeout: 20_000
					});
				} finally {
					await ctx.close();
				}
			});
		} finally {
			if (runId) {
				try {
					// Sweep the live pings first; deleteRun only removes the
					// row + Storage track.
					await getAdminClient().from('live_run_pings').delete().eq('run_id', runId);
				} catch (_) {
					/* best-effort */
				}
				try {
					await deleteRun(runId);
				} catch (_) {
					/* best-effort */
				}
			}
			if (users.length > 0) {
				try {
					await deleteSagaUsers(users);
				} catch (_) {
					/* best-effort */
				}
			}
		}
	});
});
