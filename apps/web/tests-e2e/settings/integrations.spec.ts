import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — Strava / parkrun / Garmin Connect rows
 * with connect / sync / disconnect affordances. Strava is OAuth-
 * gated, parkrun is a one-button athlete-number scrape, Garmin is
 * bulk-import only.
 *
 * Future depth: Strava connect button click → mock OAuth flow,
 * parkrun import button against the seeded athlete number, Garmin
 * .fit / .zip upload + per-file progress.
 */

test.describe('/settings/integrations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('integration list renders Strava + parkrun + Garmin rows', async ({
		page
	}) => {
		// The integrations page lists three providers regardless of
		// connection state. Runner's seed has parkrun + strava
		// connected (last_sync_at populated); garmin is unconnected.
		// All three rows must appear — the list is built from a
		// hardcoded array, but the connection state comes from a
		// query, so a regression there could break the page render.
		await page.goto('/settings/integrations');

		await expect(
			page.getByRole('heading', { name: 'Strava', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'parkrun', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'Garmin Connect', exact: true })
		).toBeVisible();
	});

	test('parkrun connect → disconnect round-trip flips the button + the row class', async ({
		page
	}) => {
		// parkrun + garmin both go through the placeholder-connect path
		// (`connectIntegration(provider)` upsert into integrations) —
		// only Strava has live OAuth. parkrun starts connected per
		// seed, so the round-trip is Disconnect → Connect → Disconnect.
		// Tests the data-layer upsert + delete path that the canonical
		// click handler funnels into.
		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		const parkrunCard = page.locator('.integration-card', { hasText: 'parkrun' });
		await expect(parkrunCard).toBeVisible({ timeout: 10_000 });
		await expect(parkrunCard).toHaveClass(/connected/);

		await parkrunCard.getByRole('button', { name: 'Disconnect' }).click();
		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await confirm.getByRole('button', { name: 'Disconnect' }).click();
		await expect(parkrunCard).not.toHaveClass(/connected/, { timeout: 5_000 });
		await expect(parkrunCard.getByRole('button', { name: 'Connect' }))
			.toBeVisible();

		// Reconnect to restore the seed state.
		await parkrunCard.getByRole('button', { name: 'Connect' }).click();
		await expect(parkrunCard).toHaveClass(/connected/, { timeout: 5_000 });
	});

	test('Strava Connect button on an unconnected user fires the OAuth path (toast OR strava.com redirect)', async ({
		page,
		context
	}) => {
		// Strava connect doesn't use the placeholder-connect path —
		// clicking Connect either redirects to strava.com/oauth/authorize
		// (live OAuth) or surfaces a "Strava is not configured" toast
		// when PUBLIC_STRAVA_CLIENT_ID is missing. Local dev typically
		// lacks the env var. Either branch is acceptable — the
		// regression we'd miss is a silent click that does nothing.
		//
		// Set up by service-role: ensure Strava starts disconnected
		// for this test; restore the seed state in the finally block.
		const admin = getAdminClient();
		try {
			await admin
				.from('integrations')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('provider', 'strava');

			await page.goto('/settings/integrations');
			await page.waitForLoadState('networkidle');
			const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
			await expect(stravaCard).toBeVisible({ timeout: 10_000 });
			await expect(stravaCard.getByRole('button', { name: 'Connect' }))
				.toBeVisible({ timeout: 5_000 });

			// Catch any external redirect to strava.com so the test
			// doesn't actually leave localhost.
			let stravaRedirect = false;
			await context.route('**://www.strava.com/**', (route) => {
				stravaRedirect = true;
				route.fulfill({ status: 200, body: 'mock' });
			});

			await stravaCard.getByRole('button', { name: 'Connect' }).click();

			const toast = page.getByText(/Strava is not configured/);
			const ok = await Promise.race([
				toast.waitFor({ timeout: 3_000 }).then(() => true).catch(() => false),
				page.waitForTimeout(3_000).then(() => stravaRedirect)
			]);
			expect(ok).toBe(true);
		} finally {
			// Restore seed state — Strava connected with the seeded
			// last_sync_at so downstream tests asserting that row holds.
			await admin.from('integrations').upsert(
				{
					user_id: USER_A.id,
					provider: 'strava',
					last_sync_at: '2026-03-30T08:00:00Z'
				},
				{ onConflict: 'user_id,provider' }
			);
		}
	});

	test('connected integration shows a last-sync timestamp', async ({ page }) => {
		// Strava starts connected per seed with last_sync_at populated.
		// The card surfaces a "Last sync …" line so the user knows
		// data is fresh. Pin the presence of the label — exact
		// timestamp format depends on the formatter but the label
		// is stable.
		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');
		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard).toHaveClass(/connected/, { timeout: 10_000 });
		await expect(stravaCard.getByText(/Last sync/i)).toBeVisible();
	});

	test('Sync now button visible on a connected Strava card', async ({ page }) => {
		// 'Sync now' is the canonical re-fetch affordance for a
		// connected Strava integration. A regression that hides it
		// would leave users without a manual refresh path.
		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');
		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard.getByRole('button', { name: /Sync/i }))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/settings/integrations — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login', async ({ page }) => {
		// /settings/integrations is NOT in the publicPaths list, so an
		// anon user must be redirected to /login with a return_to.
		await page.goto('/settings/integrations');
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
	});
});
