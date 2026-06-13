import { expect, test } from '@playwright/test';

import { deleteRoute } from '../fixtures/simulate';
import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

const MULTI_ROUTE_GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="e2e-import-spec" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>e2e-multi-A</name>
    <trkseg>
      <trkpt lat="-33.8915" lon="151.2767"><ele>10</ele></trkpt>
      <trkpt lat="-33.8920" lon="151.2770"><ele>11</ele></trkpt>
      <trkpt lat="-33.8925" lon="151.2773"><ele>12</ele></trkpt>
    </trkseg>
  </trk>
  <trk><name>e2e-multi-B</name>
    <trkseg>
      <trkpt lat="-33.8930" lon="151.2776"><ele>13</ele></trkpt>
      <trkpt lat="-33.8935" lon="151.2780"><ele>14</ele></trkpt>
      <trkpt lat="-33.8940" lon="151.2784"><ele>15</ele></trkpt>
    </trkseg>
  </trk>
  <trk><name>e2e-multi-C</name>
    <trkseg>
      <trkpt lat="-33.8945" lon="151.2788"><ele>16</ele></trkpt>
      <trkpt lat="-33.8950" lon="151.2792"><ele>17</ele></trkpt>
      <trkpt lat="-33.8955" lon="151.2796"><ele>18</ele></trkpt>
    </trkseg>
  </trk>
</gpx>
`;

/**
 * /routes — Import-route modal (ImportRoute component).
 *
 * The route builder (/routes/new) drives MapLibre canvas clicks which
 * are not Playwright-friendly. The Import path is the realistic path
 * for new users — drop a .gpx (or .kml / .tcx / .geojson) and create
 * a route. This pins the parse → preview → Save → goto(/routes/[id])
 * round-trip with a minimal inline GPX fixture.
 */

const MINIMAL_GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="e2e-import-spec" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>e2e-import-route</name>
    <trkseg>
      <trkpt lat="-33.8915" lon="151.2767"><ele>10</ele></trkpt>
      <trkpt lat="-33.8920" lon="151.2770"><ele>11</ele></trkpt>
      <trkpt lat="-33.8925" lon="151.2773"><ele>12</ele></trkpt>
      <trkpt lat="-33.8930" lon="151.2776"><ele>13</ele></trkpt>
      <trkpt lat="-33.8935" lon="151.2780"><ele>14</ele></trkpt>
    </trkseg>
  </trk>
</gpx>
`;

// Minimal KML — exercises the LineString parser path that Google
// Maps / Google Earth exports use. The coords format is
// `lng,lat,alt` (longitude-first, opposite of GPX's lat-first
// attribute order) — a regression that swapped the axes during
// parse would land the route on the wrong side of the globe and
// the next-page route-detail map would render off-screen.
const MINIMAL_KML = `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>e2e-import-kml</name>
      <LineString>
        <coordinates>
          151.2767,-33.8915,10
          151.2770,-33.8920,11
          151.2773,-33.8925,12
          151.2776,-33.8930,13
          151.2780,-33.8935,14
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
`;

// Minimal GeoJSON — same lng-first axis order as KML. The format
// is a single Feature with a LineString geometry. The parser
// pipeline also accepts FeatureCollection; this test covers the
// bare-Feature shape.
const MINIMAL_GEOJSON = JSON.stringify({
	type: 'Feature',
	properties: { name: 'e2e-import-geojson' },
	geometry: {
		type: 'LineString',
		coordinates: [
			[151.2767, -33.8915, 10],
			[151.2770, -33.8920, 11],
			[151.2773, -33.8925, 12],
			[151.2776, -33.8930, 13],
			[151.2780, -33.8935, 14]
		]
	}
});

// A well-formed but empty GPX — no <trk>, no <rte>, no <wpt>.
// The parser falls back through trk → rte → wpt and only throws
// `GPX file contains no track, route, or waypoints` when ALL three
// are absent. ImportRoute catches and renders the message in the
// .error div. A regression that defaulted to "create a zero-point
// route" instead of erroring would slip through.
const EMPTY_GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>empty</name></metadata>
</gpx>
`;

test.describe('/routes — Import route modal', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
	});

	test('GPX import: drop a file → preview → Save → land on /routes/[new-id]', async ({
		page
	}) => {
		const name = `e2e-import-route ${Date.now()}`;

		await page.goto('/routes');
		await page.getByRole('button', { name: /Import/ }).first().click();

		// Modal opens with the drop zone visible.
		const dropZone = page.locator('[aria-label="Route file drop zone"]');
		await expect(dropZone).toBeVisible({ timeout: 5_000 });

		// The hidden <input type="file"> inside the Browse-button
		// label is what setInputFiles drives. Use buffer-based upload
		// so we don't need an actual fixture file on disk.
		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-import-route.gpx',
			mimeType: 'application/gpx+xml',
			buffer: Buffer.from(MINIMAL_GPX, 'utf-8')
		});

		// Single-route preview renders. The auto-derived name is the
		// trk/name "e2e-import-route" — replace it with our timestamped
		// label so we can find this row deterministically.
		const nameInput = page.locator('.preview input[type="text"]').first();
		await expect(nameInput).toBeVisible({ timeout: 5_000 });
		await nameInput.fill(name);

		// "Save Route" submits, then goto(`/routes/<new-id>`).
		await page.getByRole('button', { name: /^Save Route$/ }).click();
		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });

		// Capture the new id for cleanup.
		routeId = page.url().match(/\/routes\/([0-9a-f-]+)$/)![1];

		// Detail page mounts with the chosen name as h1.
		await expect(page.getByRole('heading', { level: 1, name }))
			.toBeVisible({ timeout: 10_000 });

		// Sanity: the row exists in the DB with surface='road' (the
		// import default per ImportRoute.svelte handleSave) and the
		// correct user_id.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('routes')
			.select('user_id, surface, name')
			.eq('id', routeId)
			.single();
		expect(row?.user_id).toBe(USER_A.id);
		expect(row?.surface).toBe('road');
		expect(row?.name).toBe(name);
	});

	test('multi-route GPX import: 3 tracks → multi-preview → import 2 selected', async ({
		page
	}) => {
		// A multi-track GPX should land in the parsed-multi branch
		// (parsed.length > 1). The UI lists each track as a row with
		// a checkbox + a name input. Deselect track B, leave A and C
		// checked, click "Import 2 routes" — exactly 2 routes get
		// created. Pins the multi-import code path that's separate
		// from the single-route handler.
		const stamp = Date.now();
		const nameA = `e2e-multi-A ${stamp}`;
		const nameC = `e2e-multi-C ${stamp}`;
		const admin = getAdminClient();
		const createdIds: string[] = [];

		try {
			await page.goto('/routes');
			await page.getByRole('button', { name: /Import/ }).first().click();
			await page.locator('input[type="file"]').setInputFiles({
				name: 'e2e-multi.gpx',
				mimeType: 'application/gpx+xml',
				buffer: Buffer.from(MULTI_ROUTE_GPX, 'utf-8')
			});

			// Multi-list renders with 3 items.
			await expect(page.locator('.multi-item')).toHaveCount(3, {
				timeout: 10_000
			});

			// Rename A and C with our stamped suffixes; deselect B.
			await page.locator('.multi-item input[type="text"]').nth(0).fill(nameA);
			await page.locator('.multi-item input[type="text"]').nth(2).fill(nameC);
			await page.locator('.multi-item input[type="checkbox"]').nth(1).uncheck();

			// Button label re-renders with the live count.
			await expect(
				page.getByRole('button', { name: /Import 2 routes/ })
			).toBeVisible();
			await page.getByRole('button', { name: /Import 2 routes/ }).click();

			// onimport fires + the modal closes; verify both rows
			// exist via service-role.
			await expect.poll(async () => {
				const { data } = await admin
					.from('routes')
					.select('id, name')
					.in('name', [nameA, nameC]);
				return data?.length ?? 0;
			}, { timeout: 10_000 }).toBe(2);

			const { data: rows } = await admin
				.from('routes')
				.select('id, name')
				.in('name', [nameA, nameC]);
			for (const r of rows ?? []) {
				createdIds.push((r as { id: string }).id);
			}

			// Negative: no row exists for the deselected track B name
			// stamp (the original parsed name was "e2e-multi-B" — left
			// unchanged after deselecting; confirm the un-stamped name
			// also isn't there).
			const { count: bCount } = await admin
				.from('routes')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', USER_A.id)
				.eq('name', 'e2e-multi-B');
			expect(bCount).toBe(0);
		} finally {
			for (const id of createdIds) {
				try {
					await deleteRoute(id);
				} catch (_) {
					/* best-effort */
				}
			}
		}
	});

	test('KML import: lng-first coords parse correctly → route lands at expected lat/lng', async ({
		page
	}) => {
		// Google Maps / Google Earth exports are KML, and KML's
		// coordinate order (`lng,lat,alt`) is opposite to GPX
		// (`lat=..,lon=..` attributes). A regression that swapped the
		// axes during parse would land the route off the globe by
		// 1000s of km — the DB-level lat/lng check catches it.
		const name = `e2e-import-kml ${Date.now()}`;

		await page.goto('/routes');
		await page.getByRole('button', { name: /Import/ }).first().click();
		await expect(
			page.locator('[aria-label="Route file drop zone"]')
		).toBeVisible({ timeout: 5_000 });

		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-import-route.kml',
			mimeType: 'application/vnd.google-earth.kml+xml',
			buffer: Buffer.from(MINIMAL_KML, 'utf-8')
		});

		const nameInput = page.locator('.preview input[type="text"]').first();
		await expect(nameInput).toBeVisible({ timeout: 5_000 });
		await nameInput.fill(name);
		await page.getByRole('button', { name: /^Save Route$/ }).click();
		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });
		routeId = page.url().match(/\/routes\/([0-9a-f-]+)$/)![1];

		await expect(page.getByRole('heading', { level: 1, name }))
			.toBeVisible({ timeout: 10_000 });

		// Backend assertion: the row exists AND the first waypoint
		// landed in the expected hemisphere (negative latitude, +144
		// longitude — Melbourne / Sydney area). A regression that
		// swapped lat/lng during KML parse would land the row at
		// lat=151.X, lng=-33.X (i.e. somewhere in the Pacific east of
		// Russia) and the next assertion would fail.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('routes')
			.select('user_id, name, waypoints')
			.eq('id', routeId)
			.single();
		expect(row?.user_id).toBe(USER_A.id);
		expect(row?.name).toBe(name);
		const wp = (row as { waypoints: Array<{ lat: number; lng: number }> }).waypoints;
		expect(wp.length).toBeGreaterThan(0);
		expect(wp[0].lat).toBeLessThan(0); // southern hemisphere
		expect(wp[0].lat).toBeGreaterThan(-40);
		expect(wp[0].lng).toBeGreaterThan(150);
		expect(wp[0].lng).toBeLessThan(152);
	});

	test('GeoJSON import: bare Feature with LineString geometry parses + saves', async ({
		page
	}) => {
		// GeoJSON's the format Strava + Garmin export when you ask for
		// "raw route data". Same lng-first coord order as KML. A
		// minimal Feature (not wrapped in a FeatureCollection) must
		// still parse — the import library accepts both shapes.
		const name = `e2e-import-geojson ${Date.now()}`;

		await page.goto('/routes');
		await page.getByRole('button', { name: /Import/ }).first().click();
		await expect(
			page.locator('[aria-label="Route file drop zone"]')
		).toBeVisible({ timeout: 5_000 });

		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-import-route.geojson',
			mimeType: 'application/geo+json',
			buffer: Buffer.from(MINIMAL_GEOJSON, 'utf-8')
		});

		const nameInput = page.locator('.preview input[type="text"]').first();
		await expect(nameInput).toBeVisible({ timeout: 5_000 });
		await nameInput.fill(name);
		await page.getByRole('button', { name: /^Save Route$/ }).click();
		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });
		routeId = page.url().match(/\/routes\/([0-9a-f-]+)$/)![1];

		await expect(page.getByRole('heading', { level: 1, name }))
			.toBeVisible({ timeout: 10_000 });

		const admin = getAdminClient();
		const { data: row } = await admin
			.from('routes')
			.select('user_id, waypoints')
			.eq('id', routeId)
			.single();
		expect(row?.user_id).toBe(USER_A.id);
		const wp = (row as { waypoints: Array<{ lat: number; lng: number }> }).waypoints;
		expect(wp.length).toBeGreaterThan(0);
		// Same hemisphere check — GeoJSON lng-first must not flip to
		// lat-first during the import.
		expect(wp[0].lat).toBeLessThan(0);
		expect(wp[0].lng).toBeGreaterThan(150);
	});

	test('GPX with no tracks surfaces an error in the modal + leaves no row', async ({
		page
	}) => {
		// A well-formed GPX that has waypoints but no <trk> is a
		// realistic failure mode — a user exports their "favourite
		// places" from a mapping app and tries to import it as a
		// route. The parser must reject it loudly rather than create
		// a zero-waypoint row. Pin the error UI + that no row lands.
		const beforeCount = await routesCountForUser(USER_A.id);

		await page.goto('/routes');
		await page.getByRole('button', { name: /Import/ }).first().click();
		await expect(
			page.locator('[aria-label="Route file drop zone"]')
		).toBeVisible({ timeout: 5_000 });

		await page.locator('input[type="file"]').setInputFiles({
			name: 'no-tracks.gpx',
			mimeType: 'application/gpx+xml',
			buffer: Buffer.from(EMPTY_GPX, 'utf-8')
		});

		// .error div renders. Don't pin the exact copy (it comes from
		// the parser library and could shift) — just that something
		// surfaced in the error slot, AND the modal didn't crash AND
		// the Save Route button never appeared.
		const errorBox = page.locator('.error');
		await expect(errorBox).toBeVisible({ timeout: 10_000 });
		const errorText = (await errorBox.innerText()).trim();
		expect(errorText.length).toBeGreaterThan(0);

		// Negative shape: no preview rendered, no Save Route button.
		await expect(page.locator('.preview')).toHaveCount(0);
		await expect(
			page.getByRole('button', { name: /^Save Route$/ })
		).toHaveCount(0);

		// No row was inserted.
		const afterCount = await routesCountForUser(USER_A.id);
		expect(afterCount).toBe(beforeCount);
	});

	test('hitting the 30/hour create_route cap on import surfaces the friendly "slow down" toast', async ({
		page
	}) => {
		// The import modal shares saveRoute with the route builder, so the
		// same create_route cap (migration 20260907_001) applies. Pre-plant
		// the counter to 30 so the next saveRoute insert fires the BEFORE
		// INSERT trigger; data.ts rewraps the P0001 via rateLimitErrorMessage
		// and the ImportRoute handleSave catch now routes it through showToast
		// (E4) instead of the inline .error banner. Pin the toast wording so a
		// refactor can't silently revert to the generic "failed to save" copy.
		const admin = getAdminClient();
		const nowS = Math.floor(Date.now() / 1000);
		const windowStartS = Math.floor(nowS / 3600) * 3600;
		const windowStart = new Date(windowStartS * 1000).toISOString();
		await admin.from('rate_limits').upsert({
			user_id: USER_A.id,
			bucket: 'create_route',
			window_start: windowStart,
			count: 30
		});

		try {
			await page.goto('/routes');
			await page.getByRole('button', { name: /Import/ }).first().click();
			await expect(
				page.locator('[aria-label="Route file drop zone"]')
			).toBeVisible({ timeout: 5_000 });

			await page.locator('input[type="file"]').setInputFiles({
				name: 'e2e-import-ratelimited.gpx',
				mimeType: 'application/gpx+xml',
				buffer: Buffer.from(MINIMAL_GPX, 'utf-8')
			});

			const nameInput = page.locator('.preview input[type="text"]').first();
			await expect(nameInput).toBeVisible({ timeout: 5_000 });
			await nameInput.fill(`rate-limited import ${Date.now()}`);

			await page.getByRole('button', { name: /^Save Route$/ }).click();

			const errorToast = page.locator('.toast-error');
			await expect(errorToast).toBeVisible({ timeout: 10_000 });
			await expect(errorToast).toHaveText(/creating routes too quickly/i);
			// Negative pin: generic fallback + raw exception must not leak.
			await expect(page.getByText('Failed to save route')).toHaveCount(0);
			await expect(
				page.getByText(/rate limit exceeded for create_route/i)
			).toHaveCount(0);
		} finally {
			await resetRateLimit(USER_A.id, 'create_route');
		}
	});

	test('cancel the modal with X button: closes without import or error toast', async ({
		page
	}) => {
		// Drop a valid file but then close the modal via the X button
		// before pressing Save. The drop-zone offered a preview; cancel
		// must discard it AND not create a row AND not surface a
		// "Failed to save route" error (regression where unmount
		// triggered the catch block).
		const beforeCount = await routesCountForUser(USER_A.id);

		await page.goto('/routes');
		await page.getByRole('button', { name: /Import/ }).first().click();
		await expect(
			page.locator('[aria-label="Route file drop zone"]')
		).toBeVisible({ timeout: 5_000 });

		await page.locator('input[type="file"]').setInputFiles({
			name: 'e2e-cancel.gpx',
			mimeType: 'application/gpx+xml',
			buffer: Buffer.from(MINIMAL_GPX, 'utf-8')
		});
		// Preview renders, signalling parse success.
		await expect(page.locator('.preview')).toBeVisible({ timeout: 5_000 });

		// Modal's close button — `.modal-close` is the canonical
		// global class per the CLAUDE.md modal contract.
		await page.locator('.modal-close').click();
		await expect(page.locator('.modal')).not.toBeVisible({ timeout: 5_000 });

		// No row landed.
		const afterCount = await routesCountForUser(USER_A.id);
		expect(afterCount).toBe(beforeCount);
	});
});

/** Count routes owned by `userId` via service-role. */
async function routesCountForUser(userId: string): Promise<number> {
	const admin = getAdminClient();
	const { count } = await admin
		.from('routes')
		.select('id', { count: 'exact', head: true })
		.eq('user_id', userId);
	return count ?? 0;
}
