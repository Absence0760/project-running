import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser,
} from '../fixtures/saga-users';
import { deleteRun, deleteRoute, insertRun, insertRoute } from '../fixtures/simulate';

/**
 * Single-run ENRICHMENT lifecycle — the arc a GPS-recorded run takes
 * from a bare row to a fully-detailed activity, then out to its
 * privacy-clipped public face. personal-records-journey.spec.ts walks
 * the PB-cache contract; run-lifecycle-journey.spec.ts walks create →
 * edit → cross-user social → delete. NEITHER walks the *detail
 * surfaces a track + HR series light up*. This spec does exactly that
 * — it threads ONE run through every enrichment surface on /runs/[id]
 * and confirms the public /share/run/[id] view re-derives them from
 * the clipped track:
 *
 *   1. A run lands with a real GPS track (per-point ele + ts + bpm) and
 *      a linked route. /runs/[id] mounts and the track-fed surfaces
 *      light up TOGETHER:
 *        - key-stats grid (distance / time / pace / elevation),
 *        - Grade-Adjusted Pace stat (track has real climb so GAP differs
 *          from raw pace by ≥2 s/km — the showGradeAdjustedPace gate),
 *        - Elevation Profile (gated on real `ele` samples),
 *        - Splits table (gated on track timestamps),
 *        - Heart Rate Zones (5-segment bar + avg/min/max from per-point
 *          bpm — NOT the "no data" empty state),
 *        - Segment efforts (run.route_id set → Segments section + the
 *          planted effort's rank pill),
 *        - Photos gallery (owner-uploaded via the RunPhotos file input),
 *        - Gear chip (owner tags a shoe via RunGearChips).
 *   2. The run is made PUBLIC via the share icon → ConfirmDialog →
 *      makeRunPublic flips is_public; the visibility chip flips to
 *      Public and the clipboard gets the /share link.
 *   3. /share/run/[id] (the anon-reachable public face) re-renders the
 *      enriched view from the CLIPPED track: the run-meta line, the
 *      Elevation Profile, the gear chip, and the uploaded photo — but
 *      the owner-only edit affordances (Add photo / gear Edit) are
 *      ABSENT for a non-owner. The non-owner track comes through the
 *      clip-public-track Edge Function, which we stub with a clipped
 *      polyline so the share map + elevation still mount deterministically
 *      without depending on the EF's live behaviour.
 *
 * Ownership: an ephemeral saga user owns everything (run, route,
 * segment, effort, photo, gear) so the run-detail owner gates
 * (auth.user.id === run.user_id) all open and teardown is a single
 * deleteSagaUsers CASCADE plus explicit blob/route sweeps in finally.
 *
 * Track placement: the points sit at ~-37.90 / 145.05 — well clear of
 * the seed's 200 m privacy zone at -37.8136 / 144.9631 (the saga user
 * has no zone of their own anyway, but keeping clear means the OWNER
 * view renders the unclipped track verbatim, so the elevation +
 * splits assertions are deterministic). The /share clipping is
 * exercised separately via the stubbed EF in step 3.
 */

// A 1×1 transparent PNG — the smallest valid image the RunPhotos file
// input will accept. Storage policies only check the MIME prefix.
const ONE_PIXEL_PNG = Buffer.from([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
	0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
	0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
	0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

// Saga-user contexts float a cookie-consent banner (role=dialog) over
// the page; pre-accepting it keeps the banner from intercepting clicks
// on the share icon / file input (it broke a prior spec).
function setConsentAccepted(): void {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

test.describe('single-run enrichment journey', () => {
	test('track + HR run lights up /runs/[id] detail surfaces, then renders enriched + clipped on /share/run/[id]', async ({
		browser,
	}) => {
		const admin = getAdminClient();

		let owner: SagaUser | null = null;
		let runId = '';
		let routeId = '';
		let segmentId = '';
		let photoStoragePath = '';

		try {
			[owner] = await createSagaUsers(1, { displayNames: ['Enrichment Owner'] });

			// ── Fixture: a climbing track with per-point ele + ts + bpm ──
			// 12 points along a south-east Melbourne suburban line, clear of
			// the seed privacy zone. Elevation climbs 40→150 m then settles —
			// enough relief that grade-adjusted pace diverges from raw pace
			// (the ≥2 s/km showGradeAdjustedPace gate). Timestamps at 90 s
			// spacing feed computeRealSplits. bpm spans Zone 1 (≤114) through
			// Zone 4 (≤171) on the page's default cutoffs so the HR bar fills.
			const baseLat = -37.9000;
			const baseLng = 145.0500;
			const startMs = new Date('2026-04-12T07:00:00Z').getTime();
			const elevations = [40, 55, 72, 90, 110, 135, 150, 140, 120, 95, 70, 50];
			const bpmSamples = [108, 116, 124, 138, 150, 162, 168, 160, 150, 140, 128, 112];
			const track = elevations.map((ele, i) => ({
				lat: baseLat + i * 0.0012,
				lng: baseLng + i * 0.0012,
				ele,
				ts: new Date(startMs + i * 90_000).toISOString(),
				bpm: bpmSamples[i],
			}));

			// A route for the run to link to — the gate for the Segments
			// section on /runs/[id]. insertRoute fires the geom trigger; we
			// only need a real row + a segment + a planted effort, so the
			// segment-efforts list renders deterministically rather than
			// depending on the client-side auto-effort matcher.
			routeId = await insertRoute({
				user_id: owner.id,
				name: `e2e-enrichment-route ${Date.now()}`,
				waypoints: track.map((p) => ({ lat: p.lat, lng: p.lng, elevation_m: p.ele })),
				distance_m: 1_500,
			});

			const { data: segRow, error: segErr } = await admin
				.from('segments')
				.insert({
					route_id: routeId,
					name: 'e2e-Enrichment Climb',
					start_distance_m: 200,
					end_distance_m: 1_000,
					author_id: owner.id,
				})
				.select('id')
				.single();
			if (segErr) throw segErr;
			segmentId = (segRow as { id: string }).id;

			// The run itself, owned by the saga user, with the GPS track +
			// the route link. Private to start — step 2 flips it public.
			runId = await insertRun({
				user_id: owner.id,
				started_at: new Date('2026-04-12T07:00:00Z').toISOString(),
				distance_m: 1_500,
				duration_s: 990, // 12 × 90 s spacing ≈ the track span
				is_public: false,
				metadata: { activity_type: 'run', avg_bpm: 140 },
				route_id: routeId,
				track,
			});

			// A planted segment effort so the Segments list has a row (rank
			// 1 → .gold pill). Matching the segment-efforts spec's approach,
			// this sidesteps the auto-effort matcher's distance-window math.
			const { error: effErr } = await admin.from('segment_efforts').insert({
				segment_id: segmentId,
				run_id: runId,
				user_id: owner.id,
				time_seconds: 240,
				started_at: new Date('2026-04-12T07:00:00Z').toISOString(),
			});
			if (effErr) throw effErr;

			const ctx = await browser.newContext({
				storageState: owner.storageStatePath,
			});
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();

			try {
				// ── 1. /runs/[id] — every track-fed surface lights up ───────
				await test.step('the track + HR run lights up the run-detail enrichment surfaces', async () => {
					await page.goto(`/runs/${runId}`);
					await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
						timeout: 15_000,
					});

					// Key-stats grid: distance + the Grade-Adjusted Pace stat.
					// realElevationGain renders the Elevation stat; the GAP cell
					// only appears when the climb makes GAP differ from raw pace
					// (the showGradeAdjustedPace gate) — so its presence proves the
					// track's elevation flowed into gradeAdjustedPaceSecPerKm.
					await expect(page.locator('.key-stat-value').first()).toBeVisible();
					await expect(
						page.locator('.key-stat-label', { hasText: 'Grade-Adj. Pace' }),
					).toBeVisible({ timeout: 10_000 });
					await expect(
						page.locator('.key-stat-label', { hasText: /^Elevation$/ }),
					).toBeVisible();

					// Elevation Profile section — gated on real `ele` samples.
					await expect(
						page.locator('section h2', { hasText: /^Elevation Profile$/ }),
					).toBeVisible({ timeout: 10_000 });

					// Splits table — gated on track timestamps (computeRealSplits).
					await expect(
						page.locator('section h2', { hasText: /^Splits$/ }),
					).toBeVisible();
					await expect(
						page.locator('.splits-table tbody tr').first(),
					).toBeVisible();

					// Heart Rate Zones — the per-point-bpm branch: 5-segment bar +
					// avg/min/max, NOT the "no data" empty state. min 108 / max 168
					// come straight from the planted samples, proving the bpm
					// stream drove the breakdown.
					await expect(
						page.getByRole('heading', { name: 'Heart Rate Zones' }),
					).toBeVisible();
					await expect(page.locator('.hr-segment')).toHaveCount(5);
					await expect(page.locator('.hr-empty')).toHaveCount(0);
					await expect(
						page
							.locator('.hr-stat-label', { hasText: 'Min' })
							.locator('+ .hr-stat-value'),
					).toHaveText('108');
					await expect(
						page
							.locator('.hr-stat-label', { hasText: 'Max' })
							.locator('+ .hr-stat-value'),
					).toHaveText('168');
					// Legend percentages sum to ~100 (±1 per-row rounding).
					const pctTexts = await page
						.locator('.hr-legend .hr-zone-pct')
						.allInnerTexts();
					const pctTotal = pctTexts
						.map((t) => parseInt(t.replace(/[^0-9]/g, ''), 10))
						.reduce((a, b) => a + b, 0);
					expect(pctTotal).toBeGreaterThanOrEqual(99);
					expect(pctTotal).toBeLessThanOrEqual(101);

					// Segment efforts — run.route_id gates the Segments section;
					// the planted rank-1 effort renders the .gold pill.
					await expect(
						page.locator('section h2', { hasText: /^Segments$/ }),
					).toBeVisible({ timeout: 10_000 });
					const goldPill = page.locator('.efforts li .rank-pill.gold').first();
					await expect(goldPill).toBeVisible({ timeout: 10_000 });
					await expect(goldPill).toHaveText('#1');
					await expect(
						page.locator('.efforts .effort-meta strong', {
							hasText: 'e2e-Enrichment Climb',
						}),
					).toBeVisible();
				});

				// ── 1b. Owner enriches: a photo + a gear tag ────────────────
				await test.step('owner uploads a photo + tags gear on the run', async () => {
					// Photo: drive the hidden file input directly, fill the
					// pending caption, upload. The tile renders + the row lands.
					const caption = `e2e-enrichment-photo ${Date.now()}`;
					await expect(
						page.getByRole('button', { name: /Add photo/ }),
					).toBeVisible({ timeout: 10_000 });
					await page.locator('input[type="file"]').setInputFiles({
						name: 'e2e-enrichment.png',
						mimeType: 'image/png',
						buffer: ONE_PIXEL_PNG,
					});
					await page.locator('.pending input[type="text"]').fill(caption);
					await page.getByRole('button', { name: 'Upload' }).click();
					await expect(page.locator('.tile').first()).toBeVisible({
						timeout: 15_000,
					});
					await expect(
						page.locator('figcaption', { hasText: caption }),
					).toBeVisible({ timeout: 5_000 });

					// Backend cross-check + capture the Storage path for teardown.
					const { data: photoRows } = await admin
						.from('run_photos')
						.select('storage_path, caption')
						.eq('run_id', runId);
					expect(photoRows?.length).toBe(1);
					expect((photoRows?.[0] as { caption: string }).caption).toBe(caption);
					photoStoragePath = (photoRows?.[0] as { storage_path: string })
						.storage_path;

					// Gear: the saga user has no gear yet, so plant one shoe via
					// service-role (the gear-CRUD UI lives under Settings, out of
					// this run-detail arc), then drive the RunGearChips picker to
					// tag it onto the run — the owner-only flow.
					const { data: gearRow, error: gearErr } = await admin
						.from('gear')
						.insert({
							owner_id: owner!.id,
							kind: 'shoe',
							name: 'e2e-Enrichment Trainer',
						})
						.select('id')
						.single();
					if (gearErr) throw gearErr;
					const gearId = (gearRow as { id: string }).id;

					// Reload so RunGearChips re-fetches and the (now-existing)
					// gear is offered in the picker. The owner sees a "Tag gear"
					// affordance because assigned is empty + canManage is true.
					await page.reload();
					await page
						.locator('.gear-strip .edit-btn', { hasText: /Tag gear|Edit/ })
						.click();
					const picker = page.locator('.modal .picker');
					await expect(picker).toBeVisible({ timeout: 10_000 });
					await page
						.locator('.modal .picker label', { hasText: 'e2e-Enrichment Trainer' })
						.locator('input[type="checkbox"]')
						.check();
					await page
						.locator('.modal')
						.getByRole('button', { name: 'Save', exact: true })
						.click();

					// The chip renders with the gear name after the save round-trip.
					await expect(
						page.locator('.gear-chip .gear-name', {
							hasText: 'e2e-Enrichment Trainer',
						}),
					).toBeVisible({ timeout: 10_000 });

					// Backend cross-check on the run_gear link.
					const { data: linkRows } = await admin
						.from('run_gear')
						.select('gear_id')
						.eq('run_id', runId);
					expect(linkRows?.some((r) => (r as { gear_id: string }).gear_id === gearId))
						.toBe(true);
				});

				// ── 2. Make the run public via the share icon ───────────────
				await test.step('owner makes the run public via the share confirm dialog', async () => {
					// Visibility chip starts Private.
					await expect(
						page.locator('.visibility-chip', { hasText: 'Private' }),
					).toBeVisible({ timeout: 10_000 });

					// Share icon → the Make-public ConfirmDialog (the run is not
					// yet public, so handleShare opens the dialog rather than a
					// silent re-copy). Stub the clipboard write so the headless
					// browser's navigator.clipboard.writeText can't reject and
					// surface a toast instead of the success path.
					await page.evaluate(() => {
						// eslint-disable-next-line @typescript-eslint/no-explicit-any
						(navigator as any).clipboard = {
							writeText: () => Promise.resolve(),
						};
					});
					await page.locator('button[title="Share link"]').click();
					const shareDialog = page.locator('.modal', {
						hasText: 'Make this run public?',
					});
					await expect(shareDialog).toBeVisible({ timeout: 5_000 });
					await shareDialog
						.getByRole('button', { name: 'Make public & copy link' })
						.click();

					// proceedShare flips run.is_public in-page → the chip reads
					// Public without a reload.
					await expect(
						page.locator('.visibility-chip', { hasText: 'Public' }),
					).toBeVisible({ timeout: 10_000 });

					// Backend cross-check: the column actually flipped.
					await expect
						.poll(
							async () => {
								const { data } = await admin
									.from('runs')
									.select('is_public')
									.eq('id', runId)
									.single();
								return (data as { is_public: boolean } | null)?.is_public ?? null;
							},
							{ timeout: 10_000 },
						)
						.toBe(true);
				});
			} finally {
				await ctx.close();
			}

			// ── 3. /share/run/[id] — enriched + clipped public view ─────────
			await test.step('the public share page renders the enriched view from the clipped track, owner affordances absent', async () => {
				// A fresh anon context — the real path a non-owner takes.
				const anonCtx = await browser.newContext({
					storageState: { cookies: [], origins: [] },
				});
				await anonCtx.addInitScript(setConsentAccepted);
				const anonPage = await anonCtx.newPage();
				try {
					// Non-owner track comes through the clip-public-track Edge
					// Function. Stub it with a privacy-clipped polyline (a
					// trimmed, ele-carrying subset of the real track) so the
					// share map + Elevation Profile mount deterministically —
					// this models "the clipped track is what crosses the wire to
					// a non-owner", which is the whole privacy contract.
					const clippedTrack = track.slice(2, 9).map((p) => ({
						lat: p.lat,
						lng: p.lng,
						ele: p.ele,
						ts: p.ts,
					}));
					await anonPage.route(
						'**/functions/v1/clip-public-track',
						(route) =>
							route.fulfill({
								status: 200,
								contentType: 'application/json',
								body: JSON.stringify({ points: clippedTrack }),
							}),
					);

					await anonPage.goto(`/share/run/${runId}`);

					// The public run body renders: the run-meta line (distance /
					// duration / pace / source) is the anchor that the share view
					// mounted at all.
					await expect(anonPage.locator('.run-meta')).toBeVisible({
						timeout: 15_000,
					});

					// Elevation Profile re-derives from the CLIPPED track's `ele`
					// samples (RunShareView gates it on elevations.some(e>0)).
					await expect(
						anonPage.locator('section.card h2', {
							hasText: /^Elevation Profile$/,
						}),
					).toBeVisible({ timeout: 10_000 });

					// Gear chip + photo render on the public face too…
					await expect(
						anonPage.locator('.gear-chip .gear-name', {
							hasText: 'e2e-Enrichment Trainer',
						}),
					).toBeVisible({ timeout: 10_000 });
					await expect(anonPage.locator('.tile').first()).toBeVisible({
						timeout: 10_000,
					});

					// …but EVERY owner-only enrichment affordance is absent for a
					// non-owner: no Add-photo, no photo Delete/Edit, no gear Edit.
					await expect(
						anonPage.getByRole('button', { name: /Add photo/ }),
					).toHaveCount(0);
					await expect(
						anonPage.getByRole('button', { name: 'Delete photo' }),
					).toHaveCount(0);
					await expect(anonPage.locator('.gear-strip .edit-btn')).toHaveCount(0);
				} finally {
					await anonCtx.close();
				}
			});
		} finally {
			// Sweep in dependency order. deleteRun removes the run row +
			// its track/hr blobs (and cascades segment_efforts + run_gear +
			// run_photos rows); the photo Storage object + the route + the
			// saga user's gear/segment are swept explicitly. deleteSagaUsers
			// CASCADE is the final backstop for anything left.
			if (photoStoragePath) {
				await admin.storage
					.from('run-photos')
					.remove([photoStoragePath])
					.catch(() => {});
			}
			if (runId) {
				await deleteRun(runId).catch(() => {});
			}
			if (segmentId) {
				// A PostgREST builder is thenable but has no .catch — await it in
				// a try/catch rather than chaining .catch (which throws "catch is
				// not a function"). Best-effort sweep; the saga CASCADE backstops.
				try {
					await admin.from('segments').delete().eq('id', segmentId);
				} catch {
					/* best-effort */
				}
			}
			if (routeId) {
				await deleteRoute(routeId).catch(() => {});
			}
			if (owner) {
				await deleteSagaUsers([owner]).catch(() => {});
			}
		}
	});
});
