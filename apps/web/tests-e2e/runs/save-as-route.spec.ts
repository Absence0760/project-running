import { expect, test } from '@playwright/test';

import { deleteRoute, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] → Save as route — CRUD from a tracked run to a saved route.
 *
 * `handleSaveAsRoute` calls `window.prompt('Name this route', defaultName)`,
 * then `saveRunAsRoute(runId, name, simplifiedTrack)`, then `goto`s to
 * `/routes/<new-id>`. The interesting bits are:
 *   - the prompt → Playwright's `dialog` event
 *   - the simplified-track upload (no separate Storage write — routes
 *     store waypoints inline as jsonb)
 *   - the post-create navigation
 *
 * Plants a run with a real track (not just metadata) via service-role
 * since runs need >=2 GPS points before the Save-as-route button is
 * enabled. Cleanup deletes both the run AND the new route so the
 * suite stays idempotent.
 */

test.describe('/runs/[id] — Save as route', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;
	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('Save-as-route round-trip: prompt → save → navigate to /routes/[id] with the chosen name', async ({
		page
	}) => {
		// Multi-point track far enough apart that simplifyTrack (10 m
		// epsilon, see saveRunAsRoute) keeps every point. Coordinates
		// in central Sydney — outside runner's Melbourne privacy zone
		// so the share guardrail from batch 10 doesn't fire.
		const track = [
			{ lat: -33.8688, lng: 151.2093, ele: 12 },
			{ lat: -33.87, lng: 151.21, ele: 14 },
			{ lat: -33.871, lng: 151.211, ele: 16 },
			{ lat: -33.872, lng: 151.212, ele: 18 },
			{ lat: -33.873, lng: 151.213, ele: 20 }
		];

		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T11:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'e2e save-as-route' },
			track
		});

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
			timeout: 10_000
		});

		// `handleSaveAsRoute` is gated on `run.track.length >= 2`. The
		// run is loaded into memory via `fetchRunById` which downloads
		// the track from Storage — wait for the Save-as-route button
		// to become enabled before clicking, or the click is a no-op.
		const saveButton = page.locator('button[title="Save as route"]');
		await expect(saveButton).toBeEnabled({ timeout: 10_000 });

		// Hook the prompt handler BEFORE the click. Playwright's
		// dialog event fires once and you must accept(text) or
		// dismiss() — leaving it hanging blocks the page.
		const routeName = `e2e-savedroute-${Date.now()}`;
		page.once('dialog', async (dialog) => {
			expect(dialog.type()).toBe('prompt');
			await dialog.accept(routeName);
		});

		// Click → prompt fires → accept → saveRunAsRoute → goto.
		await saveButton.click();

		// `goto` lands on /routes/<new-id>; capture the id for cleanup.
		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 10_000 });
		const m = page.url().match(/\/routes\/([0-9a-f-]+)$/);
		expect(m).not.toBeNull();
		routeId = m![1];

		// /routes/[id] renders the route name as h1 — proves the row
		// landed with the prompt's value, not the default placeholder.
		await expect(
			page.getByRole('heading', { level: 1, name: routeName })
		).toBeVisible({ timeout: 10_000 });
	});
});
