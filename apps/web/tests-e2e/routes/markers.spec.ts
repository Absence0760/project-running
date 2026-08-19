import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — course markers (aid stations, cutoffs, …) via the
 * RouteMarkerEditor component (migration 20270129_001).
 *
 * The editor reads through the route_markers_for_viewer RPC, renders an
 * ordered course-schedule list, and (owner-only) lets the user drop a pin
 * on the map, pick a kind, and save. Markers are owned by the route owner;
 * position_m is derived server-side from routes.geom.
 */

async function insertOwnedRoute(): Promise<string> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	const { error } = await admin.from('routes').insert({
		id,
		user_id: USER_A.id,
		name: 'E2E course-markers route',
		waypoints: [
			{ lat: 51.5, lng: -0.12 },
			{ lat: 51.51, lng: -0.13 }
		],
		distance_m: 5_000,
		is_public: false
	});
	if (error) throw new Error(`insertOwnedRoute failed: ${error.message}`);
	return id;
}

async function insertMarker(
	routeId: string,
	kind: string,
	label: string,
	lat: number,
	lng: number,
	meta: Record<string, unknown> = {}
): Promise<void> {
	const { error } = await getAdminClient().from('route_markers').insert({
		route_id: routeId,
		user_id: USER_A.id,
		kind,
		label,
		lat,
		lng,
		meta
	});
	if (error) throw new Error(`insertMarker failed: ${error.message}`);
}

test.describe('/routes/[id] — course markers', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId); // cascade clears route_markers
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
	});

	test('schedule list shows seeded markers ordered by distance with detail', async ({ page }) => {
		routeId = await insertOwnedRoute();
		// Aid near the END (larger position_m), cutoff near the START
		// (smaller) — so the schedule sorts cutoff before aid.
		await insertMarker(routeId, 'aid_station', 'Aid 2', 51.5098, -0.1298, {
			services: ['water', 'food']
		});
		await insertMarker(routeId, 'cutoff', 'Gate', 51.5005, -0.1205, {
			cutoff_clock: '14:30'
		});

		await page.goto(`/routes/${routeId}`);

		const list = page.locator('.markers-list');
		await expect(list).toBeVisible();
		const rows = list.locator('.marker-row');
		await expect(rows).toHaveCount(2);

		// Distance ordering: cutoff (near start) first, aid (near end) second.
		await expect(rows.nth(0).locator('.marker-label')).toHaveText('Gate');
		await expect(rows.nth(1).locator('.marker-label')).toHaveText('Aid 2');

		// Kind labels + detail lines.
		await expect(rows.nth(0).locator('.marker-kind')).toHaveText('Cut-off');
		await expect(rows.nth(0).locator('.marker-detail')).toContainText('14:30');
		await expect(rows.nth(1).locator('.marker-kind')).toHaveText('Aid station');
		await expect(rows.nth(1).locator('.marker-detail')).toContainText('Water');
		await expect(rows.nth(1).locator('.marker-detail')).toContainText('Food');
	});

	test('a long marker label is clipped to one line, not overflowed', async ({ page }) => {
		routeId = await insertOwnedRoute();
		// Exactly the 120-char DB max (route_markers_label_check) — the longest
		// label a user can save, which must still clip rather than overflow.
		const longLabel = 'Aid Station Emigrant Pass Ridge Crest Water Refill '.repeat(3).slice(0, 120);
		await insertMarker(routeId, 'aid_station', longLabel, 51.505, -0.125, {
			services: ['water']
		});

		await page.goto(`/routes/${routeId}`);

		const label = page.locator('.markers-list .marker-row .marker-label').first();
		await expect(label).toBeVisible();
		// The fix: shrink-and-clip to one line so a long name can't overflow
		// the row or crush the along-route distance chip beside it.
		await expect(label).toHaveCSS('text-overflow', 'ellipsis');
		await expect(label).toHaveCSS('white-space', 'nowrap');
		// The label genuinely exceeds its box here, so the clip is doing real
		// work — guards against a future change that widens the row instead.
		const clipped = await label.evaluate((el) => el.scrollWidth > el.clientWidth);
		expect(clipped).toBe(true);
	});

	test('owner adds a marker by clicking the map', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await page.goto(`/routes/${routeId}`);

		// Empty-state copy until a marker exists.
		await expect(page.locator('.markers-empty')).toBeVisible();

		await page.getByRole('button', { name: 'Add marker' }).click();

		// Drop the pin: click the map canvas once it has loaded.
		const canvas = page.locator('.map-panel .maplibregl-canvas');
		await expect(canvas).toBeVisible();
		const box = await canvas.boundingBox();
		if (!box) throw new Error('map canvas has no bounding box');
		await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);

		// Name it and save.
		await page.getByLabel('Name').fill('Halfway aid');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		const rows = page.locator('.markers-list .marker-row');
		await expect(rows).toHaveCount(1);
		await expect(rows.first().locator('.marker-label')).toHaveText('Halfway aid');
	});

	test('owner adds a marker by typing coordinates, keyboard-only', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await page.goto(`/routes/${routeId}`);

		await page.getByRole('button', { name: 'Add marker' }).click();

		await page.getByLabel('Name').fill('Typed aid');

		// An out-of-range latitude blocks the save with the validation message.
		await page.getByLabel('Latitude').fill('999');
		await page.getByLabel('Longitude').fill('-0.121');
		await expect(
			page.getByText('Enter a valid latitude (-90 to 90) and longitude (-180 to 180).')
		).toBeVisible();
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('.markers-list .marker-row')).toHaveCount(0);

		// Valid coordinates save without any map interaction.
		await page.getByLabel('Latitude').fill('51.5055');
		await page.getByLabel('Latitude').press('Tab');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		const rows = page.locator('.markers-list .marker-row');
		await expect(rows).toHaveCount(1);
		await expect(rows.first().locator('.marker-label')).toHaveText('Typed aid');
	});

	test('owner sees draggable pins on the map and a drag-to-move hint', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'aid_station', 'Aid 1', 51.505, -0.125, {
			services: ['water']
		});

		await page.goto(`/routes/${routeId}`);

		// The owner gets the drag affordance copy + a draggable DOM pin
		// rendered over the map (not the static circle layer).
		await expect(page.getByText('Tip: drag a pin on the map to move it.')).toBeVisible();
		const pin = page.locator('.map-panel .course-pin');
		await expect(pin).toHaveCount(1);
		await expect(pin.locator('.course-pin-label')).toHaveText('Aid 1');
	});

	test('owner drags a pin to move it and the change persists', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'aid_station', 'Aid 1', 51.505, -0.125, {
			services: ['water']
		});

		await page.goto(`/routes/${routeId}`);

		const pin = page.locator('.map-panel .course-pin');
		await expect(pin).toBeVisible();
		// The pin renders before the map's entrance fitBounds animation
		// finishes, and MapLibre reprojects it every camera frame — a
		// boundingBox read taken mid-animation is stale by mouse.down(),
		// which then lands on empty canvas and no drag ever starts (the
		// intermittent shard failure in CI run 28707481878). Wait for the
		// settled-camera stamp RunMap sets on `idle`.
		await expect(page.locator('.map-panel [data-map-idle="true"]')).toBeAttached({
			timeout: 15_000
		});
		const from = await pin.boundingBox();
		if (!from) throw new Error('pin has no bounding box');

		// Drag the pin a little. MapLibre needs intermediate moves to treat
		// it as a drag, not a click.
		await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
		await page.mouse.down();
		await page.mouse.move(from.x + 60, from.y + 40, { steps: 8 });
		await page.mouse.move(from.x + 90, from.y + 70, { steps: 8 });
		await page.mouse.up();

		// The move persists immediately (no form) → confirmation toast.
		await expect(page.getByText('Marker moved.')).toBeVisible({ timeout: 10_000 });

		// And it survives a reload (server-side persisted, not just optimistic).
		await page.reload();
		await expect(page.locator('.map-panel .course-pin')).toHaveCount(1);
	});

	test('schedule shows a Target chip for a marker carrying a target time', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'aid_station', 'Aid 2', 51.5098, -0.1298, {
			services: ['water'],
			target_elapsed_s: 6300
		});

		await page.goto(`/routes/${routeId}`);

		const detail = page.locator('.markers-list .marker-row .marker-detail');
		// Services and the target render side by side — the target must not
		// displace the kind-specific detail.
		await expect(detail).toContainText('Water');
		await expect(detail).toContainText('Target 1:45:00');
	});

	test('schedule shows a Target chip for a clock-only target', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'note', 'Turn', 51.5005, -0.1205, {
			note: 'Sharp left',
			target_clock: '14:30'
		});

		await page.goto(`/routes/${routeId}`);

		const detail = page.locator('.markers-list .marker-row .marker-detail');
		await expect(detail).toContainText('Sharp left');
		await expect(detail).toContainText('Target 14:30');
	});

	test('owner sets a target time via the editor and it persists across reload', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'cutoff', 'Gate', 51.5005, -0.1205, {
			cutoff_clock: '14:30'
		});

		await page.goto(`/routes/${routeId}`);

		await page.locator('.markers-list .marker-row').first().getByTitle('Edit marker').click();
		await page.getByLabel('Target time (elapsed)').fill('1:45:00');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		const detail = page.locator('.markers-list .marker-row .marker-detail');
		await expect(detail).toContainText('Target 1:45:00');
		// The pre-existing cutoff survives the meta round-trip.
		await expect(detail).toContainText('14:30');

		// Server-side persisted, not just optimistic.
		await page.reload();
		await expect(
			page.locator('.markers-list .marker-row .marker-detail')
		).toContainText('Target 1:45:00');
	});

	test('mm:ss and bare-minute target inputs normalise to elapsed time', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'note', 'Turn', 51.5005, -0.1205, {
			note: 'Sharp left'
		});

		await page.goto(`/routes/${routeId}`);

		await page.locator('.markers-list .marker-row').first().getByTitle('Edit marker').click();
		await page.getByLabel('Target time (elapsed)').fill('90');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(
			page.locator('.markers-list .marker-row .marker-detail')
		).toContainText('Target 1:30:00');

		await page.locator('.markers-list .marker-row').first().getByTitle('Edit marker').click();
		await page.getByLabel('Target time (elapsed)').fill('25:00');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(
			page.locator('.markers-list .marker-row .marker-detail')
		).toContainText('Target 25:00');
	});

	test('an invalid target blocks the save with a validation toast', async ({ page }) => {
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'aid_station', 'Aid 1', 51.505, -0.125, {});

		await page.goto(`/routes/${routeId}`);

		await page.locator('.markers-list .marker-row').first().getByTitle('Edit marker').click();
		await page.getByLabel('Target time (elapsed)').fill('abc');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(page.getByText('Enter the target time as h:mm:ss')).toBeVisible();
		// The form stays open (save rejected) and the row gained no target.
		await expect(page.getByLabel('Target time (elapsed)')).toBeVisible();
		await expect(page.locator('.markers-list .marker-row').first()).not.toContainText('Target');
	});

	// The marker delete lost its ConfirmDialog when it moved to undo, but the
	// guard this test really carries is ConfirmDialog's OWN default cancel
	// label — it used to be a hardcoded English 'Cancel' that leaked into
	// every locale. Retargeted at the share confirm on the same page, which
	// also omits cancelLabel, so the fallback stays pinned.
	test('a ConfirmDialog cancel button is localized, not a hardcoded English label', async ({
		browser
	}) => {
		routeId = await insertOwnedRoute();

		// A German browser negotiates the `de` catalogue on load.
		const context = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'de-DE'
		});
		const page = await context.newPage();
		await page.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
			// The seeded storageState may carry a stored locale that wins over
			// the browser locale — force German so the fallback is exercised.
			localStorage.setItem('locale', 'de');
		});
		await page.goto(`/routes/${routeId}`);

		// The share affordance on a private route opens the make-public
		// confirm, which passes no cancelLabel.
		await page.getByTestId('route-share-btn').click();
		const dialog = page.getByTestId('share-confirm-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });

		// Before the fix ConfirmDialog defaulted cancelLabel to a hardcoded
		// English "Cancel"; now it falls back to m('common.cancel') → German.
		await expect(page.locator('.modal .btn-secondary')).toHaveText('Abbrechen');

		await context.close();
	});

	test('owner deletes a marker, and Undo puts it back untouched', async ({ page }) => {
		const admin = getAdminClient();
		routeId = await insertOwnedRoute();
		await insertMarker(routeId, 'note', 'Locked gate', 51.505, -0.125, {
			note: 'Climb over on the left'
		});

		await page.goto(`/routes/${routeId}`);

		const rows = page.locator('.markers-list .marker-row');
		await expect(rows).toHaveCount(1);

		// One click, no confirm: the row leaves the list and the delete is
		// held for the undo window (decisions § 514).
		await rows.first().getByTitle('Delete').click();
		await expect(page.locator('.markers-empty')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('undo-bar')).toBeVisible();

		await page.getByTestId('undo-action').click();
		await expect(page.locator('.markers-list .marker-row')).toHaveCount(1, { timeout: 5_000 });
		// Asserted after the undo so it cannot race the window: the marker
		// never left the table, so its server-derived position_m is intact.
		const { data: survived } = await admin
			.from('route_markers')
			.select('id')
			.eq('route_id', routeId);
		expect((survived ?? []).length).toBe(1);

		// Dismiss commits the held delete.
		await page.locator('.markers-list .marker-row').first().getByTitle('Delete').click();
		await expect(page.getByTestId('undo-bar')).toBeVisible();
		await page.getByTestId('undo-dismiss').click();
		await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 5_000 });
		await expect(page.locator('.markers-list')).toHaveCount(0);
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('route_markers')
						.select('id')
						.eq('route_id', routeId);
					return (data ?? []).length;
				},
				{ timeout: 5_000 }
			)
			.toBe(0);
	});
});
