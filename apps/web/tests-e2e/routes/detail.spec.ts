import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — owner-only route detail page.
 *
 * Operations covered: public toggle, star toggle (with /routes filter
 * round-trip), tag add + remove. The anon /share/route/[id] view is
 * in share/route.spec.ts. Routes have NO UI delete affordance — the
 * only delete path is service-role / SQL — so there's no
 * "delete via UI" test here.
 */

test.describe('/routes/[id]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('public toggle: Public → Private, reload persists, back to Public', async ({
		page
	}) => {
		// `togglePublic` calls setRoutePublic which updates `is_public`
		// on the routes row. Owner-only button — gated on `isOwner`.
		// The button text flips between "Public" / "Private". Catches
		// regressions in either the write (RLS dropping the update)
		// or the optimistic rollback (button text reverts on error).
		// Pinned route starts public; cleanup leaves it public.
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		// The button text content is "public Public" (icon ligature +
		// label) so a plain text regex pulls in the icon span. Target
		// by the `title` attribute which is unique to this button —
		// "Public — tap to make private" / "Private — tap to make
		// public".
		const toggleBtn = () =>
			page.locator('button[title^="Public"], button[title^="Private"]');
		await expect(toggleBtn()).toBeVisible({ timeout: 10_000 });
		await expect(toggleBtn()).toHaveAttribute('title', /^Public/);

		await toggleBtn().click();
		await expect(toggleBtn()).toHaveAttribute('title', /^Private/, {
			timeout: 5_000
		});

		// Reload — server-side state must agree.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(toggleBtn()).toHaveAttribute('title', /^Private/, {
			timeout: 10_000
		});

		// Restore.
		await toggleBtn().click();
		await expect(toggleBtn()).toHaveAttribute('title', /^Public/, {
			timeout: 5_000
		});
	});

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

	test('tag add → reload persists → remove restores', async ({ page }) => {
		// Tags live as `routes.tags text[]`. addTag pushes to the
		// array via updateRouteTags; the .tag-add input is a text
		// field that submits on Enter via the wrapping form.
		// removeTag is wired to the per-chip "×" button with
		// aria-label "Remove tag <name>".
		const tag = `e2e-${Date.now().toString().slice(-6)}`;

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await expect(page.locator('.tags-row')).toBeVisible({ timeout: 10_000 });

		// Capture starting tag count so the test is robust to seed
		// drift (the pinned route currently has 0 tags but a future
		// seed change could add some).
		const startCount = await page.locator('.tag-chip').count();

		// Add tag — fill the .tag-add input and submit via Enter
		// (the form submit handler calls addTag).
		const tagInput = page.locator('.tag-add input[type="text"]');
		await tagInput.fill(tag);
		await tagInput.press('Enter');
		await expect(page.locator('.tag-chip', { hasText: tag })).toBeVisible({
			timeout: 5_000
		});
		expect(await page.locator('.tag-chip').count()).toBe(startCount + 1);

		// Reload — server-side state must agree.
		await page.reload();
		await expect(page.locator('.tag-chip', { hasText: tag })).toBeVisible({
			timeout: 10_000
		});

		// Remove via the per-chip × button (aria-label "Remove tag <name>").
		await page.getByRole('button', { name: `Remove tag ${tag}` }).click();
		await expect(page.locator('.tag-chip', { hasText: tag })).toHaveCount(0, {
			timeout: 5_000
		});
		expect(await page.locator('.tag-chip').count()).toBe(startCount);
	});

	test('not-found: visiting a missing route id shows "Route not found" with a way back', async ({
		page
	}) => {
		// Stale link landing protection — same shape as the runs/[id]
		// not-found test. Without this branch the {:else if route}
		// fall-through rendered an empty SplitPane and a blank
		// stats-panel, which looks broken.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/routes/${bogusId}`);
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { level: 1, name: 'Route not found' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: 'Back to your routes' })
		).toBeVisible();
	});
});
