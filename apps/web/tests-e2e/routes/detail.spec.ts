import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — owner-only route detail page.
 *
 * Operations covered: star toggle (with /routes filter round-trip).
 * Future depth: public toggle, tags edit, route reviews, GPX export.
 * The anon /share/route/[id] view is in share/route.spec.ts.
 */

test.describe('/routes/[id]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('star + reload + starred-only filter shows it + unstar restores', async ({
		page
	}) => {
		// Star toggles `routes.is_starred` via setRouteStar; the route
		// detail page renders a .star-btn button (owner-only, gated on
		// isOwner). Pinned RUNNER_PUBLIC_ROUTE_ID seeds with no star.
		// The starred-only filter on /routes hides everything that
		// isn't starred — so a successful round-trip + reload puts the
		// route in that view. Catches regressions in either the write
		// (RLS dropping the update) or the list re-fetch (filter
		// reading a stale cache).
		//
		// Cleanup unstars at the end so the seed state is preserved.
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		const starBtn = page.locator('button.star-btn');
		await expect(starBtn).toBeVisible({ timeout: 10_000 });
		await expect(starBtn).not.toHaveClass(/starred/);

		await starBtn.click();
		await expect(starBtn).toHaveClass(/starred/);

		// Reload — server-side state must agree.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('button.star-btn')).toHaveClass(/starred/, {
			timeout: 10_000
		});

		// Visit /routes; flip the starred-only filter; the pinned
		// route should appear in the narrowed list.
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: /Show starred only/ }).click();
		await expect(
			page.locator(`.route-card[href$="${RUNNER_PUBLIC_ROUTE_ID}"]`)
		).toBeVisible({ timeout: 10_000 });

		// Cleanup: clear the filter + unstar so the next test sees a
		// clean slate. (filteredRoutes is in localStorage as
		// `routes_filters_v1`; the search test in routes/list.spec.ts
		// would otherwise inherit starredOnly=true.)
		await page.getByRole('button', { name: /Show starred only/ }).click();
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');
		await page.locator('button.star-btn').click();
		await expect(page.locator('button.star-btn')).not.toHaveClass(/starred/);
	});
});
