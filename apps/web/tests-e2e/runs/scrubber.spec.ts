import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — Preview scrubber marker positioning.
 *
 * Repro for the May 2026 "circle appears at top-left of the map
 * instead of on the route polyline" bug. Drives the slider, then
 * reads the route-preview-runner marker's CSS transform to verify
 * MapLibre actually projected the lng/lat to a sensible pixel
 * position inside the map canvas (not 0,0).
 */

test.describe('/runs/[id] — Preview scrubber marker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('drag scrubber → marker mounts on the polyline (not at map origin)', async ({
		page,
	}) => {
		// Build a track that crosses Virginia — same kind of data the
		// `seed-run-tracks.mjs` helper uploads, just inlined so the
		// test owns its lifecycle.
		const track = Array.from({ length: 40 }, (_, i) => ({
			lat: 37.531 + i * 0.0005,
			lng: -77.452 + i * 0.0005,
			ele: 50 + i,
			ts: new Date(2026, 4, 15, 7, 30, i * 6).toISOString(),
		}));
		const planted = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-15T07:30:00Z').toISOString(),
			distance_m: 3000,
			duration_s: 1200,
			source: 'app',
			track,
			metadata: { activity_type: 'run', title: 'Scrubber repro' },
		});

		try {
			await page.goto(`/runs/${planted}`);

			// Wait for the map to mount + the scrubber section to render
			// (it lives in the info panel below the key-stats grid).
			const map = page.locator('.maplibregl-map').first();
			await expect(map).toBeVisible({ timeout: 15_000 });
			const slider = page.getByTestId('route-scrubber');
			await expect(slider).toBeVisible({ timeout: 5_000 });

			// Marker should be absent before the user drags.
			await expect(
				page.getByTestId('route-preview-runner'),
			).toHaveCount(0);

			// Drive a REAL mouse drag. Dispatching `input` events
			// programmatically doesn't fire pointerdown, and the
			// scrubber only flips `scrubbing = true` on pointerdown —
			// so a synthetic input alone wouldn't activate the marker.
			// Native `page.mouse` API exercises the full event chain.
			//
			// Scroll the slider into view first — the info panel
			// scrolls and the scrubber section can land below the
			// initial viewport on tall content. boundingBox() of an
			// off-screen element returns its layout coords, not screen
			// coords, and page.mouse.move uses screen coords; so a
			// drag against an off-screen bbox lands on whatever was
			// rendered there instead.
			await slider.scrollIntoViewIfNeeded();
			await page.waitForTimeout(150);
			const box = await slider.boundingBox();
			if (!box) throw new Error('slider has no bounding box');
			const midX = box.x + box.width * 0.5;
			const cy = box.y + box.height / 2;
			await page.mouse.move(box.x + box.width * 0.02, cy);
			await page.mouse.down();
			await page.mouse.move(midX, cy, { steps: 10 });

			// Keep the button held: the marker is only rendered while
			// `scrubbing` is true.
			const marker = page.getByTestId('route-preview-runner');
			await expect(marker).toBeVisible({ timeout: 5_000 });
			const inMap = await marker.evaluate((el) =>
				Boolean(el.closest('.maplibregl-map')),
			);
			expect(inMap, 'marker must live under the map container').toBe(true);

			// CRITICAL: the marker's wrapping element (the
			// .maplibregl-marker div MapLibre creates around our `el`)
			// gets `transform: translate(<x>px, <y>px) translate(-50%, -50%)`.
			// If MapLibre projected NaN / 0,0 we'd see `translate(0px,
			// 0px)` here. Anything else proves projection worked.
			const transform = await marker.evaluate((el) => {
				const wrap = el.closest('.maplibregl-marker') as HTMLElement | null;
				return wrap?.style.transform ?? '';
			});

			// Extract the first translate's pixel offsets.
			const match = transform.match(/translate\(([\-\d.]+)px,\s*([\-\d.]+)px\)/);
			expect(
				match,
				`expected translate(...) in marker transform, got: "${transform}"`,
			).not.toBeNull();
			if (!match) return;
			const x = parseFloat(match[1]);
			const y = parseFloat(match[2]);
			expect(Number.isFinite(x), `x must be finite, got ${x}`).toBe(true);
			expect(Number.isFinite(y), `y must be finite, got ${y}`).toBe(true);
			// MapLibre projects (0,0) as the marker container's
			// origin — top-left of the map div. The May 2026 bug was
			// "circle stuck at the top-left of the map" caused by
			// non-finite lngLat collapsing the translate3d to (0,0).
			// Any non-trivial offset rules that class of bug out.
			expect(x).toBeGreaterThan(50);
			expect(y).toBeGreaterThan(50);

			await page.mouse.up();
		} finally {
			await deleteRun(planted);
		}
	});
});
