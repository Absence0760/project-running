import { expect, test } from '@playwright/test';

import { deleteRun, insertMatchedTrack, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — when the map-match worker has produced a line, THAT line is
 * what the page draws.
 *
 * `baseTrack` prefers `matchInfo.track` over `run.track` and is the single
 * value the map, the elevation profile and the direction scrubber all read,
 * so which of the two tracks it resolves to is a real rendering decision made
 * on every owner's run detail. Nothing under `tests-e2e/` had ever planted a
 * `matched_track_url` with a Storage object behind it, so the whole path —
 * the owner-gated `run_matched_tracks` read, the lazy download of a SECOND
 * gzipped object out of the `runs` bucket, and the preference itself — ran
 * only in production.
 *
 * The elevation profile is what the assertions read, because it is the one
 * projection of `baseTrack` with numbers in the DOM: the map is a MapLibre
 * canvas. The two tracks are given disjoint elevation bands so the extremes
 * name which track was drawn and cannot be reached from the other.
 *
 * **Every assertion here is a claim about the SETTLED page, and has to be
 * written as one.** `fetchRunMatchedTrack` is fired without `await` — the
 * page draws the RECORDED track immediately and swaps when the second
 * gzipped object lands. An auto-retrying matcher polls that transition, so
 * one asking for the recorded band is satisfied by the first frame and
 * passes; on a faster machine it misses the window and fails. That is the
 * non-determinism [§ 1313](../../../../docs/architecture/decisions.md)
 * recorded, and it is a race, not a matcher defect — the SVG explanation
 * that ADR gave is refuted in § 1357. So the wait is anchored on the matched
 * object's own download, armed before the navigation: past it the swap has
 * happened and the labels can only be the matched band. Without it the
 * inverse assertion — the one that proves this test is sensitive to the
 * value at all — is satisfied by the first frame, and was measured passing
 * on one run in three.
 *
 * `extremeLabels` reads `textContent` because it feeds `expect.poll` — the
 * response resolving is a step ahead of Svelte's re-render, so the read
 * still has to be retried. `toHaveText` would work on these SVG `<text>`
 * elements too; it is simply the weaker assertion here, matching per element
 * rather than on the whole normalised array.
 *
 * The `failed` case beside it is the control. Both tracks are renderable, so
 * a page that ignored the matched line entirely would still show a profile,
 * a map and a full set of stats — the pair is what separates "the matched
 * line rendered" from "a line rendered".
 */
const RAW_BASE_ELE = 100;
const MATCHED_BASE_ELE = 500;
const POINTS = 6;

/** The recorded trace: a straight run, elevations 100..105. */
const rawTrack = Array.from({ length: POINTS }, (_, i) => ({
	lat: 51.46 + i * 0.0005,
	lng: -0.3,
	ele: RAW_BASE_ELE + i,
	t: new Date(Date.UTC(2026, 0, 1, 9, i)).toISOString(),
}));

/** What the worker would write back: the same run snapped a little west,
 *  elevations 500..505 — a band the recorded trace never enters. */
const matchedTrack = Array.from({ length: POINTS }, (_, i) => ({
	lat: 51.46 + i * 0.0005,
	lng: -0.3001,
	ele: MATCHED_BASE_ELE + i,
	t: new Date(Date.UTC(2026, 0, 1, 9, i)).toISOString(),
}));

/** The chart's max-then-min corner pills, whitespace-normalised. */
function extremeLabels(page: import('@playwright/test').Page): Promise<string[]> {
	return page
		.locator('.extreme-text')
		.allTextContents()
		.then((all) => all.map((t) => t.replace(/\s+/g, ' ').trim()));
}

test.describe('/runs/[id] — the matched line is what renders', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId = '';

	test.beforeEach(async () => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 3_000,
			duration_s: 900,
			track: rawTrack,
		});
	});

	test.afterEach(async () => {
		if (runId) await deleteRun(runId);
		runId = '';
	});

	test('a matched run draws the matched elevations, not the recorded ones', async ({ page }) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, track: matchedTrack });

		// Armed before the navigation: this is the settle point the doc
		// comment describes, and the page has already issued the request by
		// the time `goto` resolves.
		const matchedObjectFetched = page.waitForResponse(
			(r) => r.url().includes('.matched.json.gz') && r.status() === 200,
			{ timeout: 15_000 },
		);
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Elevation Profile' })).toBeVisible({
			timeout: 15_000,
		});
		await matchedObjectFetched;

		// Max pill then min pill, in document order. Both come off the matched
		// band; neither value exists anywhere in the recorded trace.
		await expect.poll(() => extremeLabels(page), { timeout: 15_000 }).toEqual([
			'\u25b2 505 m',
			'\u25bc 500 m',
		]);

		// `matched` is the one status the pill stays silent for — the cleaner
		// line is the message. Its absence is therefore part of the claim.
		await expect(page.locator('.match-pill')).toHaveCount(0);
	});

	test('a failed match falls back to the recorded track', async ({ page }) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, status: 'failed' });

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Elevation Profile' })).toBeVisible({
			timeout: 15_000,
		});

		await expect.poll(() => extremeLabels(page), { timeout: 15_000 }).toEqual([
			'\u25b2 105 m',
			'\u25bc 100 m',
		]);
		await expect(page.locator('.match-pill')).toContainText('Snap failed');
	});
});
