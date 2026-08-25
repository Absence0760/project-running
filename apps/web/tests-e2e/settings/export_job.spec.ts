import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

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
 */

const HUB_URL = `http://127.0.0.1:${process.env.EXPORTHUB_E2E_PORT ?? '8098'}`;

test.describe('/settings/account — queued export rail', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('an export is queued, built off the connection, and offered as a real archive', async ({
		page
	}) => {
		await page.goto('/settings/account');

		await page.getByTestId('full-account-archive').click();

		// The click returns immediately with a job to watch. If this rail
		// were still synchronous the page would sit here holding a
		// connection until the archive finished.
		const state = page.getByTestId('export-job-state');
		await expect(state).toBeVisible();
		await expect(state).toContainText(/building|ready/i);

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

	test('a reload mid-flight finds the export again with nothing stored locally', async ({
		page
	}) => {
		// The property the whole queued rail exists for. The page keeps no
		// job id — the status endpoint answers for the subject's LATEST
		// export — so a reload (or, on the phone, an app the OS killed)
		// has to be able to find its way back from the server alone.
		await page.goto('/settings/account');
		await page.getByTestId('full-account-archive').click();
		await expect(page.getByTestId('export-job-state')).toBeVisible();

		await page.reload();

		const state = page.getByTestId('export-job-state');
		await expect(state).toBeVisible({ timeout: 30_000 });
		await expect(state).toContainText(/building|ready/i);
		await expect(page.getByTestId('export-job-download')).toBeVisible({
			timeout: 150_000
		});
	});

	test('the synchronous rail is gone from the service', async ({ request }) => {
		// § 724 deleted POST /v1/export. Asserted against the running
		// binary rather than against the source, because a route that is
		// still mounted answers even when nothing in the repo calls it.
		const res = await request.post(`${HUB_URL}/v1/export`, {
			data: { format: 'csv' },
			failOnStatusCode: false
		});
		expect(res.status()).toBe(404);

		// And the queued rail on the same service is up, so a 404 above
		// is the route being absent rather than the worker being down.
		const health = await request.get(`${HUB_URL}/health`);
		expect(health.ok()).toBe(true);
	});
});
