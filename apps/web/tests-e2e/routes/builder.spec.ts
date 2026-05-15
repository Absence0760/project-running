import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes/new — the route builder page.
 *
 * The builder hosts a MapLibre canvas (RouteBuilder component) plus a
 * right-hand sidebar with mode / style / distance-target controls and
 * Calculate / Save / GPX action buttons. Real OSRM + MapTiler keys
 * are not available in CI; these tests pin the *control surface* of
 * the page (button states, mode toggles, gating) without driving the
 * map canvas directly. The pure-logic side (routing.ts, elevation.ts,
 * geocoding.ts, snap-to-start, route_overlap) is covered by Dart
 * + node:test unit tests in `apps/mobile_android/test/` and
 * `apps/web/src/lib/`.
 *
 * Reachable only to authed users — the layout's auth guard would
 * redirect /routes/new to /login for anon. We sign in as USER_A.
 */

test.describe('/routes/new — Route Builder control surface', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('page mounts with the canonical h1 + sidebar controls', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		await expect(page.getByRole('heading', { name: 'Route Builder', level: 1 }))
			.toBeVisible({ timeout: 10_000 });
		// Mode toggle (road / trail) — both buttons present.
		await expect(page.getByRole('button', { name: /Road/, exact: false })).toBeVisible();
		await expect(page.getByRole('button', { name: /Trail/, exact: false })).toBeVisible();
		// Three style toggles.
		await expect(page.getByRole('button', { name: 'Streets' })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Satellite' })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Terrain' })).toBeVisible();
	});

	test('mode toggle: road is active by default, click Trail flips the active class', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const road = page.locator('.mode-btn', { hasText: 'Road' });
		const trail = page.locator('.mode-btn', { hasText: 'Trail' });
		// Default active state matches `mode = 'road'` in the script.
		await expect(road).toHaveClass(/active/);
		await expect(trail).not.toHaveClass(/active/);

		await trail.click();
		await expect(trail).toHaveClass(/active/);
		await expect(road).not.toHaveClass(/active/);

		// Toggle back — confirms the state isn't write-once.
		await road.click();
		await expect(road).toHaveClass(/active/);
		await expect(trail).not.toHaveClass(/active/);
	});

	test('map-style toggle cycles streets → satellite → terrain → streets', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const streets = page.locator('.style-btn', { hasText: 'Streets' });
		const satellite = page.locator('.style-btn', { hasText: 'Satellite' });
		const terrain = page.locator('.style-btn', { hasText: 'Terrain' });

		await expect(streets).toHaveClass(/active/);
		await satellite.click();
		await expect(satellite).toHaveClass(/active/);
		await expect(streets).not.toHaveClass(/active/);
		await terrain.click();
		await expect(terrain).toHaveClass(/active/);
		await expect(satellite).not.toHaveClass(/active/);
		await streets.click();
		await expect(streets).toHaveClass(/active/);
	});

	test('Calculate + Save + GPX buttons disabled before any waypoint exists', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		// `disabled={waypointCount < 2}` on Calculate. With zero
		// waypoints (the freshly-mounted state) Calculate is disabled.
		await expect(page.getByRole('button', { name: /Calculate Route/ }))
			.toBeDisabled();
		// `disabled={!routed || saving}` on Save. Routed is false at
		// mount → Save disabled.
		await expect(page.getByRole('button', { name: /Save Route/ }))
			.toBeDisabled();
		// `disabled={!routed}` on GPX export.
		await expect(page.getByRole('button', { name: 'GPX' })).toBeDisabled();
	});

	test('Undo + Clear + Out-and-back disabled at zero waypoints', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		// All three editor toolbar buttons gate on waypointCount.
		const toolbar = page.locator('.btn.btn-ghost');
		// At least three .btn-ghost buttons exist; iterate and assert
		// the first three are disabled. Don't pin by name — the buttons
		// are icon-only.
		const count = Math.min(3, await toolbar.count());
		for (let i = 0; i < count; i++) {
			await expect(toolbar.nth(i)).toBeDisabled();
		}
	});

	test('distance-target panel toggles open + the four presets set the slider', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		// Default state: distance-target panel collapsed. Find the
		// toggle button — it has class .style-btn or similar; use the
		// canonical heading next to the slider as the gate.
		const slider = page.locator('input.target-slider');
		// Slider may already be visible depending on showDistanceTarget
		// default. Either way the presets land it on the labelled km.
		if (!(await slider.isVisible({ timeout: 1_000 }).catch(() => false))) {
			await page.locator('button', { hasText: /Distance target|generate/i }).first().click();
			await expect(slider).toBeVisible({ timeout: 5_000 });
		}

		// Four presets — 5k / 10k / Half / Full → 5 / 10 / 21.1 / 42.2 km.
		// Assert on the displayed .target-value text (the bound variable)
		// rather than the slider's step-quantised value attribute (which
		// rounds 21.1 / 42.2 to the nearest 0.5 boundary). The display
		// reads `${targetKm} km`.
		const display = page.locator('.target-value');
		for (const [label, expected] of [
			['5k', '5 km'],
			['10k', '10 km'],
			['Half', '21.1 km'],
			['Full', '42.2 km']
		] as const) {
			await page.getByRole('button', { name: label, exact: true }).click();
			await expect(display).toHaveText(expected);
		}
	});

	test('route name input is bindable + empty by default', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		const nameInput = page.getByPlaceholder('My Route');
		await expect(nameInput).toBeVisible();
		await expect(nameInput).toHaveValue('');
		await nameInput.fill('e2e route');
		await expect(nameInput).toHaveValue('e2e route');
	});

	test('keyboard shortcuts hint is visible on initial load', async ({ page }) => {
		// The .shortcuts-hint affordance is the discoverability hook
		// for power users. A regression that hid it removes the
		// keyboard-power-user signal.
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.shortcuts-hint')).toBeVisible({ timeout: 10_000 });
	});

	test('anon visitor is auth-walled to /login', async ({ browser }) => {
		// /routes/new is not in publicPaths. Use a fresh context with
		// no storage state to simulate anon.
		const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		const anon = await ctx.newPage();
		try {
			await anon.goto('/routes/new');
			await anon.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});
});
