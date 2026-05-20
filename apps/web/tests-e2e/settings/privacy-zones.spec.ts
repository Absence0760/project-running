import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/preferences — privacy zones CRUD round-trip.
 *
 * The PrivacyZonePicker modal mounts a MapLibre map for tap-to-add
 * which doesn't drive cleanly under Playwright. The test here covers
 * the rest of the round-trip end-to-end:
 *
 *   - Plant a zone in user_settings.prefs.privacy_zones via
 *     service-role (the shape mobile reads through `loadSettings`).
 *   - Reload /settings/preferences and confirm the zone-row renders
 *     with the seeded coords + radius — this pins the read path.
 *   - Click Remove + Save Preferences. Reload. Zone is gone from the
 *     UI AND from the prefs blob.
 *
 * The map-picker INSERT path (clicking on the map → setting radius
 * → "Add zone") is exercised by the existing
 * cross-cutting/privacy-zones.spec.ts which tests the share-time
 * guardrail; a regression in the picker itself surfaces there
 * because that test plants a zone via the same component.
 */

const PRIVACY_ZONES_KEY = 'privacy_zones';

async function setUserPrivacyZones(
	zones: Array<{ lat: number; lng: number; radius_m: number; label?: string }>
) {
	const admin = getAdminClient();
	// user_settings is keyed on user_id; the prefs jsonb holds
	// privacy_zones. Upsert so the test seeds idempotently.
	const { data: existing } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', USER_A.id)
		.maybeSingle();
	const prefs = (existing?.prefs as Record<string, unknown>) ?? {};
	prefs[PRIVACY_ZONES_KEY] = zones;
	await admin
		.from('user_settings')
		.upsert(
			{ user_id: USER_A.id, prefs },
			{ onConflict: 'user_id' }
		);
}

async function getUserPrivacyZones(): Promise<unknown[]> {
	const admin = getAdminClient();
	const { data } = await admin
		.from('user_settings')
		.select('prefs')
		.eq('user_id', USER_A.id)
		.maybeSingle();
	const prefs = (data?.prefs as Record<string, unknown>) ?? {};
	return (prefs[PRIVACY_ZONES_KEY] as unknown[]) ?? [];
}

test.describe('/settings/preferences — privacy zones', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('seeded zone renders + Remove + Save round-trip clears it from prefs', async ({
		page
	}) => {
		const seeded = {
			lat: -33.8688,
			lng: 151.2093,
			radius_m: 250,
			label: 'e2e-home'
		};
		await setUserPrivacyZones([seeded]);

		try {
			await page.goto('/settings/preferences');

			// Zone row renders with the seeded coords + radius.
			const zoneRow = page.locator('.zone-list .zone-row').first();
			await expect(zoneRow).toBeVisible({ timeout: 10_000 });
			await expect(zoneRow).toContainText('-33.86880, 151.20930');
			await expect(zoneRow).toContainText('250 m radius');

			// Remove → Save → expect the saved confirmation.
			await zoneRow.getByRole('button', { name: 'Remove' }).click();
			await expect(zoneRow).toHaveCount(0);
			await page.getByRole('button', { name: /Save Preferences/ }).click();
			await expect(
				page.getByRole('button', { name: /Saved!/ })
			).toBeVisible({ timeout: 5_000 });

			// Reload — zone stays gone in the UI.
			await page.reload();
			await expect(page.locator('.zone-list .zone-row')).toHaveCount(0);

			// Backend agrees: prefs.privacy_zones is empty (or absent).
			const after = await getUserPrivacyZones();
			expect(after.length).toBe(0);
		} finally {
			// Restore the runner's seeded zone so other tests see the
			// canonical state. The seed is referenced by
			// cross-cutting/privacy-zones.spec.ts.
			await setUserPrivacyZones([
				{ lat: -37.8136, lng: 144.9631, radius_m: 200, label: 'home' }
			]);
		}
	});

	test('empty state renders "No privacy zones yet." when prefs has no zones', async ({
		page
	}) => {
		await setUserPrivacyZones([]);

		try {
			await page.goto('/settings/preferences');

			await expect(
				page.getByText('No privacy zones yet.')
			).toBeVisible({ timeout: 10_000 });
			// Add-zone button is still reachable so the user can fix the
			// empty state in one click.
			await expect(
				page.getByRole('button', { name: /Add a zone/ })
			).toBeVisible();
		} finally {
			await setUserPrivacyZones([
				{ lat: -37.8136, lng: 144.9631, radius_m: 200, label: 'home' }
			]);
		}
	});
});
