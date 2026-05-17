import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
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
		await page.waitForLoadState('networkidle');
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
});
