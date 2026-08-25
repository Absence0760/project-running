import { expect, test } from '@playwright/test';

import { USER_C_PRO } from '../fixtures/users';

/**
 * /settings/account — the QUEUED Art 20 export rail, end to end against
 * a real Go worker and a real Storage stack (decisions.md § 717 / § 724).
 *
 * Every other export spec runs against the `export-data` Edge Function
 * fallback, because PUBLIC_EXPORT_HUB_URL is unset in the main config's
 * dev server. This one is the opposite: playwright.exporthub.config.ts
 * boots the worker and points a dev server at it, so what runs here is
 * the enqueue, the worker's own claim off the `jobs` queue, the tus
 * upload into the `exports` bucket, and the signed URL minted at the
 * moment the subject asks for it. § 717 shipped with none of that
 * observed against a live stack; this is that observation.
 *
 * Signed in as the PRO seed user, and that is about quota rather than
 * about tier: an export costs a `check_rate_limit_tiered` token, free
 * allows 2/h and pro 8/h, and this lane retries once on CI. Two runs of
 * a one-token journey would sit exactly on the free ceiling with no
 * headroom, and a 429 would read as a broken rail rather than as an
 * exhausted quota. Nothing here depends on the tier otherwise.
 */

const HUB_URL = `http://127.0.0.1:${process.env.EXPORTHUB_E2E_PORT ?? '8098'}`;

test.describe('/settings/account — queued export rail', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('an export is queued, survives a reload, and lands as a real archive', async ({
		page
	}) => {
		// One journey rather than three tests on purpose: each enqueue
		// spends a quota token, and the properties below are stages of
		// one export rather than independent facts about three.
		await page.goto('/settings/account');

		await page.getByTestId('full-account-archive').click();

		// The click returns immediately with a job to watch. If this rail
		// were still synchronous the page would sit here holding a
		// connection until the archive finished.
		const state = page.getByTestId('export-job-state');
		await expect(state).toBeVisible();
		await expect(state).toContainText(/building|ready/i);

		// The property the whole queued rail exists for: the page keeps no
		// job id — the status endpoint answers for the subject's LATEST
		// export — so a reload (or, on the phone, an app the OS killed)
		// finds its way back from the server alone.
		await page.reload();
		await expect(page.getByTestId('export-job-state')).toBeVisible({
			timeout: 30_000
		});
		await expect(page.getByTestId('export-job-state')).toContainText(
			/building|ready/i
		);

		// The worker claims off a 2-second poll and builds with nothing
		// attached to the browser.
		const download = page.getByTestId('export-job-download');
		await expect(download).toBeVisible({ timeout: 150_000 });

		const href = await download.getAttribute('href');
		expect(href, 'a ready job must carry a signed URL').toBeTruthy();
		expect(href!).toMatch(/^https?:\/\//);

		// The link is a real object, not a path the page dressed up as
		// one: fetch it and check the archive's own magic bytes.
		const res = await page.request.get(href!);
		expect(res.status()).toBe(200);
		const body = await res.body();
		expect(body.length).toBeGreaterThan(0);
		expect(body.subarray(0, 2).toString('latin1')).toBe('PK');
	});

	test('the synchronous rail is gone from the service', async ({ request }) => {
		// § 724 deleted POST /v1/export. Asserted against the running
		// binary rather than against the source, because a route that is
		// still mounted answers even when nothing in the repo calls it.
		// Costs no quota: the route does not exist, so nothing is charged.
		const res = await request.post(`${HUB_URL}/v1/export`, {
			data: { format: 'csv' },
			failOnStatusCode: false
		});
		expect(res.status()).toBe(404);

		// And the queued rail on the same service is up, so the 404 above
		// is the route being absent rather than the worker being down.
		const health = await request.get(`${HUB_URL}/health`);
		expect(health.ok()).toBe(true);
	});
});
