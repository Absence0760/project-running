import { expect, test } from '@playwright/test';

import { deleteRoute, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] → Save as route — CRUD from a tracked run to a saved route.
 *
 * `handleSaveAsRoute` opens the in-app name modal (Modal + text input,
 * the create-flow shape) pre-filled with the run title (or its ISO
 * date), then `confirmSaveAsRoute` calls `saveRunAsRoute(runId, name,
 * simplifiedTrack)` and `goto`s to `/routes/<new-id>`. Replaces the old
 * `window.prompt`, which some webviews suppress. The interesting bits:
 *   - the styled modal (not a native dialog)
 *   - non-empty name validation gating the Save button
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

	test('Save-as-route round-trip: modal → edit name → save → navigate to /routes/[id]', async ({
		page
	}) => {
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

		// Click opens the styled modal — no native dialog fires.
		await saveButton.click();
		const dialog = page.getByTestId('name-route-dialog');
		await expect(dialog).toBeVisible();

		// Pre-filled with the run's title, per the default-name behaviour.
		const nameInput = page.getByTestId('name-route-input');
		await expect(nameInput).toHaveValue('e2e save-as-route');

		const routeName = `e2e-savedroute-${Date.now()}`;
		await nameInput.fill(routeName);
		await page.getByTestId('name-route-save').click();

		// confirmSaveAsRoute → saveRunAsRoute → goto lands on
		// /routes/<new-id>; capture the id for cleanup.
		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 10_000 });
		const m = page.url().match(/\/routes\/([0-9a-f-]+)$/);
		expect(m).not.toBeNull();
		routeId = m![1];

		// /routes/[id] renders the route name as h1 — proves the row
		// landed with the modal's value, not the default placeholder.
		await expect(
			page.getByRole('heading', { level: 1, name: routeName })
		).toBeVisible({ timeout: 10_000 });
	});

	test('Save button is disabled when the name is blank (non-empty validation)', async ({
		page
	}) => {
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-01T11:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'e2e blank-name' },
			track
		});

		await page.goto(`/runs/${runId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
			timeout: 10_000
		});

		const saveButton = page.locator('button[title="Save as route"]');
		await expect(saveButton).toBeEnabled({ timeout: 10_000 });
		await saveButton.click();

		await expect(page.getByTestId('name-route-dialog')).toBeVisible();
		const confirm = page.getByTestId('name-route-save');
		await expect(confirm).toBeEnabled();

		// Clearing the name (or leaving only whitespace) disables Save —
		// the modal can validate where window.prompt could not.
		await page.getByTestId('name-route-input').fill('   ');
		await expect(confirm).toBeDisabled();
	});
});
