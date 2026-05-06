import { expect, test } from '@playwright/test';

import { isInAnyZone } from '../../src/lib/privacy';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Privacy-zone share guardrail.
 *
 * Runner has a seeded privacy zone at (-37.8136, 144.9631) radius 200 m
 * (`apps/backend/supabase/seed.sql` line 682). The owner-side Share
 * flow on `/runs/[id]` checks the run's track against `privacy_zones`
 * before flipping `is_public`; if any point falls inside a zone, a
 * ConfirmDialog warns the user that viewers will see a clipped track.
 *
 * Two paths covered:
 *  1. Cancel — `is_public` stays false; clicking Share again re-opens
 *     the dialog.
 *  2. "Share anyway" — `is_public` flips true and the page swaps to
 *     the post-share state (toast + clipboard write).
 *
 * Privacy-zone clipping for non-owner viewers is exercised separately
 * by `cross-cutting/auth-walls.spec.ts` (RLS leak checks).
 *
 * Why service-role plant instead of UI: the privacy-zone picker is a
 * MapLibre canvas — driving a click on a webgl canvas in Playwright is
 * brittle. The zone in seed.sql IS what the picker would write, so
 * the test still pins the read-side wiring (`loadSettings` →
 * `effective<PrivacyZone[]>`). The runs we plant are real rows with a
 * real gzipped track in Storage, so the share path runs unmodified.
 */

const ZONE_LAT = -37.8136;
const ZONE_LNG = 144.9631;

test.describe('privacy-zone share guardrail', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let zoneRunId: string | null = null;

	test.afterEach(async () => {
		if (zoneRunId) {
			try {
				await deleteRun(zoneRunId);
			} catch (_) {
				/* best-effort cleanup */
			}
			zoneRunId = null;
		}
	});

	test('Share on a run inside a privacy zone opens the warning dialog; Cancel keeps the run private', async ({
		page
	}) => {
		// Three track points dead-centre on runner's seeded zone — every
		// point falls inside the 200 m radius, so the share guard MUST
		// fire.
		zoneRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T08:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'e2e privacy-zone share test' },
			track: [
				{ lat: ZONE_LAT, lng: ZONE_LNG, ele: 10 },
				{ lat: ZONE_LAT + 0.0001, lng: ZONE_LNG + 0.0001, ele: 10 },
				{ lat: ZONE_LAT + 0.0002, lng: ZONE_LNG + 0.0002, ele: 10 }
			]
		});

		await page.goto(`/runs/${zoneRunId}`);

		// Wait for the page to mount past loading (the run title is the
		// title field saved on the metadata blob — see RunEditor and the
		// run-detail header).
		await expect(
			page.getByRole('heading', { level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Click Share. The button is icon-only with title="Share link";
		// playwright matches by accessible name (title attr).
		await page.locator('button[title="Share link"]').click();

		// The privacy-zone ConfirmDialog must appear with the warning
		// text. The dialog title is "Share through a privacy zone?".
		const dialog = page.locator('.modal', { hasText: 'Share through a privacy zone' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(dialog).toContainText(/clipped/i);

		// Cancel. Clipboard must NOT have received the share link, and
		// is_public must still be false. We assert via "click again →
		// dialog re-opens" — proves the run is still gated.
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);

		await page.locator('button[title="Share link"]').click();
		await expect(
			page.locator('.modal', { hasText: 'Share through a privacy zone' })
		).toBeVisible({ timeout: 5_000 });

		// Cancel again to leave the row in its private state for cleanup.
		await page
			.locator('.modal', { hasText: 'Share through a privacy zone' })
			.getByRole('button', { name: 'Cancel' })
			.click();
	});

	test('"Share anyway" flips is_public + the dialog does not re-open on a second click', async ({
		page,
		context
	}) => {
		// Grant clipboard permission so navigator.clipboard.writeText
		// in handleShare's success path doesn't reject and trip the
		// catch branch.
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: 'http://localhost:7777'
		});

		zoneRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T09:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			is_public: false,
			metadata: { activity_type: 'run', title: 'e2e privacy-zone share confirm' },
			track: [
				{ lat: ZONE_LAT, lng: ZONE_LNG, ele: 10 },
				{ lat: ZONE_LAT + 0.0001, lng: ZONE_LNG + 0.0001, ele: 10 }
			]
		});

		await page.goto(`/runs/${zoneRunId}`);
		await expect(
			page.getByRole('heading', { level: 1 })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button[title="Share link"]').click();
		const dialog = page.locator('.modal', { hasText: 'Share through a privacy zone' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });

		// Confirm.
		await dialog.getByRole('button', { name: 'Share anyway' }).click();
		await expect(dialog).toHaveCount(0);

		// makeRunPublic + a navigator.clipboard.writeText. The success
		// toast pins the happy path.
		await expect(
			page.getByText('Share link copied to clipboard')
		).toBeVisible({ timeout: 5_000 });

		// Reload so the in-memory `run.is_public` is rebuilt from the DB.
		// A second Share click should NOT show the dialog (the guard
		// short-circuits when the run is already public).
		await page.reload();
		await expect(
			page.getByRole('heading', { level: 1 })
		).toBeVisible({ timeout: 10_000 });
		await page.locator('button[title="Share link"]').click();
		// Toast appears immediately; dialog does not.
		await expect(
			page.locator('.modal', { hasText: 'Share through a privacy zone' })
		).toHaveCount(0);
	});
});

/**
 * Cross-user privacy clipping — the security guarantee from
 * decisions §33. A non-owner viewing a public run whose track passes
 * through the owner's privacy zones must NEVER receive the unclipped
 * blob. The clip happens server-side in the `clip-public-track`
 * Edge Function via `clip_track_for_user`; this test pins the wire
 * by capturing the EF response and asserting the returned points are
 * a strict subset that excludes everything inside the zone.
 *
 * The auth-walls suite stubs the EF (deliberately, to test the page's
 * empty-track branch). This test exercises the EF for real.
 */
const ZONE_LAT_X = -37.8136;
const ZONE_LNG_X = 144.9631;
const ZONE_RADIUS_M = 200;

test.describe('cross-user privacy-zone clipping', () => {
	let zoneRunId: string | null = null;

	test.afterEach(async () => {
		if (zoneRunId) {
			try {
				await deleteRun(zoneRunId);
			} catch (_) {
				/* best-effort */
			}
			zoneRunId = null;
		}
	});

	test('alex viewing runner\'s public run with track in a zone gets a clipped point set', async ({
		browser
	}) => {
		// Plant a run owned by runner with a 5-point track that
		// straddles the zone: 2 dead-centre on the zone, 3 well clear
		// (2 km north). clipPointsToZones walks forward + backward and
		// keeps the contiguous middle, so the EF should return only
		// the 3 outside points.
		const inZone = [
			{ lat: ZONE_LAT_X, lng: ZONE_LNG_X },
			{ lat: ZONE_LAT_X + 0.0001, lng: ZONE_LNG_X + 0.0001 }
		];
		const outOfZone = [
			{ lat: ZONE_LAT_X + 0.02, lng: ZONE_LNG_X },
			{ lat: ZONE_LAT_X + 0.021, lng: ZONE_LNG_X + 0.001 },
			{ lat: ZONE_LAT_X + 0.022, lng: ZONE_LNG_X + 0.002 }
		];
		const planted = [...inZone, ...outOfZone];

		zoneRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T10:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			is_public: true, // public from the start — non-owner read path
			metadata: { activity_type: 'run', title: 'e2e clipping test' },
			track: planted
		});

		// Open as alex — explicit non-owner. /share/run/<id> works
		// without auth too, but signed-in non-owner is the realistic
		// path for "follower viewing your run on the feed".
		const ctx = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const page = await ctx.newPage();
		try {
			// Capture the EF response on the way to /share/run.
			const efPromise = page.waitForResponse(
				(r) =>
					r.url().includes('/functions/v1/clip-public-track') &&
					r.request().method() === 'POST',
				{ timeout: 10_000 }
			);
			await page.goto(`/share/run/${zoneRunId}`);
			const ef = await efPromise;

			expect(ef.status()).toBe(200);
			const body = (await ef.json()) as { points: { lat: number; lng: number }[] };
			expect(Array.isArray(body.points)).toBe(true);

			// Strict subset: clipping happened.
			expect(body.points.length).toBeLessThan(planted.length);
			expect(body.points.length).toBeGreaterThan(0);

			// Stronger check: NO returned point may be inside the zone.
			// If a single point leaks through, the user's home address
			// is on the wire — the very leak the EF exists to prevent.
			const zones = [{ lat: ZONE_LAT_X, lng: ZONE_LNG_X, radius_m: ZONE_RADIUS_M }];
			for (const p of body.points) {
				expect(isInAnyZone(p, zones)).toBe(false);
			}
		} finally {
			await ctx.close();
		}
	});
});
