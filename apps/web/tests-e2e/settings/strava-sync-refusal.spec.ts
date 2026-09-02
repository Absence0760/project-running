import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B } from '../fixtures/users';

/**
 * /settings/integrations — what a runner reads when `strava-import` refuses.
 *
 * `integrations-connected.spec.ts` plants the connected card and presses
 * Sync, but only over the success path. The refusal path had no spec, and
 * it is the third site of the same defect the paid-registration and
 * Connect-onboarding lanes carried: `supabase.functions.invoke` reports
 * every non-2xx as a `FunctionsHttpError` whose `message` is the fixed
 * "Edge Function returned a non-2xx status code", with the function's own
 * `{ error: '<code>' }` envelope on `context`. Both toasts here interpolate
 * `err.message` into a template that was written to carry a reason
 * ("Strava sync failed: {error}"), so a build with no Strava keys, a
 * connection whose refresh token has been revoked, and a genuine outage
 * all filled that slot with the same internal sentence.
 *
 * The function is stubbed at the network layer: the codes it can return are
 * pinned by its own Deno tests, and what is under test is the client's
 * reading of them.
 *
 * USER_B for the same reason `integrations-connected.spec.ts` uses them —
 * USER_A carries seeded integration rows other specs depend on.
 */
test.describe('/settings/integrations — Strava sync refusals', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const admin = getAdminClient();

	test.beforeEach(async () => {
		const { error } = await admin
			.from('integrations')
			.upsert(
				{ user_id: USER_B.id, provider: 'strava', last_sync_at: '2026-05-10T08:00:00Z' },
				{ onConflict: 'user_id,provider' },
			);
		if (error) throw error;
	});

	test.afterEach(async () => {
		await admin.from('integrations').delete().eq('user_id', USER_B.id);
	});

	async function syncWith(
		page: import('@playwright/test').Page,
		status: number,
		body: unknown,
	): Promise<void> {
		await page.route('**/functions/v1/strava-import', async (route) => {
			await route.fulfill({
				status,
				contentType: 'application/json',
				body: JSON.stringify(body),
			});
		});
		await page.goto('/settings/integrations');
		const card = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByRole('button', { name: /Sync/i }).click();
	}

	test('a build with no Strava keys names that, not the invoke internals', async ({ page }) => {
		await syncWith(page, 503, { error: 'strava_not_configured' });

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(toast).toContainText(/not configured/i);
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
	});

	test('a revoked connection reports the refusal code, not the invoke internals', async ({
		page,
	}) => {
		// `refresh_failed` is what the function returns when Strava rejects
		// the stored refresh token — the runner has to reconnect, and a
		// sentence that cannot distinguish that from an outage cannot say so.
		await syncWith(page, 502, { error: 'refresh_failed' });

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(toast).toContainText('refresh_failed');
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
	});

	test('a refusal with an unreadable body still avoids the invoke internals in the slot', async ({
		page,
	}) => {
		// Fail-closed on the unwrap: no envelope to read must not put the
		// internal sentence back in front of the runner.
		await syncWith(page, 500, 'not json at all');

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
	});

	test('a refused disconnect says what refused it, not that it was non-2xx', async ({ page }) => {
		// Disconnect goes through the same function on purpose — it revokes at
		// Strava's end and wipes the vault rows rather than doing a bare DELETE
		// — so it inherits the same envelope, into the same reason-shaped slot
		// ("Couldn't disconnect: {error}").
		await page.route('**/functions/v1/strava-import', async (route) => {
			await route.fulfill({
				status: 503,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'strava_not_configured' }),
			});
		});
		await page.goto('/settings/integrations');
		const card = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByRole('button', { name: 'Disconnect' }).click();
		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await confirm.getByRole('button', { name: 'Disconnect' }).click();

		const toast = page.locator('.toast').first();
		await expect(toast).toBeVisible({ timeout: 10_000 });
		await expect(toast).toContainText('strava_not_configured');
		await expect(page.locator('.toast')).not.toContainText(/non-2xx|Edge Function/);
		// The card must still say connected: the refusal left the row alone.
		await expect(card).toHaveClass(/connected/);
	});

	test('the Sync button is released after a refusal', async ({ page }) => {
		await syncWith(page, 503, { error: 'strava_not_configured' });
		const card = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(card.getByRole('button', { name: /Sync/i })).toBeEnabled({ timeout: 10_000 });
	});
});
