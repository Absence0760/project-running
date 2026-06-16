import { expect, test } from '@playwright/test';

import { isInAnyZone } from '../../src/lib/routes/privacy';
import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { deleteRun, insertRun, setUserSetting } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Privacy + data-rights JOURNEY — ONE public run with a real GPS track
 * that passes through USER_A's privacy zone, walked through the two
 * surfaces that must treat it OPPOSITELY (decisions §33):
 *
 *   1. A non-owner viewer (USER_C_PRO, second browser context) opens
 *      /share/run/[id]. The page is owner-gated for /runs/[id] but
 *      public here, so a real non-owner takes this path. The track is
 *      served through the `clip-public-track` Edge Function, which runs
 *      `clip_track_for_user` against the OWNER's zones — the points
 *      inside the home zone are dropped, and every surviving point is
 *      provably outside the zone (asserted via the shared isInAnyZone
 *      from src/lib/routes/privacy.ts, the same predicate the EF clips
 *      with). The clipped set is strictly smaller than the planted track.
 *   2. The OWNER (USER_A) triggers the GDPR data export from
 *      /settings/account → "Cloud export (GPX zip)". In dev
 *      PUBLIC_EXPORT_HUB_URL is unset, so this hits the REAL `export-data`
 *      Edge Function (not a mock — unlike settings/export.spec.ts, which
 *      stubs the wire). The signed-URL zip is downloaded and unpacked:
 *      its runs.json lists the planted run, and runs/<id>.gpx carries
 *      ALL of the planted track points — the export is the owner's own
 *      data, so it is UNCLIPPED. This is the contract that
 *      cross-cutting/export-data-guards.spec.ts (pre-side-effect gates)
 *      and share/privacy-zone-clipping.spec.ts (non-owner clip) each
 *      only prove one half of: clipped for them, complete for me.
 *
 * Backend cross-check: the run row is owned by USER_A, public, and the
 * export count reflects the owner's full run set.
 *
 * Fixture hygiene: USER_A's privacy zone is the SEEDED zone (seed.sql
 * line ~1331: home @ -37.8136,144.9631 r=200 m). We reuse it rather than
 * fighting the MapLibre PrivacyZonePicker canvas. setUserSetting REPLACES
 * the privacy_zones array, so teardown restores the exact seeded value —
 * ~6 other specs (share/privacy-zone-clipping, cross-cutting/privacy-
 * zones, the live-ping zone-drop tests) depend on it being present and
 * unchanged. We only delete the run WE planted.
 *
 * Free-tier (USER_A) export limit is 2/hour; the planted-run export
 * consumes one slot, so we wipe the `export-data` rate-limit row before
 * the export leg (mirroring export-data-guards.spec.ts) to keep the
 * journey deterministic across reruns.
 */

const PRIVACY_ZONES_KEY = 'privacy_zones';

// The seeded zone on runner (seed.sql) — home @ Melbourne CBD, 200 m.
// Reused, not recreated; restored verbatim in teardown.
const SEEDED_ZONE = { lat: -37.8136, lng: 144.9631, radius_m: 200, label: 'home' };

// Two track points sit INSIDE the seeded 200 m home zone (the start, the
// classic "leaves from home" leak), then three points walk well clear of
// it (~2.2 km north — far outside 200 m). The clip drops the leading
// in-zone pair and keeps the contiguous out-of-zone tail.
const IN_ZONE_TRACK = [
	{ lat: SEEDED_ZONE.lat, lng: SEEDED_ZONE.lng, ele: 10 },
	{ lat: SEEDED_ZONE.lat + 0.0002, lng: SEEDED_ZONE.lng + 0.0002, ele: 11 }
];
const OUT_OF_ZONE_TRACK = [
	{ lat: SEEDED_ZONE.lat + 0.02, lng: SEEDED_ZONE.lng, ele: 12 },
	{ lat: SEEDED_ZONE.lat + 0.021, lng: SEEDED_ZONE.lng + 0.001, ele: 13 },
	{ lat: SEEDED_ZONE.lat + 0.022, lng: SEEDED_ZONE.lng + 0.002, ele: 14 }
];
const FULL_TRACK = [...IN_ZONE_TRACK, ...OUT_OF_ZONE_TRACK];

// The owner-zone shape clip_track_for_user clips against (radius only;
// label dropped). Same as what isInAnyZone in privacy.ts consumes.
const OWNER_ZONES = [
	{ lat: SEEDED_ZONE.lat, lng: SEEDED_ZONE.lng, radius_m: SEEDED_ZONE.radius_m }
];

async function clearExportDataRateLimit(): Promise<void> {
	const admin = getAdminClient();
	await admin
		.from('rate_limits')
		.delete()
		.eq('user_id', USER_A.id)
		.eq('bucket', 'export-data');
}

test.describe('privacy + data-rights journey', () => {
	// One continuous cross-context walk: a non-owner clipped read, then a
	// real server-side export build + download. The default 30 s test
	// timeout is tight for the zip round-trip.
	test.describe.configure({ timeout: 90_000 });

	test.use({ storageState: USER_A.storageStatePath });

	test('public run track is clipped for a non-owner, and the owner export is complete', async ({
		browser
	}) => {
		const admin = getAdminClient();

		// Captured from the plant so the non-owner read + the export check +
		// teardown all address the SAME run.
		let runId = '';

		try {
			// ── 0. Plant a public run whose track crosses the seeded zone ──
			await test.step('seed: a public run with a track through the privacy zone', async () => {
				// Belt-and-braces: re-assert the seeded zone is present (a
				// prior spec on the same shard could have left it mutated).
				// setUserSetting REPLACES privacy_zones, so this both
				// guarantees the precondition and is restored verbatim in
				// teardown.
				await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [SEEDED_ZONE]);

				runId = await insertRun({
					user_id: USER_A.id,
					started_at: new Date('2026-05-11T08:00:00Z').toISOString(),
					duration_s: 1500,
					distance_m: 4500,
					is_public: true,
					metadata: { activity_type: 'run', title: 'e2e privacy-data-rights run' },
					track: FULL_TRACK
				});

				const { data: row } = await admin
					.from('runs')
					.select('user_id, is_public, track_url')
					.eq('id', runId)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect(row?.is_public).toBe(true);
				// Canonical track path the export's path-shape guard expects.
				expect(row?.track_url).toBe(`${USER_A.id}/${runId}.json.gz`);
			});

			// ── 1. Non-owner sees a CLIPPED track on /share/run/[id] ───────
			await test.step('USER_C_PRO (non-owner) receives a clipped point set from the EF', async () => {
				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath
				});
				// Pre-accept cookie consent so the clip EF (a third-party-ish
				// fetch behind consent gating) is allowed to fire.
				await ctx.addInitScript(() => {
					localStorage.setItem(
						'cookie_consent',
						JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
					);
				});
				const guestPage = await ctx.newPage();
				try {
					const efPromise = guestPage.waitForResponse(
						(r) =>
							r.url().includes('/functions/v1/clip-public-track') &&
							r.request().method() === 'POST',
						{ timeout: 15_000 }
					);
					await guestPage.goto(`/share/run/${runId}`);
					const ef = await efPromise;

					// The real clip function ran (not a stub) and returned 200.
					expect(ef.status()).toBe(200);
					const body = (await ef.json()) as {
						points: Array<{ lat: number; lng: number }>;
					};
					expect(Array.isArray(body.points)).toBe(true);
					expect(body.points.length).toBeGreaterThan(0);
					// Strictly fewer points than planted — the in-zone head was
					// dropped. Equivalent here to exactly the out-of-zone tail.
					expect(body.points.length).toBeLessThan(FULL_TRACK.length);
					expect(body.points.length).toBe(OUT_OF_ZONE_TRACK.length);

					// Every surviving point is outside the OWNER's zone — the
					// home location never reaches a non-owner. Asserted with the
					// same predicate the EF clips with.
					for (const p of body.points) {
						expect(isInAnyZone(p, OWNER_ZONES)).toBe(false);
					}
					// The first served point is the start of the out-of-zone
					// tail (~2.2 km north of home), not the home start.
					expect(body.points[0].lat).toBeGreaterThan(SEEDED_ZONE.lat + 0.01);

					// The share body actually rendered for the non-owner.
					await expect(guestPage.locator('.run-meta')).toBeVisible({
						timeout: 10_000
					});
				} finally {
					await ctx.close();
				}
			});

			// ── 2. Owner export contains the FULL, UNCLIPPED record ────────
			await test.step('USER_A export includes the run with its complete track', async () => {
				// Real export, not a mock: PUBLIC_EXPORT_HUB_URL is unset in
				// dev, so the button calls supabase.functions.invoke('export-
				// data', { format: 'gpx' }), which the local stack runs for
				// real. Wipe the rate-limit slot first so the build isn't 429'd
				// on a rerun (free tier = 2/hour).
				await clearExportDataRateLimit();

				const page = await browser
					.newContext({ storageState: USER_A.storageStatePath })
					.then((c) => c.newPage());
				try {
					await page.addInitScript(() => {
						localStorage.setItem(
							'cookie_consent',
							JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
						);
					});
					await page.goto('/settings/account');

					// The signed-URL response carries the run count + format; we
					// also follow the URL to read the zip bytes. Capture the EF
					// response so we have the signed URL deterministically.
					const exportRespPromise = page.waitForResponse(
						(r) =>
							r.url().includes('/functions/v1/export-data') &&
							r.request().method() === 'POST',
						{ timeout: 30_000 }
					);
					await page
						.getByRole('button', { name: /Cloud export \(GPX zip\)/ })
						.click();
					const exportResp = await exportRespPromise;
					expect(exportResp.status()).toBe(200);
					const exportJson = (await exportResp.json()) as {
						url: string;
						count: number;
						format: string;
					};
					expect(exportJson.format).toBe('gpx');
					// The owner's full run set — includes the seed's 12 runs
					// plus the one we planted.
					expect(exportJson.count).toBeGreaterThanOrEqual(13);

					// Download the signed zip and unpack it via Playwright's
					// APIRequestContext (not subject to browser CORS; the
					// signature is in the query string so no auth header is
					// needed). The export EF runs inside the Supabase Docker
					// network, so it mints the signed URL against the INTERNAL
					// gateway host (http://kong:8000), which doesn't resolve
					// from the test process. Rewrite the origin to the external
					// API URL the fixtures use (http://127.0.0.1:54321); the
					// path + signature token are unchanged so the signature
					// still verifies. In production SUPABASE_URL is the public
					// host, so the URL is already externally fetchable.
					const signed = new URL(exportJson.url);
					const apiOrigin = new URL(loadSupabaseEnv().url).origin;
					const zipResp = await page.request.get(
						`${apiOrigin}${signed.pathname}${signed.search}`
					);
					expect(zipResp.ok()).toBeTruthy();
					const zipBytes = await zipResp.body();
					expect(zipBytes.length).toBeGreaterThan(64);

					const JSZip = (await import('jszip')).default;
					const zip = await JSZip.loadAsync(zipBytes);

					// runs.json lists the planted run.
					const manifest = zip.file('runs.json');
					expect(manifest, 'runs.json must exist in the gpx export').not.toBeNull();
					const runsArr = JSON.parse(await manifest!.async('string')) as Array<{
						id: string;
						is_public: boolean | null;
					}>;
					const planted = runsArr.find((r) => r.id === runId);
					expect(planted, 'the planted run must appear in the export manifest').toBeTruthy();
					expect(planted!.is_public).toBe(true);

					// runs/<id>.gpx carries the OWNER-COMPLETE, UNCLIPPED track:
					// all FULL_TRACK points, including the in-zone home start
					// that the non-owner never sees. Count <trkpt> elements.
					const gpxEntry = zip.file(`runs/${runId}.gpx`);
					expect(
						gpxEntry,
						'the planted run must have a per-run GPX track in the export'
					).not.toBeNull();
					const gpx = await gpxEntry!.async('string');
					const trkptCount = (gpx.match(/<trkpt\b/g) ?? []).length;
					expect(trkptCount).toBe(FULL_TRACK.length);

					// Proof it is UNCLIPPED: the in-zone home coordinate is
					// present in the owner's own export (it must NOT be — that
					// would be the bug — for the non-owner, but it MUST be here).
					const homeLat = SEEDED_ZONE.lat.toString();
					expect(
						gpx.includes(`lat="${homeLat}"`),
						'owner export must contain the in-zone home start point (unclipped)'
					).toBe(true);
				} finally {
					await page.context().close();
				}
			});
		} finally {
			// Clean up ONLY what we created: the planted run + its track blob.
			// The seeded privacy zone is restored verbatim (never deleted) so
			// the other privacy specs on this shard keep their precondition.
			if (runId) {
				try {
					await deleteRun(runId);
				} catch {
					/* best-effort */
				}
			}
			await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [SEEDED_ZONE]);
		}
	});
});
