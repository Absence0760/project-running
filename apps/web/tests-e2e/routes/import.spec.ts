import { expect, test } from '@playwright/test';

import { deleteRoute } from '../fixtures/simulate';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

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
});
