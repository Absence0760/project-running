import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Strava bulk-export ZIP import — the MULTI-activity, track-bearing,
 * partial-re-import slice that the single-activity trackless journey
 * (settings/integrations-import-journey.spec.ts) leaves uncovered.
 *
 * That sibling spec threads ONE trackless run (empty Filename cell, no
 * inner GPX) through connect → import → /runs+detail → full re-import
 * dedupe (1 → 0 imported / 1 skipped) → Garmin disconnect, as USER_A.
 * The cross-cutting specs cover the rest of the import surface:
 * strava-import-guards pins the EF OAuth gates, runs-external-id-dedupe
 * pins the raw-INSERT 23505 backstop. None of them exercise:
 *
 *   - A ZIP with MORE THAN ONE data row, so the run/walk/hike filter at
 *     strava-zip.ts:109 (a non-foot `Ride` row → `dropped`, never saved —
 *     counted distinctly from a duplicate `skip`) is never taken.
 *   - A per-activity GPX member inside `activities/`, so the
 *     track-parse path (importOne → classifyStravaMember → parseRouteFile
 *     → saveRun({ track }) → the `runs` Storage upload at data.ts:827)
 *     is never taken — the existing journey imports trackless on purpose.
 *   - A PARTIAL re-import: a second ZIP that re-presents already-imported
 *     activities ALONGSIDE a brand-new one, so the in-ZIP dedupe Set
 *     (buildStravaDedupeSet over the user's existing rows) has to skip
 *     SOME rows and import OTHERS in the same upload — not the all-or-
 *     nothing 1→0+1 the sibling pins.
 *
 * This spec drives all three through the real in-app uploader on
 * /settings/integrations (same hidden-file-input pattern as the sibling
 * + restore-backup.spec.ts), as an EPHEMERAL saga user with a clean
 * zero-run account so every progress count ("2 / 3 imported", etc.) is
 * deterministic rather than relative to USER_A's ~225 seeded runs.
 *
 *   1. IMPORT a 3-row ZIP: a Run carrying a real `activities/<id>.gpx`
 *      track, a Walk (trackless, also a foot activity → imported), and a
 *      Ride (non-foot → DROPPED by the run/walk/hike filter, counted as
 *      an unsupported type not a dupe). Progress:
 *      "3 / 3 · 2 imported · 0 skipped · 1 dropped". Backend: exactly the two foot
 *      activities land as source='strava' rows with `strava:<id>`
 *      external ids + metadata.strava_id; the Ride's id is absent. The
 *      Run's row carries a `track_url` (the GPX threaded through to the
 *      Storage object); the Walk's stays null (trackless).
 *   2. THREAD the run surfaces: both imported activities appear on /runs
 *      (All-time); the GPS Run's /runs/[id] detail renders its map +
 *      title (from the CSV Activity Name).
 *   3. PARTIAL RE-IMPORT: a 4-row ZIP = the original three + one NEW Run.
 *      The two foot rows already present (matched on strava_id) skip, the
 *      Ride drops again, the new Run imports. Progress: "4 / 4 ·
 *      1 imported · 2 skipped · 1 dropped". Backend: the user now has exactly THREE
 *      strava runs (2 + 1), and each original external_id still has a
 *      count of exactly 1 — the dedupe held per-id across a mixed ZIP.
 *
 * Disconnect is deliberately NOT part of this arc: the sibling already
 * pins the (non-strava) disconnect DELETE path, and the strava-specific
 * disconnect routes through the EF (data.ts:1468, `action: 'disconnect'`)
 * which the local stack can't complete (no STRAVA config — see
 * strava-import-guards). Pinning a Strava UI disconnect here would test
 * the unconfigured-EF failure, not the disconnect contract.
 *
 * No rate-limit reset needed: the zip importer has no per-user bucket
 * (only create_club / create_route are throttled, migration 20260907_001).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

/**
 * Render a Date as Strava's documented "Activity Date" cell shape — the
 * no-zone UTC-wall-clock "Mon D, YYYY, h:mm:ss AM" string that
 * parseStravaCsvDateToIso reads back as a UTC instant (strava-zip-date.ts).
 * Built from UTC getters so the round-trip is zone-independent. Same
 * helper shape as the sibling journey.
 */
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

/**
 * A minimal but VALID Strava per-activity GPX with two <trkpt>s under one
 * <trk><trkseg>. parseRouteFile (import.ts#parseGpx) returns one route
 * with both waypoints; saveRun then uploads it as the gzipped
 * `{uid}/{runId}.json.gz` Storage object and stamps `track_url`. Two
 * points is the minimum saveRun's `track.length >= 2` upload gate accepts
 * (data.ts:827). Coordinates are a short London segment — non-(0,0) so no
 * null-island guard trips.
 */
const GPX_TRACK = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="e2e" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>e2e track</name><trkseg>
    <trkpt lat="51.5074" lon="-0.1278"><ele>12</ele></trkpt>
    <trkpt lat="51.5080" lon="-0.1290"><ele>14</ele></trkpt>
  </trkseg></trk>
</gpx>`;

type ActivityRow = {
	stravaId: string;
	name: string;
	type: 'Run' | 'Walk' | 'Ride';
	/** Inner GPX member path under `activities/`, or '' for a trackless row. */
	filename: string;
};

/**
 * Build a multi-activity Strava bulk-export ZIP in memory. Root
 * `activities.csv` (the only required member) plus one `activities/<id>.gpx`
 * for each row that names a Filename. Column header matches the
 * case-insensitive lookups in strava-zip-header.ts (Activity ID / Date /
 * Name / Type / Filename / Distance(km) / Moving Time(s) / Elevation Gain).
 * Each activity is dated relative to `baseDate` (newest row first) so the
 * imported runs land at the top of the desc-by-started_at /runs list on
 * the saga user's otherwise-empty account.
 */
async function buildStravaZip(opts: {
	rows: ActivityRow[];
	baseDate: Date;
}): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	const header =
		'Activity ID,Activity Date,Activity Name,Activity Type,Filename,Distance,Moving Time,Elevation Gain';
	const lines = [header];
	opts.rows.forEach((r, i) => {
		// Stagger each row a minute apart so started_at values are distinct.
		const when = new Date(opts.baseDate.getTime() - i * 60_000);
		lines.push(
			`${r.stravaId},"${stravaActivityDate(when)}","${r.name}",${r.type},${r.filename},5.00,1500,42`
		);
		if (r.filename) zip.file(r.filename, GPX_TRACK);
	});
	lines.push('');
	zip.file('activities.csv', lines.join('\n'));
	const arr = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
	return Buffer.from(arr);
}

/** Unique numeric Strava id (digits only, matching Strava's real ids). */
const stravaId = () => `${Date.now()}${Math.floor(Math.random() * 100000)}`;

test.describe('Strava bulk-import — multi-activity, track-bearing, partial re-import dedupe', () => {
	let saga: SagaUser;

	test.beforeAll(async () => {
		[saga] = await createSagaUsers(1, { displayNames: ['Strava ZIP Importer'] });
	});

	test.afterAll(async () => {
		if (saga) await deleteSagaUsers([saga]);
	});

	test('import a 3-activity ZIP (run+track / walk / filtered ride) → threads /runs → partial re-import de-dupes', async ({
		browser
	}) => {
		const admin = getAdminClient();

		// Distinct ids per activity. The Ride id should NEVER appear in the
		// runs table (filtered by activity type); the run + walk should.
		const runId = stravaId();
		const walkId = stravaId();
		const rideId = stravaId();
		const newRunId = stravaId();

		const runName = uniqueText('e2e-strava-run');
		const walkName = uniqueText('e2e-strava-walk');
		const rideName = uniqueText('e2e-strava-ride');
		const newRunName = uniqueText('e2e-strava-run2');

		// Date at NOW so imported activities sort to the top of /runs.
		const baseDate = new Date();

		const ctx = await browser.newContext({ storageState: saga.storageStatePath });
		// Saga users must pre-accept the cookie banner before any page so it
		// doesn't intercept clicks / file-input interactions.
		function setConsentAccepted() {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		}
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		// Captured so teardown sweeps exactly what this test planted (the
		// saga delete CASCADEs runs too, but an explicit sweep keeps the
		// run-photos / track-object cleanup tight if the user delete races).
		const plantedRunRowIds: string[] = [];

		try {
			// ── 1. Import the 3-activity ZIP ────────────────────────────
			let gpsRunDbId = '';
			let walkDbId = '';
			await test.step('importing a Run-with-track + Walk + Ride imports 2 (foot) and skips 1 (ride)', async () => {
				const zip = await buildStravaZip({
					baseDate,
					rows: [
						{ stravaId: runId, name: runName, type: 'Run', filename: `activities/${runId}.gpx` },
						{ stravaId: walkId, name: walkName, type: 'Walk', filename: '' },
						{ stravaId: rideId, name: rideName, type: 'Ride', filename: '' }
					]
				});

				await page.goto('/settings/integrations');
				const stravaBulkCard = page
					.locator('section.bulk-import')
					.filter({ hasText: 'Bulk import from a Strava export' });
				await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

				await stravaBulkCard.locator('input[type="file"]').setInputFiles({
					name: 'strava_export.zip',
					mimeType: 'application/zip',
					buffer: zip
				});

				// Progress: all 3 rows processed, 2 imported (run+walk),
				// 0 skipped, 1 dropped (the ride — an unsupported activity
				// type, dropped not imported, counted distinctly from a dupe).
				const progress = stravaBulkCard.locator('.zip-status');
				await expect(progress).toContainText('3 / 3', { timeout: 15_000 });
				await expect(progress).toContainText('2 imported');
				await expect(progress).toContainText('0 skipped');
				await expect(progress).toContainText('1 dropped');
				// Toast: "Strava zip import: 2 new, 0 already present. 1 not
				// imported (unsupported activity type)."
				await expect(page.locator('.toast-success')).toContainText(/2 new/i, {
					timeout: 10_000
				});
				await expect(page.locator('.toast-success')).toContainText(/not imported/i);

				// Backend: exactly the two foot activities landed; the ride did not.
				const { data: rows } = await admin
					.from('runs')
					.select('id, source, external_id, activity_type, track_url, metadata')
					.eq('user_id', saga.id)
					.in('external_id', [`strava:${runId}`, `strava:${walkId}`, `strava:${rideId}`]);
				const byExt = new Map(
					(rows ?? []).map((r) => [r.external_id as string, r])
				);
				expect(byExt.size, 'run + walk imported, ride filtered out').toBe(2);

				const runRow = byExt.get(`strava:${runId}`)!;
				expect(runRow.source).toBe('strava');
				expect(runRow.activity_type).toBe('run');
				expect((runRow.metadata as Record<string, unknown>)?.strava_id).toBe(runId);
				// The GPX threaded through to a Storage object — track_url set.
				expect(
					runRow.track_url,
					'a Run with an inner GPX gets its track uploaded'
				).toBeTruthy();
				gpsRunDbId = runRow.id as string;

				const walkRow = byExt.get(`strava:${walkId}`)!;
				expect(walkRow.activity_type).toBe('walk');
				// Trackless Walk row → no Storage object.
				expect(walkRow.track_url, 'a trackless Walk row has no track_url').toBeNull();
				walkDbId = walkRow.id as string;

				expect(
					byExt.has(`strava:${rideId}`),
					'a Ride is not a foot activity and must never be saved'
				).toBe(false);

				plantedRunRowIds.push(gpsRunDbId, walkDbId);
			});

			// ── 2. The imported runs thread the run surfaces ────────────
			await test.step('both imported activities appear on /runs; the GPS run detail renders', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${gpsRunDbId}"]`)
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator(`.run-card[href$="${walkDbId}"]`)
				).toBeVisible({ timeout: 10_000 });

				// The GPS run's detail page mounts with its CSV-derived title.
				await page.goto(`/runs/${gpsRunDbId}`);
				await expect(
					page.getByRole('heading', { name: runName, level: 1 })
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator('.key-stat-value').first()
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 3. Partial re-import: 3 originals + 1 new → 1 new, 3 skipped ──
			await test.step('re-importing the 3 originals plus 1 new run de-dupes per-id', async () => {
				const zip = await buildStravaZip({
					baseDate,
					rows: [
						{ stravaId: runId, name: runName, type: 'Run', filename: `activities/${runId}.gpx` },
						{ stravaId: walkId, name: walkName, type: 'Walk', filename: '' },
						{ stravaId: rideId, name: rideName, type: 'Ride', filename: '' },
						{ stravaId: newRunId, name: newRunName, type: 'Run', filename: '' }
					]
				});

				await page.goto('/settings/integrations');
				const stravaBulkCard = page
					.locator('section.bulk-import')
					.filter({ hasText: 'Bulk import from a Strava export' });
				await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

				await stravaBulkCard.locator('input[type="file"]').setInputFiles({
					name: 'strava_export_2.zip',
					mimeType: 'application/zip',
					buffer: zip
				});

				// 4 rows processed: run + walk already present (2 skip), ride
				// dropped as an unsupported type (1 dropped), only the new run
				// imports.
				const progress = stravaBulkCard.locator('.zip-status');
				await expect(progress).toContainText('4 / 4', { timeout: 15_000 });
				await expect(progress).toContainText('1 imported');
				await expect(progress).toContainText('2 skipped');
				await expect(progress).toContainText('1 dropped');
				await expect(page.locator('.toast-success')).toContainText(/1 new/i, {
					timeout: 10_000
				});

				// Backend: the new run landed; the originals were NOT duplicated.
				const { data: newRows } = await admin
					.from('runs')
					.select('id')
					.eq('user_id', saga.id)
					.eq('external_id', `strava:${newRunId}`);
				expect(newRows ?? []).toHaveLength(1);
				plantedRunRowIds.push(newRows![0].id as string);

				// Each original external_id still resolves to exactly one row —
				// the per-id dedupe held across a mixed ZIP, not just the
				// all-or-nothing single-row case the sibling pins.
				for (const ext of [`strava:${runId}`, `strava:${walkId}`]) {
					const { count } = await admin
						.from('runs')
						.select('*', { count: 'exact', head: true })
						.eq('user_id', saga.id)
						.eq('external_id', ext);
					expect(count, `${ext} stays a single row after re-import`).toBe(1);
				}

				// Total strava runs for this user: exactly 3 (run + walk + new
				// run); the ride was never saved on either pass.
				const { count: stravaCount } = await admin
					.from('runs')
					.select('*', { count: 'exact', head: true })
					.eq('user_id', saga.id)
					.eq('source', 'strava');
				expect(stravaCount, 'run + walk + 1 new run, ride filtered both passes').toBe(3);

				// UI: still exactly one card for the original GPS run.
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${gpsRunDbId}"]`)
				).toHaveCount(1);
			});
		} finally {
			// Explicit run sweep (the saga delete CASCADEs auth.users → runs,
			// but sweep the planted rows first so the run-track Storage object
			// is unlinked deterministically regardless of CASCADE timing).
			for (const id of plantedRunRowIds) {
				await admin.from('runs').delete().eq('id', id);
			}
			await ctx.close();
		}
	});
});
