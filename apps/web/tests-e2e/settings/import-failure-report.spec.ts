import { readFileSync } from 'node:fs';

import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * Bulk-import failure reporting — the "what didn't import, and why"
 * panel.
 *
 * Before this existed both bulk importers caught the thrown error,
 * incremented a bare counter and dropped the error on the floor, so a
 * migrant walking five years of Strava history through the uploader saw
 * `failed: 47` and had no way to tell a transient network drop (re-run
 * the import and it lands) from a corrupt archive (it never will).
 *
 * The failure is forced deterministically by aborting the PostgREST
 * INSERT into `runs` — and ONLY the INSERT, so the importer's own
 * dedupe pre-fetch (a GET on the same path) still answers and the rows
 * reach `saveRun` as genuinely new. An aborted fetch surfaces through
 * supabase-js as "TypeError: Failed to fetch", which
 * `classifyImportFailure` buckets as `network`.
 *
 * Asserted: the per-activity panel outlives the progress bar (which
 * self-clears after a few seconds), names both failed activities, tallies
 * the reason, downloads a CSV carrying the same rows, and dismisses. The
 * backend cross-check pins the other half of the contract — a reported
 * failure means nothing was written.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

function stravaActivityDate(d: Date): string {
	const months = [
		'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	];
	let hour = d.getUTCHours();
	const ampm = hour >= 12 ? 'PM' : 'AM';
	hour = hour % 12;
	if (hour === 0) hour = 12;
	const mm = String(d.getUTCMinutes()).padStart(2, '0');
	const ss = String(d.getUTCSeconds()).padStart(2, '0');
	return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${hour}:${mm}:${ss} ${ampm}`;
}

/** Run-type rows. `filename` defaults to empty (a manual / indoor activity,
 *  no Storage object involved); pass one to make the row PROMISE a member. */
async function buildStravaZip(
	rows: { stravaId: string; name: string; startedAt: Date; filename?: string }[],
	members: Record<string, string> = {},
): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	const csv = [
		'Activity ID,Activity Date,Activity Name,Activity Type,Filename,Distance,Moving Time,Elevation Gain',
		...rows.map(
			(r) =>
				`${r.stravaId},"${stravaActivityDate(r.startedAt)}","${r.name}",Run,${r.filename ?? ''},5.00,1500,42`,
		),
		''
	].join('\n');
	zip.file('activities.csv', csv);
	for (const [name, body] of Object.entries(members)) zip.file(name, body);
	const arr = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
	return Buffer.from(arr);
}

test.describe('bulk-import failure report', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed Strava import names every activity, tallies the reason, and downloads a report', async ({
		page
	}) => {
		const admin = getAdminClient();
		const startedAt = new Date();
		const rows = [
			{ stravaId: `${Date.now()}001`, name: uniqueText('e2e-import-fail-a'), startedAt },
			{ stravaId: `${Date.now()}002`, name: uniqueText('e2e-import-fail-b'), startedAt },
		];
		const externalIds = rows.map((r) => `strava:${r.stravaId}`);

		// Fail ONLY the insert. The dedupe pre-fetch is a GET on the same
		// path and must still answer, or the rows would never reach saveRun.
		await page.route('**/rest/v1/runs*', async (route) => {
			if (route.request().method() === 'POST') return route.abort('failed');
			return route.fallback();
		});

		try {
			await page.goto('/settings/integrations');
			const stravaBulkCard = page
				.locator('section.bulk-import')
				.filter({ hasText: 'Bulk import from a Strava export' });
			await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

			await stravaBulkCard.locator('input[type="file"]').setInputFiles({
				name: 'strava_export.zip',
				mimeType: 'application/zip',
				buffer: await buildStravaZip(rows)
			});

			const report = stravaBulkCard.getByTestId('import-failure-report');
			await expect(report).toBeVisible({ timeout: 20_000 });
			await expect(report).toContainText(/2 activities didn.t import/);
			// The reason is named, not left as a bare count.
			await expect(report).toContainText('Connection dropped');

			await report.getByText('Show each activity').click();
			for (const r of rows) {
				await expect(report).toContainText(r.name);
			}

			// The panel must outlive the progress bar, which self-clears.
			await expect(stravaBulkCard.locator('.zip-progress')).toHaveCount(0, {
				timeout: 15_000
			});
			await expect(report).toBeVisible();

			const downloadPromise = page.waitForEvent('download');
			await report.getByRole('button', { name: 'Download report (CSV)' }).click();
			const download = await downloadPromise;
			expect(download.suggestedFilename()).toBe('strava-import-failures.csv');
			const csv = readFileSync(await download.path(), 'utf-8');
			expect(csv.split('\n')[0]).toBe('Activity,Started,Reason,Detail');
			for (const r of rows) {
				expect(csv).toContain(r.name);
			}
			expect(csv).toContain('"network"');

			// A reported failure means nothing was written.
			const leaked = await readRows(
				'runs',
				admin
					.from('runs')
					.select('id')
					.in('external_id', externalIds)
			);
			expect(leaked).toHaveLength(0);

			await report.getByRole('button', { name: 'Dismiss' }).click();
			await expect(report).toHaveCount(0);
		} finally {
			await page.unroute('**/rest/v1/runs*');
			await admin.from('runs').delete().in('external_id', externalIds);
		}
	});

	// The export promised a track it did not deliver, which is a different
	// fact from never promising one — and it used to import as a clean,
	// summary-only run with nothing said (decisions.md § 676). Mobile has
	// refused it since § 664; this is web catching up.
	test('a Filename the archive does not contain fails the row instead of importing it trackless', async ({
		page
	}) => {
		const admin = getAdminClient();
		const startedAt = new Date();
		const missing = {
			stravaId: `${Date.now()}003`,
			name: uniqueText('e2e-import-missing-member'),
			startedAt,
			filename: 'activities/9999999.gpx',
		};
		const present = {
			stravaId: `${Date.now()}004`,
			name: uniqueText('e2e-import-manual-row'),
			startedAt,
		};
		const externalIds = [missing, present].map((r) => `strava:${r.stravaId}`);

		try {
			await page.goto('/settings/integrations');
			const stravaBulkCard = page
				.locator('section.bulk-import')
				.filter({ hasText: 'Bulk import from a Strava export' });
			await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

			await stravaBulkCard.locator('input[type="file"]').setInputFiles({
				name: 'strava_export.zip',
				mimeType: 'application/zip',
				buffer: await buildStravaZip([missing, present])
			});

			const report = stravaBulkCard.getByTestId('import-failure-report');
			await expect(report).toBeVisible({ timeout: 20_000 });
			await expect(report).toContainText(/1 activity didn.t import/);
			// Not "Unknown error": the archive is missing a member it named,
			// so re-running the import cannot land this run.
			await expect(report).toContainText('File could not be read');
			await report.getByText('Show each activity').click();
			await expect(report).toContainText(missing.name);

			// The row that promised nothing still imports — the strictness is
			// about a broken promise, not about a missing track.
			const landed = await readRows(
				'runs by external_id',
				admin
					.from('runs')
					.select('external_id')
					.in('external_id', externalIds)
			);
			const ids = landed.map((r) => r.external_id);
			expect(ids).toContain(`strava:${present.stravaId}`);
			expect(ids).not.toContain(`strava:${missing.stravaId}`);
		} finally {
			await admin.from('runs').delete().in('external_id', externalIds);
		}
	});
});
