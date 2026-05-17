import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B } from '../fixtures/users';

/**
 * /settings/integrations — connected-state UI + disconnect flow.
 *
 * The OAuth round-trip itself can't run locally without a Strava
 * sandbox; the existing integrations.spec.ts covers disconnected-state
 * UI + the Strava OAuth-button branch. This spec plants integration
 * rows directly via service-role to exercise the surfaces those tests
 * can't reach: connected-state badges, Sync-now affordance, the
 * disconnect ConfirmDialog round-trip, and the DB-side delete.
 *
 * USER_B is used (not USER_A) because USER_A has Strava + parkrun
 * pre-seeded, so planting + sweeping would clash with other specs
 * that depend on the seed state. USER_B starts with zero rows in
 * `integrations` and is restored to that state in afterEach.
 */

const PROVIDERS = ['strava', 'parkrun', 'garmin'] as const;

async function clearUserBIntegrations() {
	const admin = getAdminClient();
	await admin.from('integrations').delete().eq('user_id', USER_B.id);
}

async function plantIntegration(opts: {
	provider: (typeof PROVIDERS)[number];
	lastSyncAt?: string | null;
}) {
	const admin = getAdminClient();
	const { error } = await admin.from('integrations').upsert(
		{
			user_id: USER_B.id,
			provider: opts.provider,
			last_sync_at: opts.lastSyncAt ?? null,
		},
		{ onConflict: 'user_id,provider' },
	);
	if (error) throw error;
}

test.describe('/settings/integrations — connected-state UI (planted rows)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.afterEach(async () => {
		await clearUserBIntegrations();
	});

	test('already-connected Strava renders connected card with Sync + Disconnect + last-sync line', async ({
		page,
	}) => {
		await plantIntegration({
			provider: 'strava',
			lastSyncAt: '2026-05-10T08:00:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard).toBeVisible({ timeout: 10_000 });
		await expect(stravaCard).toHaveClass(/connected/);
		await expect(stravaCard.getByText(/Last synced/i)).toBeVisible();
		await expect(stravaCard.getByRole('button', { name: /Sync/i })).toBeVisible();
		await expect(stravaCard.getByRole('button', { name: 'Disconnect' })).toBeVisible();
	});

	test('Disconnect Strava → confirm → card flips to disconnected + DB row gone', async ({
		page,
	}) => {
		await plantIntegration({
			provider: 'strava',
			lastSyncAt: '2026-05-10T08:00:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard).toHaveClass(/connected/, { timeout: 10_000 });

		await stravaCard.getByRole('button', { name: 'Disconnect' }).click();

		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await expect(confirm.getByText(/Strava/)).toBeVisible();

		await confirm.getByRole('button', { name: 'Disconnect' }).click();

		await expect(stravaCard).not.toHaveClass(/connected/, { timeout: 5_000 });
		await expect(stravaCard.getByRole('button', { name: 'Connect' })).toBeVisible();
		await expect(stravaCard.getByRole('button', { name: /Sync/i })).toHaveCount(0);

		const admin = getAdminClient();
		const { data } = await admin
			.from('integrations')
			.select('id')
			.eq('user_id', USER_B.id)
			.eq('provider', 'strava');
		expect(data ?? []).toHaveLength(0);
	});

	test('Disconnect cancel keeps the integration connected', async ({ page }) => {
		await plantIntegration({
			provider: 'strava',
			lastSyncAt: '2026-05-10T08:00:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard).toHaveClass(/connected/, { timeout: 10_000 });

		await stravaCard.getByRole('button', { name: 'Disconnect' }).click();
		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await confirm.getByRole('button', { name: 'Cancel' }).click();
		await expect(confirm).toHaveCount(0);
		await expect(stravaCard).toHaveClass(/connected/);

		const admin = getAdminClient();
		const { data } = await admin
			.from('integrations')
			.select('id')
			.eq('user_id', USER_B.id)
			.eq('provider', 'strava');
		expect(data ?? []).toHaveLength(1);
	});

	test('Strava bulk-import card renders on the integrations page (regardless of connection state)', async ({
		page,
	}) => {
		await plantIntegration({
			provider: 'strava',
			lastSyncAt: '2026-05-10T08:00:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const bulkCard = page
			.locator('section.bulk-import')
			.filter({ hasText: 'Bulk import from a Strava export' });
		await expect(bulkCard).toBeVisible({ timeout: 10_000 });
		await expect(bulkCard.getByText('Choose Strava export zip')).toBeVisible();
		await expect(bulkCard.locator('input[type="file"]')).toHaveCount(1);
	});

	test('already-connected Garmin renders connected card + Disconnect button', async ({
		page,
	}) => {
		await plantIntegration({
			provider: 'garmin',
			lastSyncAt: '2026-05-09T12:30:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const garminCard = page.locator('.integration-card', { hasText: 'Garmin Connect' });
		await expect(garminCard).toBeVisible({ timeout: 10_000 });
		await expect(garminCard).toHaveClass(/connected/);
		await expect(garminCard.getByText(/Last synced/i)).toBeVisible();
		await expect(garminCard.getByRole('button', { name: 'Disconnect' })).toBeVisible();
		// Garmin has no live OAuth (bulk-import only), so no Sync-now affordance.
		await expect(garminCard.getByRole('button', { name: /Sync/i })).toHaveCount(0);
	});

	test('already-connected parkrun + disconnect round-trip', async ({ page }) => {
		await plantIntegration({
			provider: 'parkrun',
			lastSyncAt: '2026-05-08T07:00:00Z',
		});

		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const parkrunCard = page.locator('.integration-card', { hasText: 'parkrun' });
		await expect(parkrunCard).toBeVisible({ timeout: 10_000 });
		await expect(parkrunCard).toHaveClass(/connected/);
		await expect(parkrunCard.getByText(/Last synced/i)).toBeVisible();

		await parkrunCard.getByRole('button', { name: 'Disconnect' }).click();
		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await expect(confirm.getByText(/parkrun/)).toBeVisible();
		await confirm.getByRole('button', { name: 'Disconnect' }).click();

		await expect(parkrunCard).not.toHaveClass(/connected/, { timeout: 5_000 });
		await expect(parkrunCard.getByRole('button', { name: 'Connect' })).toBeVisible();

		const admin = getAdminClient();
		const { data } = await admin
			.from('integrations')
			.select('id')
			.eq('user_id', USER_B.id)
			.eq('provider', 'parkrun');
		expect(data ?? []).toHaveLength(0);
	});
});
