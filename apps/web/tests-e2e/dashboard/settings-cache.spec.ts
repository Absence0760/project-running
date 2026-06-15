import { expect, test } from '@playwright/test';

import { refreshStorageState, signOut } from '../fixtures/helpers';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard — offline-first universal-prefs cache (decisions §79).
 *
 * Pins three properties of `apps/web/src/lib/settings/settings.ts` +
 * `apps/web/src/lib/settings/settings_cache.ts`:
 *
 *   1. A successful loadSettings populates localStorage under the
 *      user-scoped `settings_cache_universal_<userId>` key with the
 *      shape `effective<T>` reads against.
 *   2. With the cache populated, a subsequent dashboard mount under a
 *      network outage for `user_settings*` / `user_device_settings*`
 *      still renders the bag-backed cards (HR-zone-driven intensity,
 *      training-load HR signal) using the cached values.
 *   3. Sign-out drops the prior user's cache so a re-sign-in as a
 *      different user can't read or replay against the wrong account.
 *
 * Regression risk: a refactor that switches loadSettings back to
 * network-only (or that scopes the cache by something other than
 * userId) would silently make the dashboard fail to render under
 * any network blip.
 */

const PREFS_CACHE_KEY = `settings_cache_universal_${USER_A.id}`;

const FIXED_ZONES = { z1: 130, z2: 145, z3: 160, z4: 175, z5: 195 };

test.describe('/dashboard — universal prefs cache', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		// Plant deterministic HR prefs so the test isn't coupled to seed
		// drift. setUserSetting is the canonical seam — same one
		// privacy-zone tests use.
		await setUserSetting(USER_A.id, 'hr_zones', FIXED_ZONES);
		await setUserSetting(USER_A.id, 'resting_hr_bpm', 52);
		await setUserSetting(USER_A.id, 'max_hr_bpm', 190);
	});

	test('loadSettings populates the user-scoped localStorage cache after a dashboard mount', async ({
		page,
	}) => {
		await page.goto('/dashboard');
		// Wait until the dashboard's onMount loadSettings call has run.
		// The fitness card is gated on a successful settings load, so
		// once the heading is visible the cache write has happened.
		await expect(
			page.getByRole('heading', { name: /mileage/i, level: 2 }),
		).toBeVisible();

		// Poll because the cache write happens after the dashboard's
		// onMount await — using a plain getItem read would race the
		// first paint on a slow runner.
		await expect
			.poll(
				() => page.evaluate((key) => localStorage.getItem(key), PREFS_CACHE_KEY),
				{ timeout: 5_000 },
			)
			.not.toBeNull();

		const raw = await page.evaluate(
			(key) => localStorage.getItem(key),
			PREFS_CACHE_KEY,
		);
		const cached = JSON.parse(raw!) as Record<string, unknown>;
		expect(cached.resting_hr_bpm).toBe(52);
		expect(cached.max_hr_bpm).toBe(190);
		expect(cached.hr_zones).toEqual(FIXED_ZONES);
	});

	test('cached prefs let the dashboard render its bag-backed cards even with the settings PostgREST endpoints offline', async ({
		page,
	}) => {
		// First visit: prime the cache.
		await page.goto('/dashboard');
		await expect(
			page.getByRole('heading', { name: /mileage/i, level: 2 }),
		).toBeVisible();
		await expect
			.poll(
				() => page.evaluate((key) => localStorage.getItem(key), PREFS_CACHE_KEY),
				{ timeout: 5_000 },
			)
			.not.toBeNull();

		// Now sever the network path to both prefs tables — every
		// subsequent loadSettings round-trip will throw. The runs +
		// profile fetches keep working, so the rest of the dashboard
		// continues to render normally. The cache MUST be load-bearing
		// here: if the cache-first path regressed, the bag-backed cards
		// would either be empty or never resolve.
		await page.route('**/rest/v1/user_settings**', (route) =>
			route.abort('failed'),
		);
		await page.route('**/rest/v1/user_device_settings**', (route) =>
			route.abort('failed'),
		);

		await page.goto('/dashboard');
		await expect(
			page.getByRole('heading', { name: /mileage/i, level: 2 }),
		).toBeVisible();

		// Cache still has the planted prefs — a regression that
		// overwrote it on a failed fetch would null these out.
		const raw = await page.evaluate(
			(key) => localStorage.getItem(key),
			PREFS_CACHE_KEY,
		);
		const cached = JSON.parse(raw!) as Record<string, unknown>;
		expect(cached.resting_hr_bpm).toBe(52);
		expect(cached.max_hr_bpm).toBe(190);
		expect(cached.hr_zones).toEqual(FIXED_ZONES);
	});

	test('sign-out drops the cached prefs for the prior user (cross-user leak guard)', async ({
		page,
		browser,
		baseURL,
	}) => {
		try {
			await page.goto('/dashboard');
			await expect(
				page.getByRole('heading', { name: /mileage/i, level: 2 }),
			).toBeVisible();
			await expect
				.poll(
					() => page.evaluate((key) => localStorage.getItem(key), PREFS_CACHE_KEY),
					{ timeout: 5_000 },
				)
				.not.toBeNull();

			// Driving the actual UI flow proves the store's logout() hook
			// (which calls dropUserCache before nulling user/loggedIn) is
			// wired correctly. Calling auth.logout() via window would
			// bypass the affordance the user actually reaches for.
			await signOut(page);

			// Cache for the signed-out user is gone.
			const raw = await page.evaluate(
				(key) => localStorage.getItem(key),
				PREFS_CACHE_KEY,
			);
			expect(raw).toBeNull();
		} finally {
			// The UI sign-out called supabase.auth.signOut({ scope: 'local' }),
			// which revokes the refresh token of the SHARED session captured in
			// .auth/user-a.json during globalSetup — not just this page's copy.
			// Without re-minting it, the next USER_A spec sharded after this one
			// loads a revoked session and bounces to /login (run 27567813578:
			// week-strip.spec.ts saw the sign-in page, not the dashboard). Same
			// hazard + same remedy as the password-rotation specs in
			// auth/reset.spec.ts. Pinned by the e2e-session-hygiene guard.
			await refreshStorageState(browser, baseURL ?? 'http://localhost:7777', USER_A);
		}
	});
});
