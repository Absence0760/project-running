import { expect, test } from '@playwright/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Routes — build → save → detail → GPX export JOURNEY (one route's life,
 * threaded create → My-routes → detail render → BOTH GPX exports).
 *
 * Distinct from the single-surface specs already covering these seams:
 *   - routes/builder.spec.ts  — drives /routes/new (MapLibre + OSRM) and
 *     exports GPX/KML from the BUILDER, before a route ever persists.
 *   - routes/markers.spec.ts  — the RouteMarkerEditor list/save in isolation.
 *   - routes/roadbook.spec.ts — the GPX+markers export on the /roadbook
 *     SUB-page (the crew-sheet surface), not the route-detail page.
 *   - routes/detail.spec.ts   — owner ops on /routes/[id] in isolation.
 * This journey is the only one that walks a persisted route from the
 * My-routes list, through the /routes/[id] detail stats, and out through
 * the route-detail page's OWN two export affordances — the plain "GPX"
 * (line-only `<trk>`) and the "GPX + markers" button that only appears
 * once a course marker exists, verifying the marker rides out as a `<wpt>`.
 *
 * CREATE path: seeded via the service-role admin client rather than driven
 * through the /routes/new builder. The builder is MapLibre + OSRM and
 * map-heavy (builder.spec.ts already proves that seam end-to-end); routes
 * also have NO UI delete affordance, so create + teardown both go through
 * the admin client (mirroring route-lifecycle-journey.spec.ts). Every
 * assertion between create and delete is driven through the real UI.
 *
 * The export is fully CLIENT-SIDE: src/routes/routes/[id]/+page.svelte builds
 * the GPX in-page (toGpx / toRouteGpxWithMarkers from $lib/routes) and triggers
 * a Blob download via downloadFile(). So there is no network response to
 * capture — the GPX is read off the browser `download` event's stream.
 *
 * Backend cross-check: the seeded route + marker rows are owned by USER_A.
 * Teardown deletes the route (route_markers cascade via FK).
 */

test.describe('Routes — build → save → detail → GPX export', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Unique per run so reruns on a dirty DB never collide and the
	// /routes search box narrows to exactly this row.
	let routeId = '';
	let routeName = '';

	test.beforeEach(async ({ context }) => {
		// The seeded user's storageState carries accepted cookie consent,
		// but inject it on every navigation too so the GDPR banner never
		// floats over the map / actions row and eats a click.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});

		// create_route is rate-limited (30/hour/user, migration 20260907_001).
		// A shared-USER_A shard can blow through the cap; reset the window so
		// the seed reads as a clean create.
		await resetRateLimit(USER_A.id, 'create_route');

		const admin = getAdminClient();
		routeId = crypto.randomUUID();
		routeName = `E2E export route ${Date.now()}`;

		// A short Melbourne-area polyline (mirrors the seed's public route
		// shape) so the detail map + key-stats + the line-only GPX all have
		// real geometry. The routes_geom_trigger derives `geom` from
		// waypoints on insert, which the route_markers_position_trigger then
		// uses to compute the marker's position_m.
		const { error } = await admin.from('routes').insert({
			id: routeId,
			user_id: USER_A.id,
			name: routeName,
			distance_m: 8000,
			elevation_m: 60,
			surface: 'road',
			is_public: false,
			waypoints: [
				{ lat: -37.82, lng: 144.97, ele: 20 },
				{ lat: -37.818, lng: 144.972, ele: 25 },
				{ lat: -37.816, lng: 144.974, ele: 30 },
				{ lat: -37.814, lng: 144.976, ele: 35 },
				{ lat: -37.812, lng: 144.978, ele: 40 },
				{ lat: -37.81, lng: 144.98, ele: 45 }
			]
		});
		if (error) {
			throw new Error(`route-generate-export-journey: route seed failed: ${error.message}`);
		}

		// One aid-station course marker sitting on the line, carrying a
		// cutoff + services in `meta`. toRouteGpxWithMarkers emits it as a
		// `<wpt>` with kind→`<sym>Water Source</sym>` and a `<desc>` built
		// from the cutoff + services — so the export carries more than the
		// bare line, and the "GPX + markers" button is rendered at all
		// (the button is gated on routeMarkers.length > 0).
		const { error: mErr } = await admin.from('route_markers').insert({
			route_id: routeId,
			user_id: USER_A.id,
			kind: 'aid_station',
			label: 'Aid 1',
			lat: -37.816,
			lng: 144.974,
			meta: { cutoff_clock: '09:30', services: ['water', 'gels'] }
		});
		if (mErr) {
			throw new Error(`route-generate-export-journey: marker seed failed: ${mErr.message}`);
		}
	});

	test.afterEach(async () => {
		// Routes have no UI delete; the canonical delete path is service-role
		// / SQL. Sweep the route here (route_markers cascade via the FK).
		if (routeId) {
			await getAdminClient().from('routes').delete().eq('id', routeId);
		}
	});

	test('a saved route lists, opens, and exports a GPX track (line + course-marker waypoint)', async ({
		page
	}) => {
		await test.step('1. backend: the seeded route + marker are owned by USER_A', async () => {
			const admin = getAdminClient();
			const { data: routeRow } = await admin
				.from('routes')
				.select('user_id, distance_m, surface')
				.eq('id', routeId)
				.single();
			expect(routeRow?.user_id).toBe(USER_A.id);
			expect(routeRow?.distance_m).toBe(8000);

			// The marker's position_m is trigger-derived from routes.geom —
			// proves the geom trigger fired and the GPX `<wpt>` is anchored
			// on the line, not floating.
			const { data: markerRow } = await admin
				.from('route_markers')
				.select('user_id, kind, position_m')
				.eq('route_id', routeId)
				.single();
			expect(markerRow?.user_id).toBe(USER_A.id);
			expect(markerRow?.kind).toBe('aid_station');
			expect(markerRow?.position_m).not.toBeNull();
		});

		await test.step('2. the saved route appears in My routes on /routes', async () => {
			await page.goto('/routes');
			// /routes fetches My-routes client-side in onMount; the page
			// paints a skeleton then swaps in the .route-card grid. The
			// auto-waiting toBeVisible polls for the cards — no
			// waitForLoadState('networkidle') (the page holds an open
			// Supabase realtime socket and never reaches network-idle).
			await expect(page.locator('.route-card').first()).toBeVisible({
				timeout: 10_000
			});
			await page.getByLabel('Search routes').fill(routeName);
			const card = page.locator(`.route-card[href$="${routeId}"]`);
			await expect(card).toBeVisible({ timeout: 10_000 });
			await expect(card).toContainText(routeName);
		});

		await test.step('3. /routes/[id] renders the name, key stats, and the map', async () => {
			await page.goto(`/routes/${routeId}`);

			await expect(
				page.getByRole('heading', { name: routeName, level: 1 })
			).toBeVisible({ timeout: 10_000 });

			const keyStats = page.locator('.key-stats');
			await expect(keyStats).toBeVisible();
			await expect(keyStats).toContainText('Distance');
			await expect(keyStats).toContainText('road');

			// MapLibre map container mounts.
			await expect(page.locator('.run-map').first()).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('4. the plain "GPX" export downloads a line-only GPX track', async () => {
			// The GPX button is always present on the detail page and builds
			// the GPX client-side (toGpx) → Blob download. Capture it off the
			// browser download event (no network round-trip exists).
			const [download] = await Promise.all([
				page.waitForEvent('download'),
				page.getByRole('button', { name: 'GPX', exact: true }).click()
			]);
			expect(download.suggestedFilename()).toMatch(/\.gpx$/);

			const gpx = await readDownload(download);
			// A valid GPX document with the route line as a <trk> of <trkpt>s.
			expect(gpx).toContain('<gpx');
			expect(gpx).toContain('<trk>');
			// One <trkpt> per seeded waypoint (6).
			expect((gpx.match(/<trkpt\b/g) ?? []).length).toBe(6);
			// The line-only export carries NO course-marker waypoint.
			expect(gpx).not.toContain('<wpt');
		});

		await test.step('5. the "GPX + markers" export carries the course marker as a <wpt>', async () => {
			// This button is rendered only because the route has a marker
			// (routeMarkers.length > 0). It builds via toRouteGpxWithMarkers,
			// emitting the marker as a <wpt> (with a kind→<sym> + a <desc>
			// from the cutoff + services) BEFORE the <trk>, per GPX 1.1.
			const markerBtn = page.getByRole('button', { name: 'GPX + markers' });
			await expect(markerBtn).toBeVisible({ timeout: 10_000 });

			const [download] = await Promise.all([
				page.waitForEvent('download'),
				markerBtn.click()
			]);
			expect(download.suggestedFilename()).toMatch(/_with_markers\.gpx$/);

			const gpx = await readDownload(download);
			// The route line is still present as a track…
			expect(gpx).toContain('<trk>');
			expect((gpx.match(/<trkpt\b/g) ?? []).length).toBe(6);
			// …and the seeded aid station rides out as a course waypoint.
			expect(gpx).toContain('<wpt');
			expect(gpx).toContain('<name>Aid 1</name>');
			expect(gpx).toContain('<sym>Water Source</sym>');
			// The cutoff + services land in the waypoint <desc>.
			expect(gpx).toContain('Cutoff 09:30');
			expect(gpx).toContain('Services: water, gels');

			// GPX 1.1 schema ordering: the <wpt> must precede the <trk>.
			expect(gpx.indexOf('<wpt')).toBeLessThan(gpx.indexOf('<trk>'));
		});
	});
});

/** Drain a Playwright download's stream to a UTF-8 string. */
async function readDownload(
	download: import('@playwright/test').Download
): Promise<string> {
	const stream = await download.createReadStream();
	const chunks: Buffer[] = [];
	for await (const chunk of stream) chunks.push(Buffer.from(chunk));
	return Buffer.concat(chunks).toString('utf8');
}
