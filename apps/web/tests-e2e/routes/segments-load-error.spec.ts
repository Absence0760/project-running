import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] (SegmentsPanel) — a failed segments fetch must render a
 * distinct error + retry state, NOT stick on the "Loading segments…"
 * spinner forever.
 *
 * Before the fix, load() had no try/catch/finally and fetchSegmentsForRoute
 * swallowed the error to []; a rejection left the spinner up permanently.
 * fetchSegmentsForRouteWithError + the component error state fix both.
 */

test.describe('/routes/[id] — SegmentsPanel load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed segments fetch shows the error banner, not the stuck spinner', async ({
		page
	}) => {
		await page.route('**/rest/v1/segments*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated segments failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		const banner = page.locator('.error-banner', { hasText: "Couldn't load your routes." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The perpetual "Loading segments…" must have cleared.
		await expect(page.getByText('Loading segments…')).toHaveCount(0);
	});

	test('a failed leaderboard fetch shows the retryable error, not a false "no efforts"', async ({
		page
	}) => {
		// A leaderboard fetch error used to swallow to [] and read as "No
		// efforts yet" — a runner offline / hitting an RPC error was told the
		// board was empty, with no retry. This pins the distinct error state.
		const admin = getAdminClient();
		const segName = `e2e-lb-error-${Date.now()}`;
		const { data: seg, error: segErr } = await admin
			.from('segments')
			.insert({
				route_id: RUNNER_PUBLIC_ROUTE_ID,
				name: segName,
				start_distance_m: 100,
				end_distance_m: 400,
				author_id: USER_A.id
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		const segId = (seg as { id: string }).id;

		try {
			// The leaderboard is an RPC (POST /rest/v1/rpc/…). Fulfilling an RPC
			// POST hangs supabase-js (the CORS preflight for the injected
			// response is never satisfied), so ABORT it instead — a rejected
			// fetch surfaces as a PostgREST error the same way a 5xx would, and
			// exercises the same error/retry branch. The segment-list GET is
			// left untouched so the row still renders and can be opened.
			await page.route('**/rest/v1/rpc/segment_leaderboard_tiered*', async (route) => {
				if (route.request().method() === 'POST') {
					await route.abort();
				} else {
					await route.continue();
				}
			});

			await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

			const segRow = page.locator('.seg-row', { hasText: segName });
			await expect(segRow).toBeVisible({ timeout: 10_000 });
			await segRow.click();

			// The expanded segment shows the retryable error banner — never the
			// "No efforts yet" empty state and never a stuck spinner.
			const openSeg = page.locator('.seg.open');
			const banner = openSeg.locator('.error-banner');
			await expect(banner).toBeVisible({ timeout: 10_000 });
			await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
			await expect(openSeg).not.toContainText('No efforts yet');
			await expect(openSeg.getByText('Loading…', { exact: true })).toHaveCount(0);
		} finally {
			await admin.from('segments').delete().eq('id', segId);
		}
	});
});
