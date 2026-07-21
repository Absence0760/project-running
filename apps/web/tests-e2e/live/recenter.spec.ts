import { expect, test } from '@playwright/test';

import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

// Issue #602. The follow-cam pans to the runner on every ping, so without
// a user-pan latch a spectator who drags away to read the course gets
// yanked back seconds later — and once pings go sparse there was no
// affordance to snap back to the runner at all. Mirrors mobile
// LiveRunMap's `_userPanned` latch + my_location re-center FAB.
test.describe('/live/[id] — pan latch + re-center on runner', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		// The map only mounts behind the MapTiler consent gate; accept it
		// up front the same way next_cutoff.spec.ts does.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('dragging the map latches the follow-cam off and the re-center control restores it', async ({
		page
	}) => {
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ lat: -37.816, lng: 144.97, distance_m: 1_000, elapsed_s: 300 },
					{ lat: -37.8175, lng: 144.972, distance_m: 2_000, elapsed_s: 600 },
					{ lat: -37.82, lng: 144.975, distance_m: 3_000, elapsed_s: 900 }
				]
			});

			await page.goto(`/live/${runId}`);
			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});

			// The map must mount from pre-stored consent alone (no "Load
			// map" click) — pins the $effect init path that replaced the
			// onMount call racing the container bind.
			await expect(page.locator('.live-map .maplibregl-canvas')).toBeVisible({
				timeout: 10_000
			});

			// Not latched yet — the control only appears after a user pan.
			const recentre = page.getByRole('button', {
				name: /Re-center on runner/i
			});
			await expect(recentre).toBeHidden();

			const box = await page.locator('.live-map').boundingBox();
			expect(box).not.toBeNull();
			const cx = box!.x + box!.width / 2;
			const cy = box!.y + box!.height / 2;
			await page.mouse.move(cx, cy);
			await page.mouse.down();
			await page.mouse.move(cx + 90, cy + 60, { steps: 10 });
			await page.mouse.up();

			// The drag latched the follow-cam off and surfaced the control.
			await expect(recentre).toBeVisible();

			// Clicking clears the latch (control gone, follow resumes).
			await recentre.click();
			await expect(recentre).toBeHidden();
		} finally {
			await deleteRun(runId);
		}
	});
});
