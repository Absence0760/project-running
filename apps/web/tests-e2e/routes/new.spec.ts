import { expect, test } from '@playwright/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/new — Save-Route round-trip.
 *
 * routes/builder.spec.ts pins the sidebar control surface (mode +
 * style toggles, button gating, save-modal contract). This file
 * closes the end-to-end save path the builder never exercised:
 * drop waypoints → calculate → fill the modal (name + description +
 * Public) → submit → land on /routes/<id> → row exists with the
 * fields the modal collected.
 *
 * OSRM is not reachable in CI and the MapLibre canvas isn't easy to
 * drive. We drop waypoints via the component's exported addWaypoint
 * API (same bridge pattern as settings/privacy-zones-picker.spec.ts)
 * and force-enable the Save button so the modal flow runs without
 * needing real routing.
 */

test.describe('/routes/new — save round-trip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedRouteId: string | null = null;

	test.afterEach(async () => {
		if (plantedRouteId) {
			try {
				await deleteRoute(plantedRouteId);
			} catch (_) {
				/* best-effort */
			}
			plantedRouteId = null;
		}
	});

	test('drop waypoints + fill modal + submit → /routes/[id] with persisted name, description, public flag', async ({
		page
	}) => {
		const uniqueName = `e2e save round-trip ${Date.now()}`;
		const description = 'e2e route description';

		await page.goto('/routes/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Route Builder' }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		// The Save button is disabled until `routed === true` (set after
		// a successful Calculate-route call). OSRM isn't reachable in
		// the test environment, so we force-enable the gate after
		// dropping enough waypoints to satisfy the data shape.
		await page.evaluate(async () => {
			// Wait for the map to settle so the builder has rendered.
			await new Promise((r) => setTimeout(r, 100));
		});

		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeDisabled();
		await saveBtn.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await saveBtn.click();

		const modal = page.locator('.modal', { hasText: 'Save route' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByPlaceholder('My Route').fill(uniqueName);
		await modal.locator('textarea').fill(description);
		await modal.locator('input[type="checkbox"]').check();
		await expect(modal.locator('input[type="checkbox"]')).toBeChecked();

		// Submit. `canSave = routed && routeName.trim().length > 0` — we
		// already flipped routed via evaluate; the name fill enables the
		// other half. Force-enable the submit too in case `canSave`'s
		// reactive read of `routed` lagged the DOM mutation.
		const submit = modal.getByRole('button', { name: /Save route/ });
		await submit.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await submit.click();

		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });
		plantedRouteId = page.url().match(/\/routes\/([0-9a-f-]+)$/)![1];

		await expect(page.getByRole('heading', { level: 1, name: uniqueName }))
			.toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.route-description')).toHaveText(description);
		await expect(page.locator('.btn', { hasText: 'Public' })).toBeVisible();

		const admin = getAdminClient();
		const { data: row } = await admin
			.from('routes')
			.select('id, name, description, is_public, user_id')
			.eq('id', plantedRouteId)
			.single();
		expect(row).not.toBeNull();
		expect(row!.name).toBe(uniqueName);
		expect(row!.description).toBe(description);
		expect(row!.is_public).toBe(true);
		expect(row!.user_id).toBe(USER_A.id);
	});

	test('hitting the 30/hour create_route cap surfaces the friendly "slow down" toast', async ({
		page,
	}) => {
		// Mirror of the clubs/new rate-limit pin (clubs/new.spec.ts) on
		// the routes side. Pre-plant the rate_limits counter to 30 (the
		// cap from migration 20260907_001) so the next saveRoute insert
		// fires the BEFORE INSERT trigger. data.ts → rateLimitErrorMessage
		// rewraps the P0001 as a friendly "creating routes too quickly"
		// Error, the save handler now routes e.message through showToast
		// and the user gets a readable error toast instead of either
		// the raw exception or the generic "Failed to save route" fallback.
		const admin = getAdminClient();
		const nowS = Math.floor(Date.now() / 1000);
		const windowStartS = Math.floor(nowS / 3600) * 3600;
		const windowStart = new Date(windowStartS * 1000).toISOString();
		await admin.from('rate_limits').upsert({
			user_id: USER_A.id,
			bucket: 'create_route',
			window_start: windowStart,
			count: 30,
		});

		try {
			await page.goto('/routes/new');
			await expect(page.getByRole('heading', { level: 1, name: 'Route Builder' }))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

			// Same force-enable trick as the happy-path test — OSRM isn't
			// reachable here, so we open the modal without a real route.
			const saveBtn = page.getByRole('button', { name: /Save Route/ });
			await saveBtn.evaluate((el: HTMLButtonElement) => (el.disabled = false));
			await saveBtn.click();

			const modal = page.locator('.modal', { hasText: 'Save route' });
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByPlaceholder('My Route').fill(`rate-limited ${Date.now()}`);

			const submit = modal.getByRole('button', { name: /Save route/ });
			await submit.evaluate((el: HTMLButtonElement) => (el.disabled = false));
			await submit.click();

			// Friendly wording lands in a page-level error toast,
			// not the modal's inline .save-error banner.
			const errorToast = page.locator('.toast-error');
			await expect(errorToast).toBeVisible({ timeout: 10_000 });
			await expect(errorToast).toHaveText(/creating routes too quickly/i);
			// Negative pin: the generic "Failed to save route" fallback
			// (and the raw "rate limit exceeded for create_route" leak)
			// must NOT appear.
			await expect(page.getByText('Failed to save route')).toHaveCount(0);
			await expect(page.getByText(/rate limit exceeded for create_route/i))
				.toHaveCount(0);
		} finally {
			await resetRateLimit(USER_A.id, 'create_route');
		}
	});
});
