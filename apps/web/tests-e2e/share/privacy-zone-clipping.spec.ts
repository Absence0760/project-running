import { expect, test } from '@playwright/test';

import { isInAnyZone } from '../../src/lib/privacy';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun, setUserSetting } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

const PRIVACY_ZONES_KEY = 'privacy_zones';
const SEEDED_ZONE = { lat: -37.8136, lng: 144.9631, radius_m: 200, label: 'home' };

const ZONE_LAT = 51.5074;
const ZONE_LNG = -0.1278;
const ZONE_RADIUS_M = 300;
const TEST_ZONE = { lat: ZONE_LAT, lng: ZONE_LNG, radius_m: ZONE_RADIUS_M, label: 'e2e-clip-zone' };

const IN_ZONE_TRACK = [
	{ lat: ZONE_LAT, lng: ZONE_LNG, ele: 10 },
	{ lat: ZONE_LAT + 0.0002, lng: ZONE_LNG + 0.0002, ele: 10 }
];
const OUT_OF_ZONE_TRACK = [
	{ lat: ZONE_LAT + 0.02, lng: ZONE_LNG, ele: 12 },
	{ lat: ZONE_LAT + 0.021, lng: ZONE_LNG + 0.001, ele: 13 },
	{ lat: ZONE_LAT + 0.022, lng: ZONE_LNG + 0.002, ele: 14 }
];

test.describe('/share/run/[id] — server-side privacy-zone clipping', () => {
	let plantedRunId: string | null = null;

	test.beforeEach(async () => {
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [TEST_ZONE]);
		plantedRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-10T08:00:00Z').toISOString(),
			duration_s: 1500,
			distance_m: 4500,
			is_public: true,
			metadata: { activity_type: 'run', title: 'e2e share-page privacy clip' },
			track: [...IN_ZONE_TRACK, ...OUT_OF_ZONE_TRACK]
		});
	});

	test.afterEach(async () => {
		if (plantedRunId) {
			try {
				await deleteRun(plantedRunId);
			} catch {
				/* best-effort */
			}
			plantedRunId = null;
		}
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [SEEDED_ZONE]);
	});

	test('non-owner anon visitor receives a clipped point set from the Edge Function', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		try {
			const efPromise = page.waitForResponse(
				(r) =>
					r.url().includes('/functions/v1/clip-public-track') &&
					r.request().method() === 'POST',
				{ timeout: 15_000 }
			);
			await page.goto(`/share/run/${plantedRunId}`);
			const ef = await efPromise;

			expect(ef.status()).toBe(200);
			const body = (await ef.json()) as { points: Array<{ lat: number; lng: number }> };
			expect(Array.isArray(body.points)).toBe(true);
			expect(body.points.length).toBeGreaterThan(0);
			expect(body.points.length).toBeLessThan(IN_ZONE_TRACK.length + OUT_OF_ZONE_TRACK.length);

			const zones = [{ lat: ZONE_LAT, lng: ZONE_LNG, radius_m: ZONE_RADIUS_M }];
			for (const p of body.points) {
				expect(isInAnyZone(p, zones)).toBe(false);
			}

			const first = body.points[0];
			expect(first.lat).toBeGreaterThan(ZONE_LAT + 0.01);

			await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});

	test('authenticated non-owner (USER_B) receives the same clipped set', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		try {
			const efPromise = page.waitForResponse(
				(r) =>
					r.url().includes('/functions/v1/clip-public-track') &&
					r.request().method() === 'POST',
				{ timeout: 15_000 }
			);
			await page.goto(`/share/run/${plantedRunId}`);
			const ef = await efPromise;

			expect(ef.status()).toBe(200);
			const body = (await ef.json()) as { points: Array<{ lat: number; lng: number }> };
			const zones = [{ lat: ZONE_LAT, lng: ZONE_LNG, radius_m: ZONE_RADIUS_M }];
			for (const p of body.points) {
				expect(isInAnyZone(p, zones)).toBe(false);
			}
			expect(body.points.length).toBe(OUT_OF_ZONE_TRACK.length);
		} finally {
			await ctx.close();
		}
	});

	test('owner viewing /share/run/[id] bypasses the EF and gets the unclipped track via direct Storage', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		try {
			let efHit = false;
			page.on('response', (r) => {
				if (r.url().includes('/functions/v1/clip-public-track')) {
					efHit = true;
				}
			});

			const storagePromise = page.waitForResponse(
				(r) =>
					r.url().includes(`/storage/v1/object`) &&
					r.url().includes(`${plantedRunId}.json.gz`) &&
					r.request().method() === 'GET',
				{ timeout: 15_000 }
			);

			await page.goto(`/share/run/${plantedRunId}`);
			const storageRes = await storagePromise;
			expect(storageRes.status()).toBe(200);

			await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
			await page.waitForTimeout(500);
			expect(efHit).toBe(false);
		} finally {
			await ctx.close();
		}
	});
});

test.describe('/share/run/[id] — owner-zone clipping uses owner zones, not viewer zones', () => {
	let plantedRunId: string | null = null;

	test.beforeEach(async () => {
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [TEST_ZONE]);
		plantedRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-10T09:00:00Z').toISOString(),
			duration_s: 1500,
			distance_m: 4500,
			is_public: true,
			metadata: { activity_type: 'run', title: 'e2e zone-ownership clip' },
			track: [...IN_ZONE_TRACK, ...OUT_OF_ZONE_TRACK]
		});
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (plantedRunId) {
			try {
				await deleteRun(plantedRunId);
			} catch {
				/* best-effort */
			}
			plantedRunId = null;
		}
		await setUserSetting(USER_A.id, PRIVACY_ZONES_KEY, [SEEDED_ZONE]);
		await admin.from('user_settings').update({ prefs: {} }).eq('user_id', USER_B.id);
	});

	test("USER_B's own zones do not influence clipping of runner's run", async ({ browser }) => {
		await setUserSetting(USER_B.id, PRIVACY_ZONES_KEY, [
			{ lat: ZONE_LAT + 0.022, lng: ZONE_LNG + 0.002, radius_m: 500 }
		]);

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		try {
			const efPromise = page.waitForResponse(
				(r) =>
					r.url().includes('/functions/v1/clip-public-track') &&
					r.request().method() === 'POST',
				{ timeout: 15_000 }
			);
			await page.goto(`/share/run/${plantedRunId}`);
			const ef = await efPromise;
			const body = (await ef.json()) as { points: Array<{ lat: number; lng: number }> };

			const ownerZones = [{ lat: ZONE_LAT, lng: ZONE_LNG, radius_m: ZONE_RADIUS_M }];
			for (const p of body.points) {
				expect(isInAnyZone(p, ownerZones)).toBe(false);
			}
			expect(body.points.length).toBe(OUT_OF_ZONE_TRACK.length);
		} finally {
			await ctx.close();
		}
	});
});
