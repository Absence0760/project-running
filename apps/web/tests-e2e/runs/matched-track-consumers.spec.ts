import { expect, test } from '@playwright/test';

import { deleteRun, insertMatchedTrack, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — the map itself, and the direction scrubber over it, on a run
 * whose map-matched line has landed.
 *
 * `runs/matched-track-render.spec.ts` proves the PAGE prefers the matched
 * track, through the elevation chart, because that is the projection with
 * numbers in the DOM. `RunMap` is the other consumer of the same value and had
 * no coverage at all — and it was broken. Every snapshot the map derives from
 * its `track` prop (the drawn line, the camera bounds, the cumulative-distance
 * array and the tap index) was taken once, in `onMount`, while the run detail
 * fires `fetchRunMatchedTrack` WITHOUT awaiting it. So the map mounted on the
 * recorded line and stayed there forever, under a page whose own comment says
 * "the map will swap to the matched line once it lands"
 * ([§ 1402](../../../../docs/architecture/decisions.md)).
 *
 * Two DOM handles reach it, and the fixture is shaped so each is decisive:
 *
 *   * The CAMERA, read through the scrubber marker. The marker's position is
 *     `interpolateAlongRoute(baseTrack, f)` — the page's value, which was
 *     always the matched one — PROJECTED by the map, whose camera came from
 *     the snapshot. Give the two tracks disjoint bounding boxes and the two
 *     answers stop overlapping: measured before the fix, the marker sat at
 *     x=558363, y=-68309 against a 663x720 canvas. The camera and the drawn
 *     line come off the same snapshot, so this is the half of it with a DOM
 *     projection; there is no way to read a MapLibre line layer from outside
 *     the map instance. The 4 km offset is far larger than any real snap, on
 *     purpose — the point is that the two cameras cannot be confused.
 *
 *   * The SEGMENT CARD. A map click snaps through `RunMap`'s own cumulative
 *     array and reports distance / time / pace / avg HR. The two tracks are
 *     given DIFFERENT POINT COUNTS, which is the sharpest form of the old
 *     defect: `buildSegment` bails when `cumulativeM.length !== track.length`,
 *     so a matched line of a different length silently disabled tap-to-select
 *     altogether and no card rendered at all. The disjoint per-point `bpm`
 *     bands then name which track was measured.
 *
 * The settle point is the elevation chart's own extremes, not the network
 * response: past them the page has re-rendered on the matched value, which is
 * the same flush that hands the map its new track. `data-map-idle` is asserted
 * after, never before — the map clears that stamp when it adopts a new track
 * and re-arms it once the new camera stops moving, so waiting on it first
 * would read the OLD stamp and take a pixel measurement mid-animation.
 *
 * The `failed` case is the control on both halves: both tracks are renderable,
 * so a page that ignored the matched line would still draw a map, a marker and
 * a full segment card.
 */

const RAW_POINTS = 41;
const MATCHED_POINTS = 25;
const RAW_BPM = 132;
const MATCHED_BPM = 181;

function line(
	baseLat: number,
	baseEle: number,
	bpm: number,
	count: number,
): Array<{ lat: number; lng: number; ele: number; bpm: number; ts: string }> {
	return Array.from({ length: count }, (_, i) => ({
		lat: baseLat + (i / (count - 1)) * 0.01,
		lng: -0.31 + (i / (count - 1)) * 0.01,
		ele: baseEle + i,
		bpm,
		ts: new Date(Date.UTC(2026, 0, 1, 9, i)).toISOString(),
	}));
}

/** The recorded trace. */
const rawTrack = line(51.46, 100, RAW_BPM, RAW_POINTS);
/** What the worker wrote back: a disjoint box, a different point count. */
const matchedTrack = line(51.5, 500, MATCHED_BPM, MATCHED_POINTS);

const RAW_EXTREMES = [`▲ ${100 + RAW_POINTS - 1} m`, '▼ 100 m'];
const MATCHED_EXTREMES = [`▲ ${500 + MATCHED_POINTS - 1} m`, '▼ 500 m'];

function extremeLabels(page: import('@playwright/test').Page): Promise<string[]> {
	return page
		.locator('.extreme-text')
		.allTextContents()
		.then((all) => all.map((t) => t.replace(/\s+/g, ' ').trim()));
}

/** The avg-HR figure the segment card renders, or null while it has none. */
async function segmentBpm(page: import('@playwright/test').Page): Promise<number | null> {
	const stat = page
		.locator('.segment-stat')
		.filter({ has: page.locator('.segment-stat-label', { hasText: 'Avg HR' }) })
		.locator('.segment-stat-value');
	if ((await stat.count()) !== 1) return null;
	const text = (await stat.first().textContent()) ?? '';
	const m = text.match(/(\d+)/);
	return m ? Number(m[1]) : null;
}

test.describe('/runs/[id] — the map adopts the matched line', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId = '';

	test.beforeEach(async () => {
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 1_400,
			duration_s: 2_400,
			track: rawTrack,
		});
	});

	test.afterEach(async () => {
		if (runId) await deleteRun(runId);
		runId = '';
	});

	/** Navigate, settle past the swap (or past its absence), and settle the camera. */
	async function open(page: import('@playwright/test').Page, extremes: string[]) {
		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { name: 'Elevation Profile' })).toBeVisible({
			timeout: 15_000,
		});
		await expect.poll(() => extremeLabels(page), { timeout: 15_000 }).toEqual(extremes);
		await expect(page.locator('.map-panel [data-map-idle="true"]')).toBeAttached({
			timeout: 15_000,
		});
	}

	async function mapBox(page: import('@playwright/test').Page) {
		const box = await page.locator('.map-panel .maplibregl-canvas').boundingBox();
		if (!box) throw new Error('map canvas has no bounding box');
		return box;
	}

	test('the camera follows the matched line, so the scrubber marker lands on the map', async ({
		page,
	}) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, track: matchedTrack });
		await open(page, MATCHED_EXTREMES);

		const map = await mapBox(page);
		const marker = await scrubToHalfway(page);
		expect(marker.x).toBeGreaterThan(map.x);
		expect(marker.x).toBeLessThan(map.x + map.width);
		expect(marker.y).toBeGreaterThan(map.y);
		expect(marker.y).toBeLessThan(map.y + map.height);
	});

	test('a failed match leaves the camera on the recorded line', async ({ page }) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, status: 'failed' });
		await open(page, RAW_EXTREMES);
		await expect(page.locator('.match-pill')).toContainText('Snap failed');

		const map = await mapBox(page);
		const marker = await scrubToHalfway(page);
		expect(marker.x).toBeGreaterThan(map.x);
		expect(marker.x).toBeLessThan(map.x + map.width);
		expect(marker.y).toBeGreaterThan(map.y);
		expect(marker.y).toBeLessThan(map.y + map.height);
	});

	test('a map click reports the matched line, not the recorded one', async ({ page }) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, track: matchedTrack });
		await open(page, MATCHED_EXTREMES);

		const map = await mapBox(page);
		await page.mouse.click(map.x + map.width / 2, map.y + map.height / 2);

		// That the card renders AT ALL is half the claim: the two tracks differ
		// in length, which is the case `buildSegment` refused outright.
		await expect(page.locator('.segment-card')).toBeVisible({ timeout: 10_000 });
		await expect.poll(() => segmentBpm(page), { timeout: 10_000 }).toBe(MATCHED_BPM);
	});

	test('a failed match leaves the click on the recorded line', async ({ page }) => {
		await insertMatchedTrack({ run_id: runId, user_id: USER_A.id, status: 'failed' });
		await open(page, RAW_EXTREMES);

		const map = await mapBox(page);
		await page.mouse.click(map.x + map.width / 2, map.y + map.height / 2);

		await expect(page.locator('.segment-card')).toBeVisible({ timeout: 10_000 });
		await expect.poll(() => segmentBpm(page), { timeout: 10_000 }).toBe(RAW_BPM);
	});
});

/**
 * Drag the direction scrubber to its midpoint and report the preview marker's
 * page-space centre. The button stays held through the read: the marker only
 * exists while `scrubbing` is true.
 */
async function scrubToHalfway(
	page: import('@playwright/test').Page,
): Promise<{ x: number; y: number }> {
	const slider = page.getByTestId('route-scrubber');
	await expect(slider).toBeVisible({ timeout: 10_000 });
	await slider.scrollIntoViewIfNeeded();
	const box = await slider.boundingBox();
	if (!box) throw new Error('slider has no bounding box');
	const cy = box.y + box.height / 2;
	await page.mouse.move(box.x + box.width * 0.02, cy);
	await page.mouse.down();
	await page.mouse.move(box.x + box.width * 0.5, cy, { steps: 10 });

	const marker = page.getByTestId('route-preview-runner');
	await expect(marker).toBeVisible({ timeout: 10_000 });
	const mb = await marker.boundingBox();
	await page.mouse.up();
	if (!mb) throw new Error('marker has no bounding box');
	return { x: mb.x + mb.width / 2, y: mb.y + mb.height / 2 };
}
