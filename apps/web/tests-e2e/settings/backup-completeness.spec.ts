import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/account — a local backup declares its own completeness.
 *
 * The writer skips a track whose download fails so one dead blob can't
 * sink the whole archive. That is the right trade, but it used to be
 * silent in both directions: the manifest emitted neither `complete`
 * nor `incomplete`, and the download surface said nothing — so a file
 * short of its GPS traces was indistinguishable from a whole one right
 * up until a restore. Mobile and the Go exporter both publish the pair
 * (decisions.md § 668 / § 675); these two tests pin the web halves.
 *
 *   1. WRITE — plant a run whose `track_url` names a Storage object
 *      that does not exist. The download 400s, the writer skips it, and
 *      both the archive's manifest and the page must say so.
 *   2. READ — feed back an archive that declares `complete: false`. The
 *      restore still lands its rows (a short archive can't delete
 *      anything — restore is additive) but the verdict has to reach the
 *      runner, because a full-looking history is what someone wipes a
 *      device on.
 */

const MISSING_TRACK_RUN_ID = '11111111-2222-3333-4444-bac02000beef';
const SHORT_ARCHIVE_RUN_ID = '11111111-2222-3333-4444-bac02000cafe';

async function downloadToBuffer(
	download: import('@playwright/test').Download
): Promise<Buffer> {
	const stream = await download.createReadStream();
	const chunks: Buffer[] = [];
	for await (const chunk of stream) chunks.push(Buffer.from(chunk));
	return Buffer.concat(chunks);
}

test.describe('backup completeness disclosure', () => {
	// The write leg builds a real archive over USER_A's whole seeded
	// history, including its Storage track downloads.
	test.describe.configure({ timeout: 120_000 });

	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin.from('runs').delete().in('id', [MISSING_TRACK_RUN_ID, SHORT_ARCHIVE_RUN_ID]);
	});

	test('a backup whose track download failed says so on the page and in its manifest', async ({
		page
	}) => {
		const admin = getAdminClient();
		// A row pointing at a blob that was never uploaded. No route
		// interception: the Storage read genuinely fails, which is the
		// same shape as the offline / permission / corrupt-object case.
		const { error: insErr } = await admin.from('runs').insert({
			id: MISSING_TRACK_RUN_ID,
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 5 * 60_000).toISOString(),
			duration_s: 1200,
			distance_m: 4321,
			source: 'app',
			is_public: false,
			activity_type: 'run',
			metadata: { activity_type: 'run', title: `e2e-backup-shortfall ${Date.now()}` },
			track_url: `${USER_A.id}/${MISSING_TRACK_RUN_ID}.json.gz`
		});
		expect(insErr, 'planted run insert must succeed').toBeNull();

		await page.goto('/settings/account');
		const downloadPromise = page.waitForEvent('download');
		await page.getByRole('button', { name: /Download full backup/ }).click();
		const download = await downloadPromise;
		const zipBytes = await downloadToBuffer(download);

		// The page discloses the shortfall — the manifest is not something
		// anyone reads before trusting a backup.
		await expect(page.getByTestId('backup-shortfall')).toBeVisible({ timeout: 15_000 });

		const JSZip = (await import('jszip')).default;
		const zip = await JSZip.loadAsync(zipBytes);
		const manifest = JSON.parse(await zip.file('manifest.json')!.async('string')) as {
			complete?: boolean;
			incomplete?: string[];
		};
		expect(manifest.complete).toBe(false);
		expect(manifest.incomplete).toEqual(['tracks']);
		// The run row itself still ships — the archive is short, not broken.
		const runs = JSON.parse(await zip.file('runs.json')!.async('string')) as Array<{
			id: string;
		}>;
		expect(runs.some((r) => r.id === MISSING_TRACK_RUN_ID)).toBe(true);
		expect(zip.file(`tracks/${MISSING_TRACK_RUN_ID}.json.gz`)).toBeNull();
	});

	test('restoring an archive that declares itself incomplete surfaces the verdict', async ({
		page
	}) => {
		const JSZip = (await import('jszip')).default;
		const zip = new JSZip();
		zip.file(
			'manifest.json',
			JSON.stringify({
				format: 'run-app-backup',
				version: 1,
				exported_at: new Date().toISOString(),
				exported_from: 'e2e-backup-completeness-spec',
				counts: { runs: 1, routes: 0, goals: 0, tracks: 0 },
				complete: false,
				incomplete: ['tracks']
			})
		);
		zip.file(
			'runs.json',
			JSON.stringify([
				{
					id: SHORT_ARCHIVE_RUN_ID,
					started_at: new Date(Date.now() - 3 * 60_000).toISOString(),
					duration_s: 900,
					distance_m: 3210,
					source: 'app',
					is_public: false,
					metadata: {
						activity_type: 'run',
						title: `e2e-short-archive ${Date.now()}`
					}
				}
			])
		);
		const buf = Buffer.from(
			await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' })
		);

		await page.goto('/settings/account');
		await page.locator('input[type="file"][accept=".zip"]').setInputFiles({
			name: 'e2e-short-archive.zip',
			mimeType: 'application/zip',
			buffer: buf
		});
		const dialog = page.locator('.modal', { hasText: /Restore from backup/i });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: /^Restore$/ }).click();

		// The rows still land: a short archive cannot delete anything.
		await expect(page.getByText(/Restored 1 runs/)).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('restore-incomplete-archive')).toBeVisible();
	});
});
