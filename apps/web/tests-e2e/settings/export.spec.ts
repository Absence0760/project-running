import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — Data Export buttons.
 *
 * Two client-side download paths live on this page: "Export All Runs
 * (CSV)" and "Export All Runs (JSON)". Both fetch the user's runs
 * via supabase-js (no Edge Function), serialise them in the browser,
 * and trigger an `<a download>` click via the data-layer helper
 * `downloadFile`. This pins both:
 *   - the click ends up as a real download event from Playwright's
 *     perspective (`page.waitForEvent('download')` resolves)
 *   - the saved file's filename matches the contract documented in
 *     handleExportCsv / handleExportJson (`runs_export.csv` and
 *     `runs-<ts>.json`)
 *   - the body actually contains the seeded runs, not just an empty
 *     header line
 */

test.describe('/settings/account — data export', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Export All Runs (CSV) downloads a runs_export.csv with seed rows', async ({
		page
	}) => {
		await page.goto('/settings/account');

		const downloadPromise = page.waitForEvent('download');
		await page
			.getByRole('button', { name: /Export All Runs \(CSV\)/ })
			.click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toBe('runs_export.csv');

		// Read the body and check the header + at least one data row.
		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) {
			chunks.push(Buffer.from(chunk));
		}
		const body = Buffer.concat(chunks).toString('utf-8');
		expect(body.split('\n')[0]).toBe(
			'date,distance_m,duration_s,pace_s_per_km,source'
		);
		// Runner has 12+ seeded runs → at least one body row.
		expect(body.split('\n').length).toBeGreaterThan(1);
	});

	test('Backup ZIP contains runs.json + manifest.json + profile.json (interior shape)', async ({
		page
	}) => {
		// The magic-bytes test below pins the wrapper. This pins the
		// CONTENT — every entry the backup needs to be re-importable
		// must be inside. createBackup writes:
		//   - manifest.json (versioning)
		//   - profile.json
		//   - runs.json (one row per run, no track inline)
		//   - tracks/<run_id>.json.gz (per-run gzipped tracks)
		//   - routes.json
		// A regression that dropped any of these would silently break
		// restore on another device; magic-bytes alone wouldn't catch
		// it.
		const JSZip = (await import('jszip')).default;

		await page.goto('/settings/account');
		const downloadPromise = page.waitForEvent('download');
		await page
			.getByRole('button', { name: /Download full backup/ })
			.click();
		const download = await downloadPromise;

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) {
			chunks.push(Buffer.from(chunk));
		}
		const zip = await JSZip.loadAsync(Buffer.concat(chunks));

		// Required top-level entries.
		expect(zip.file('manifest.json'), 'manifest.json must exist')
			.not.toBeNull();
		expect(zip.file('profile.json'), 'profile.json must exist')
			.not.toBeNull();
		expect(zip.file('runs.json'), 'runs.json must exist').not.toBeNull();
		expect(zip.file('routes.json'), 'routes.json must exist').not.toBeNull();

		// runs.json must parse + carry the seeded rows.
		const runsTxt = await zip.file('runs.json')!.async('string');
		const runs = JSON.parse(runsTxt) as Array<Record<string, unknown>>;
		expect(Array.isArray(runs)).toBe(true);
		expect(runs.length).toBeGreaterThan(0);

		// Manifest carries a version key so future restore paths can
		// version-gate.
		const manifestTxt = await zip.file('manifest.json')!.async('string');
		const manifest = JSON.parse(manifestTxt) as Record<string, unknown>;
		expect(manifest).toHaveProperty('version');
	});

	test('Download full backup → emits a non-empty .zip with the timestamped filename', async ({
		page
	}) => {
		// The Backup & Restore card lives above Data Export. Clicking
		// "Download full backup" calls createBackup() which builds a zip
		// (runs.json + per-run track json.gz files + routes/profile/
		// settings) entirely client-side. Pin the file shape: filename
		// matches `run-app-backup-<ts>.zip` and the body has the ZIP
		// magic bytes (PK\x03\x04 == 0x504b0304). A regression that
		// returned an empty Blob or a non-ZIP buffer would fail here.
		await page.goto('/settings/account');

		const downloadPromise = page.waitForEvent('download');
		await page
			.getByRole('button', { name: /Download full backup/ })
			.click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toMatch(/^run-app-backup-.*\.zip$/);

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) {
			chunks.push(Buffer.from(chunk));
		}
		const body = Buffer.concat(chunks);
		// ZIP local file header = "PK\x03\x04".
		expect(body.length).toBeGreaterThan(64);
		expect(body.subarray(0, 4)).toEqual(Buffer.from([0x50, 0x4b, 0x03, 0x04]));
	});

	test('Export All Runs (JSON) downloads a runs-<ts>.json with seed rows + no user_id leak', async ({
		page
	}) => {
		await page.goto('/settings/account');

		const downloadPromise = page.waitForEvent('download');
		await page
			.getByRole('button', { name: /Export All Runs \(JSON\)/ })
			.click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toMatch(/^runs-.*\.json$/);

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) {
			chunks.push(Buffer.from(chunk));
		}
		const body = Buffer.concat(chunks).toString('utf-8');
		const rows = JSON.parse(body) as Array<Record<string, unknown>>;
		expect(rows.length).toBeGreaterThan(0);

		// Contract: every row carries the run-row columns (id, source,
		// distance_m, duration_s, started_at, ...) and NONE carries
		// user_id (handleExportJson strips it so the file is
		// re-homeable).
		for (const r of rows) {
			expect(r).toHaveProperty('id');
			expect(r).toHaveProperty('distance_m');
			expect(r).toHaveProperty('duration_s');
			expect(r).toHaveProperty('source');
			expect(r).not.toHaveProperty('user_id');
		}
	});

	test('Cloud export (GPX zip) calls the server endpoint and opens the signed URL', async ({
		page,
		context
	}) => {
		// PUBLIC_EXPORT_HUB_URL is unset in the dev `.env`, so the
		// button takes the fallback path: `supabase.functions.invoke
		// ('export-data', ...)`. supabase-js targets that EF at
		// `${PUBLIC_SUPABASE_URL}/functions/v1/export-data`, which the
		// dev stack actually has running. We don't want to exercise
		// the real EF (it touches Storage + the rate-limit RPC and
		// produces a real signed URL we'd then download), so route-
		// intercept the call and fulfil with a fake-but-correctly-shaped
		// response. That pins both the wire shape AND the UI's
		// behaviour after success.
		const fakeSignedUrl =
			'https://signed.example/runs/exports/abc?token=fake';
		await page.route('**/functions/v1/export-data', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					url: fakeSignedUrl,
					expires_in: 600,
					count: 12,
					format: 'gpx'
				})
			})
		);
		// Fulfil the popup navigation with a tiny 200 so we can read
		// the URL after the navigation completes (signed.example
		// doesn't resolve, which would leave the popup on
		// chrome-error://chromewebdata/ and lose the requested URL).
		await context.route('**/runs/exports/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'text/plain',
				body: 'fake-export'
			})
		);

		await page.goto('/settings/account');

		const popupPromise = context.waitForEvent('page');
		await page
			.getByRole('button', { name: /Cloud export \(GPX zip\)/ })
			.click();
		const popup = await popupPromise;
		await popup.waitForLoadState('domcontentloaded');
		expect(popup.url()).toBe(fakeSignedUrl);
		// Success toast must mention the seeded run count from the
		// mocked response.
		await expect(page.getByText(/Export ready \(12 runs\)/)).toBeVisible({
			timeout: 5_000
		});
	});

	test('Cloud export (GPX zip) surfaces a server-side failure as a toast', async ({
		page
	}) => {
		// A 500 from the EF must surface as a readable error toast
		// instead of swallowing the failure, otherwise a user staring
		// at a stuck "Building zip..." button has no idea why nothing
		// happens.
		await page.route('**/functions/v1/export-data', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'fetch_failed' })
			})
		);

		await page.goto('/settings/account');
		await page
			.getByRole('button', { name: /Cloud export \(GPX zip\)/ })
			.click();
		await expect(page.getByText(/Export failed:/)).toBeVisible({
			timeout: 5_000
		});
	});
});
