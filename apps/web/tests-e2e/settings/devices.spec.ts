import { expect, test, type Locator, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/devices — per-device prefs registry. Each browser mints a
 * `device_id` into localStorage on first read; the matching
 * `user_device_settings` row is auto-provisioned by `loadSettings` on
 * first access (i.e. the first time the user opens any settings tab).
 * /settings/preferences's onMount calls loadSettings → upsert, so the
 * row exists by the time the test lands on /settings/devices.
 *
 * Planted fixture rows are torn down in afterEach so successive tests
 * don't observe stale state from prior runs.
 */

const PLANTED_DEVICE_PREFIX = 'e2e-fixture-device-';

function rowByLabel(page: Page, label: string): Locator {
	return page.locator(`.device[data-device-label="${label}"]`);
}

test.describe('/settings/devices', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_device_settings')
			.delete()
			.eq('user_id', USER_A.id)
			.like('device_id', `${PLANTED_DEVICE_PREFIX}%`);
	});

	test('current browser shows up with a "This device" badge', async ({ page }) => {
		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');

		const rows = page.locator('.device');
		await expect(rows.first()).toBeVisible({ timeout: 10_000 });

		await expect(page.locator('.current-badge', { hasText: 'This device' })).toBeVisible();

		const currentRow = page.locator('.device.current');
		await expect(currentRow).toHaveCount(1);
		await expect(currentRow.locator('button[title^="Reset this device"]')).toBeVisible();
	});

	test('current device label is editable inline + persists across reload', async ({ page }) => {
		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');
		const currentRow = page.locator('.device.current');
		await expect(currentRow).toBeVisible({ timeout: 10_000 });

		const labelInput = currentRow.locator('input.device-label-input');
		await expect(labelInput).toBeVisible();
		const initial = await labelInput.inputValue();
		const renamed = `e2e-device-label ${Date.now()}`;

		await labelInput.fill(renamed);
		await labelInput.blur();

		await page.reload();
		await expect(page.locator('.device.current input.device-label-input')).toHaveValue(renamed, {
			timeout: 10_000,
		});

		await page.locator('.device.current input.device-label-input').fill(initial);
		await page.locator('.device.current input.device-label-input').blur();
	});

	test('push notification toggle appears on the current device + reflects browser permission state', async ({
		page,
	}) => {
		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');
		const currentRow = page.locator('.device.current');
		await expect(currentRow).toBeVisible({ timeout: 10_000 });

		const pushRow = currentRow.locator('[data-testid="device-push-row"]');
		await expect(pushRow).toBeVisible();

		// Either the unsupported hint OR an Enable button — both are
		// valid states for a headless browser. The hint covers the
		// PUBLIC_VAPID_PUBLIC_KEY-missing case (likely in CI / dev);
		// the Enable button covers the case where a key is configured.
		const hint = pushRow.locator('.push-hint');
		const enableBtn = pushRow.locator('button', { hasText: /Enable push/ });
		const disableBtn = pushRow.locator('button', { hasText: /Disable push/ });
		const visibleCount =
			(await hint.count()) + (await enableBtn.count()) + (await disableBtn.count());
		expect(visibleCount).toBeGreaterThan(0);
	});

	test('non-current device row surfaces a "Push on" indicator when subscribed', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const plantedDeviceId = `${PLANTED_DEVICE_PREFIX}push-on-${Date.now()}`;

		await admin.from('user_device_settings').insert({
			user_id: USER_A.id,
			device_id: plantedDeviceId,
			platform: 'android',
			label: 'Pixel 8 (e2e)',
			prefs: {
				push_subscription: {
					endpoint: 'https://fcm.example/test-endpoint',
					keys: { p256dh: 'x'.repeat(20), auth: 'y'.repeat(20) },
					registered_at: new Date().toISOString(),
				},
			},
		});

		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');
		const plantedRow = rowByLabel(page, 'Pixel 8 (e2e)');
		await expect(plantedRow).toBeVisible({ timeout: 10_000 });
		await expect(plantedRow.locator('.push-state', { hasText: 'Push on' })).toBeVisible();
	});

	test('per-device override planted server-side shows up on the row', async ({ page }) => {
		const admin = getAdminClient();
		const plantedDeviceId = `${PLANTED_DEVICE_PREFIX}override-${Date.now()}`;

		await admin.from('user_device_settings').insert({
			user_id: USER_A.id,
			device_id: plantedDeviceId,
			platform: 'android',
			label: 'Override fixture',
			prefs: { map_style: 'satellite', voice_feedback_enabled: false },
		});

		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');
		const plantedRow = rowByLabel(page, 'Override fixture');
		await expect(plantedRow).toBeVisible({ timeout: 10_000 });
		await expect(plantedRow.locator('.override-link')).toContainText('2 pref override');

		await plantedRow.locator('.override-link').click();
		await expect(plantedRow.locator('.overrides code', { hasText: 'map_style' })).toBeVisible();
		await expect(plantedRow.locator('.override-value', { hasText: 'satellite' })).toBeVisible();
	});

	test('delete device confirmation removes the row', async ({ page }) => {
		const admin = getAdminClient();
		const plantedDeviceId = `${PLANTED_DEVICE_PREFIX}delete-${Date.now()}`;

		await admin.from('user_device_settings').insert({
			user_id: USER_A.id,
			device_id: plantedDeviceId,
			platform: 'android',
			label: 'Deletable fixture',
			prefs: {},
		});

		await page.goto('/settings/preferences');
		await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
			timeout: 10_000,
		});

		await page.goto('/settings/devices');
		const plantedRow = rowByLabel(page, 'Deletable fixture');
		await expect(plantedRow).toBeVisible({ timeout: 10_000 });

		await plantedRow.locator('button.remove-btn').click();

		const dialog = page.getByRole('dialog', { name: /Remove device/ });
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Remove' }).click();

		await expect(plantedRow).toHaveCount(0, { timeout: 10_000 });

		const { data } = await admin
			.from('user_device_settings')
			.select('device_id')
			.eq('user_id', USER_A.id)
			.eq('device_id', plantedDeviceId);
		expect(data).toEqual([]);
	});
});
