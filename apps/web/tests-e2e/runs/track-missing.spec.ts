import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] graceful render when the runs row points at a Storage
 * track that doesn't exist.
 *
 * Failure mode this catches: a row + Storage divergence after a
 * partial sync. The runs row is inserted FIRST; the gzipped GPS
 * track upload to the `runs` bucket happens SECOND. If the upload
 * fails (network drop mid-Strava-backfill, Storage outage, the
 * upload's signed URL expired, the writer process crashed between
 * the two writes), the row lands with a `track_url` that points
 * nowhere. The user opens /runs/[id] and the GPS-track download
 * 404s.
 *
 * The data-layer fetchRun wraps `fetchTrack` in try/catch and
 * returns `track: null` on failure — the page is supposed to render
 * the run header + stats + map placeholder, no GPS line. This pins
 * that contract: a row pointing at a phantom Storage path must NOT
 * crash the page.
 *
 * If the try/catch ever gets removed the test surfaces an unhandled
 * Storage-download error blocking page mount.
 */

test.describe('/runs/[id] — graceful render when track_url is broken', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('row with track_url pointing at non-existent Storage object renders cleanly', async ({
		page
	}) => {
		// Plant a runs row WITHOUT a track via insertRun (no `track`
		// option means no Storage upload).
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-29T07:00:00Z').toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			metadata: { activity_type: 'run', title: 'broken-track-url test' }
		});

		try {
			// Service-role: poke a track_url onto the row that points
			// nowhere. Mirrors the partial-sync failure mode.
			const admin = getAdminClient();
			const phantomPath = `${USER_A.id}/${runId}.json.gz`;
			const { error: updErr } = await admin
				.from('runs')
				.update({ track_url: phantomPath })
				.eq('id', runId);
			expect(updErr).toBeNull();

			// Confirm the Storage object actually doesn't exist (so
			// we're testing the right thing, not an accidentally-planted
			// blob from a previous run).
			const { data: list } = await admin.storage
				.from('runs')
				.list(USER_A.id, { search: runId });
			const matched = list?.find((f) => f.name.startsWith(runId));
			expect(matched, 'no Storage object should exist for this run').toBeUndefined();

			// Capture browser-side errors so a regression that throws
			// out of the page's load() (rather than logging the warning
			// and continuing) is loud.
			const pageErrors: Error[] = [];
			page.on('pageerror', (e) => pageErrors.push(e));

			await page.goto(`/runs/${runId}`);

			// Page must mount past the loading shell. The h1 carries
			// either the run's title or the date — either is fine,
			// the assertion is "the page rendered, not stuck on a
			// spinner / error fallback".
			await expect(
				page.getByRole('heading', { level: 1 })
			).toBeVisible({ timeout: 10_000 });

			// Run-not-found fallback must NOT be visible — the row IS
			// there; only the Storage object isn't.
			await expect(page.getByText('Run not found')).toHaveCount(0);

			// Distance / duration values come straight off the row, not
			// the track, so they must render.
			await expect(page.getByText(/5\.00.*km|3\.10.*mi/i).first())
				.toBeVisible({ timeout: 5_000 });

			// No uncaught browser-side errors. (Console warnings from
			// `console.warn('Failed to fetch track', e)` are fine —
			// they're the expected resilience log. We only fail on
			// pageerror, which fires for unhandled exceptions.)
			expect(
				pageErrors.map((e) => e.message),
				'an unhandled exception during /runs/[id] mount means the try/catch around fetchTrack regressed'
			).toEqual([]);
		} finally {
			await deleteRun(runId);
		}
	});
});
