import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const PRIVACY_ZONES_KEY = 'privacy_zones';
const SEEDED_ZONE = { lat: -37.8136, lng: 144.9631, radius_m: 200, label: 'home' };

async function getUserPrivacyZones(): Promise<
	Array<{ lat: number; lng: number; radius_m: number; label?: string }>
> {
	const admin = getAdminClient();
	const { data } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', USER_A.id)
		.maybeSingle();
	const prefs = (data?.prefs as Record<string, unknown>) ?? {};
	return (
		(prefs[PRIVACY_ZONES_KEY] as Array<{
			lat: number;
			lng: number;
			radius_m: number;
			label?: string;
		}>) ?? []
	);
}

test.describe('/settings/preferences — PrivacyZonePicker (MapLibre modal)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, []);
	});

	test.afterEach(async () => {
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [SEEDED_ZONE]);
	});

	test('Add-zone modal mounts PrivacyZonePicker with map + radius + disabled Add button', async ({
		page
	}) => {
		await page.goto('/settings/preferences');

		await expect(page.getByText('No privacy zones yet.')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /Add a zone/ }).click();

		const modal = page.locator('.modal', { hasText: 'Add a privacy zone' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await expect(modal.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		const radiusInput = modal.locator('input[type="range"]');
		await expect(radiusInput).toBeVisible();
		await expect(radiusInput).toHaveValue('250');

		const addButton = modal.getByRole('button', { name: 'Add zone' });
		await expect(addButton).toBeDisabled();

		await expect(
			modal.getByRole('button', { name: /Use current location/ })
		).toBeVisible();

		await modal.getByRole('button', { name: 'Cancel' }).click();
		await expect(modal).toHaveCount(0);
	});

	test('Map click places marker, enables Add zone, persists zone to user_settings, then Remove clears it', async ({
		page
	}) => {
		await page.goto('/settings/preferences');

		await page.getByRole('button', { name: /Add a zone/ }).click();

		const modal = page.locator('.modal', { hasText: 'Add a privacy zone' });
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await expect(modal.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		const radiusInput = modal.locator('input[type="range"]');
		await radiusInput.fill('400');

		const addButton = modal.getByRole('button', { name: 'Add zone' });
		await expect(addButton).toBeDisabled();

		const targetLat = 51.5074;
		const targetLng = -0.1278;
		const fired = await modal.locator('.maplibregl-map').evaluate(
			(el, coords) => {
				const win = window as unknown as {
					__maplibreInstance?: { fire: (evt: string, data: unknown) => void };
				};
				const container = el as HTMLElement & { __mapInstance?: unknown };
				const candidates: Array<unknown> = [];
				if (container.__mapInstance) candidates.push(container.__mapInstance);
				if (win.__maplibreInstance) candidates.push(win.__maplibreInstance);
				for (const c of candidates) {
					const m = c as { fire?: (evt: string, data: unknown) => void };
					if (typeof m.fire === 'function') {
						m.fire('click', {
							lngLat: { lat: coords.lat, lng: coords.lng },
							point: { x: 0, y: 0 }
						});
						return true;
					}
				}
				return false;
			},
			{ lat: targetLat, lng: targetLng }
		);

		if (!fired) {
			const canvas = modal.locator('.maplibregl-canvas');
			const box = await canvas.boundingBox();
			expect(box, 'MapLibre canvas should be measurable in headless chrome').not.toBeNull();
			await canvas.click({ position: { x: box!.width / 2, y: box!.height / 2 } });
		}

		await expect(addButton).toBeEnabled({ timeout: 5_000 });

		await addButton.click();
		await expect(modal).toHaveCount(0);

		const zoneRow = page.locator('.zone-list .zone-row').first();
		await expect(zoneRow).toBeVisible({ timeout: 5_000 });
		await expect(zoneRow).toContainText('m radius');

		const planted = await getUserPrivacyZones();
		expect(planted.length).toBe(1);
		expect(planted[0]?.radius_m).toBeGreaterThan(0);

		await page.reload();
		await expect(page.locator('.zone-list .zone-row').first()).toBeVisible({ timeout: 10_000 });

		await page.locator('.zone-list .zone-row').first().getByRole('button', { name: 'Remove' }).click();
		// Removal is confirm-gated — step through the dialog (its confirm
		// button shares the "Remove" label, so scope to the modal).
		await page.locator('.modal').getByRole('button', { name: 'Remove' }).click();
		await expect(page.locator('.zone-list .zone-row')).toHaveCount(0);

		const cleared = await getUserPrivacyZones();
		expect(cleared.length).toBe(0);
	});

	test('Radius slider drives the picker state (data-layer fallback for canvas-bridge flake)', async ({
		page
	}) => {
		await page.goto('/settings/preferences');

		await page.getByRole('button', { name: /Add a zone/ }).click();
		const modal = page.locator('.modal', { hasText: 'Add a privacy zone' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const radiusInput = modal.locator('input[type="range"]');
		await radiusInput.fill('150');
		await expect(modal.locator('.radius strong')).toContainText('150 m');

		await radiusInput.fill('800');
		await expect(modal.locator('.radius strong')).toContainText('800 m');

		await expect(modal.getByRole('button', { name: 'Add zone' })).toBeDisabled();

		await modal.getByRole('button', { name: 'Cancel' }).click();
		await expect(modal).toHaveCount(0);
	});
});
