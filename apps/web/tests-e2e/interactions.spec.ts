import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from './fixtures/helpers';
import { RUNNER_PUBLIC_ROUTE_ID } from './fixtures/seeded-data';
import { USER_A, USER_C_PRO } from './fixtures/users';

/**
 * Interaction spec — UI state that must survive a navigation, reload,
 * or cross-user write. Smoke / security / data-flow / happy-paths
 * already cover sign-in, RLS, CRUD, and multi-step flows; this spec
 * focuses on the next layer down — the bits of UI plumbing that
 * silently break when a $state declaration loses sync with the
 * persistence layer (localStorage, the auth store, the user_profiles
 * row).
 *
 * Five describe blocks:
 *   - Run filter state persists across reload (localStorage).
 *   - Routes search narrows the My-routes list.
 *   - Theme toggle persists across reload (data-theme attribute).
 *   - Follow → unfollow toggles button + counter on /u/[id].
 *   - Anonymous /share/route/[id] mounts the public route.
 */

test.describe('Run filter state persists across reload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('switching activity + date range survives a reload', async ({
		page
	}) => {
		// /runs writes the filter set to localStorage (`runs_filters_v1`)
		// inside a `filtersHydrated`-gated $effect. The regression risk
		// is that the writer fires *before* hydration finishes (saves
		// stale defaults over the user's choice) or that the reader
		// crashes silently on a malformed blob and the user's filter is
		// silently reset every page-load.
		await page.goto('/runs');
		await switchRunsToAllTime(page);
		await expect(page.locator('.run-card').first()).toBeVisible();

		await page.getByRole('button', { name: 'Walk', exact: true }).click();
		await expect(page.locator('.run-card')).toHaveCount(1);

		// Reload — both selections must hold.
		await page.reload();
		await page.waitForLoadState('networkidle');

		// The Walk activity-button stays `aria-pressed=true` after
		// hydration if persistence works.
		await expect(
			page.getByRole('button', { name: 'Walk', exact: true })
		).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByLabel('Date range')).toHaveValue('all');
		await expect(page.locator('.run-card')).toHaveCount(1);

		// Restore so subsequent tests don't inherit a Walk filter via
		// shared localStorage state inside the same browser context.
		await page.getByRole('button', { name: 'All', exact: true }).click();
		await page.getByLabel('Date range').selectOption('today');
	});
});

test.describe('Routes search narrows the My-routes list', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('typing a substring filters routes by name', async ({ page }) => {
		// /routes computes `filteredRoutes` from a $derived that does a
		// case-insensitive substring match on `name`. Pinned route
		// "E2E demo public route" plus the seed's "Richmond Park Loop /
		// Thames Path 5K / Battersea / Sunday Long Run / Commute Run"
		// give us > 1 row to start with.
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.route-card').first()).toBeVisible();

		const before = await page.locator('.route-card').count();
		expect(before).toBeGreaterThan(2);

		// "Richmond" → exactly the Richmond Park Loop seed row.
		await page.getByLabel('Search routes').fill('Richmond');
		await expect(page.locator('.route-card')).toHaveCount(1);
		await expect(
			page.locator('.route-card').first()
		).toContainText('Richmond Park Loop');

		// Clear by clicking the clear button — exposed for that purpose.
		await page.getByRole('button', { name: 'Clear search' }).click();
		await expect(page.locator('.route-card')).toHaveCount(before);
	});
});

test.describe('Theme toggle persists across reload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('switching to Dark applies html[data-theme] + survives reload', async ({
		page
	}) => {
		// `applyTheme` writes `html.dataset.theme = <value>` AND
		// localStorage; the layout's onMount calls `initTheme()` which
		// reads localStorage. The combination should be idempotent
		// across navigations and reloads — a regression here means
		// "user picks dark, comes back tomorrow, sees light" which is
		// a subtle UX bug you'd never catch without an integration
		// test.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: 'Dark', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Reload to confirm initTheme on a fresh load resurrects it.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Restore to Auto so subsequent tests don't render against a
		// stale dark-mode root attribute. (Auto + no media-query
		// preference still puts data-theme=auto on the root.)
		await page.getByRole('button', { name: 'Auto', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'auto');
	});
});

test.describe('Follow → unfollow toggles button + counter', () => {
	// USER_C_PRO (morgan) has no outgoing follows in the seed. Visiting
	// runner's profile shows "Follow"; click it to follow, click again
	// to unfollow — the cycle leaves the seed state untouched at the
	// end so the suite stays idempotent.
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('morgan follows runner, counter increments, then unfollow restores', async ({
		page
	}) => {
		await page.goto(`/u/${USER_A.id}`);
		await page.waitForLoadState('networkidle');

		// Header h1 confirms we landed on runner's page (display_name
		// from seed).
		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Capture the starting follower count (alex already follows
		// runner, so it's at least 1) — the test asserts a delta, not
		// an absolute, so it's robust to other tests adding seeds.
		const followerCountText = page
			.locator('button.count', { hasText: 'Followers' })
			.locator('.count-num');
		const before = parseInt((await followerCountText.textContent()) ?? '0', 10);

		// The follow button has a Material Symbols icon span whose
		// ligature text ("person_add" / "check") becomes part of the
		// accessible name — `getByRole({ name: 'Follow', exact: true })`
		// would never match. Target by the dedicated `.btn-follow`
		// class instead, and assert state via the "Following" suffix.
		const followBtn = page.locator('button.btn-follow');
		await expect(followBtn).toBeVisible({ timeout: 10_000 });
		await expect(followBtn).not.toContainText('Following');
		await followBtn.click();

		// After follow: button label flips to "Following", counter +1.
		await expect(followBtn).toContainText('Following', { timeout: 5_000 });
		await expect(followerCountText).toHaveText(String(before + 1));

		// Unfollow restores both.
		await followBtn.click();
		await expect(followBtn).not.toContainText('Following', { timeout: 5_000 });
		await expect(followerCountText).toHaveText(String(before));
	});
});

test.describe('Anonymous /share/route/[id]', () => {
	// Storage-state-less context — anon viewer.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees the public route name + meta', async ({ page }) => {
		// The route share path goes through fetchRouteById, which for
		// anon hits the `public_routes` view — that view drops `geom`
		// and `start_point` and ships the rest. Pinned public route
		// is "E2E demo public route" with distance 10000 m + surface
		// road; the page should render those into h1 + .route-meta.
		await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'E2E demo public route', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// The .route-meta strip carries distance + surface tag.
		await expect(page.locator('.surface-tag')).toContainText('road');
		await expect(page.locator('.route-meta')).toContainText('10');
	});
});
