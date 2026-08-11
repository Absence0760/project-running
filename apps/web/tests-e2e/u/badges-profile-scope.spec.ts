import { expect, test } from '@playwright/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * /u/[id]?tab=achievements — the lazily-hydrated badge cache is keyed on the
 * PROFILE it belongs to.
 *
 * `/u/[id]` is one component reused across profiles (the followers list links
 * are same-route client navs), and `loadBadges` early-returned on a bare
 * `badgesLoaded` flag that no navigation reset. So viewing your own
 * achievements and then opening someone else's rendered YOUR badges under
 * THEIR name — and `fetchUserBadges` returns every row for self, including
 * `is_public = false` ones, so private achievements were shown as a stranger's
 * public ones. The `$effect` also failed to track `userId`, because
 * `loadBadges`' early return consumed it before it became a dependency.
 */

test.describe('/u/[id]?tab=achievements — cache is per profile', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('opening another runner refetches instead of reusing your badges', async ({ page }) => {
		const requested: string[] = [];
		await page.route('**/rest/v1/achievements?*', async (route) => {
			const req = route.request();
			if (req.method() !== 'GET') {
				await route.continue();
				return;
			}
			const url = new URL(req.url());
			// `user_id=eq.<uuid>` — record which profile each fetch was for.
			const eq = url.searchParams.get('user_id') ?? '';
			requested.push(eq.replace(/^eq\./, ''));
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify([])
			});
		});

		await page.goto(`/u/${USER_A.id}?tab=achievements`);
		await expect.poll(() => requested.length, { timeout: 10_000 }).toBeGreaterThan(0);
		expect(requested.at(-1)).toBe(USER_A.id);

		// Client-side nav to a different profile, same route + same component.
		await page.goto(`/u/${USER_B.id}?tab=achievements`);

		// The second profile must trigger its OWN fetch. Before the fix the
		// early return kept the first profile's rows and issued no request.
		await expect
			.poll(() => requested.filter((id) => id === USER_B.id).length, { timeout: 10_000 })
			.toBeGreaterThan(0);
	});
});
