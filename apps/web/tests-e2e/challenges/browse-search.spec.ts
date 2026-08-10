import { expect, test } from '@playwright/test';

import { USER_B } from '../fixtures/users';

/**
 * /challenges (Browse) — the two things `loadMine` already got right and the
 * Browse half did not.
 *
 * 1. A newer search must SUPERSEDE an in-flight one. `loadBrowse` opened with
 *    `if (browseLoading) return;`, so typing while a request was on the wire
 *    discarded the new term outright — the debounce is fire-and-forget, so
 *    nothing retried it. The list kept the previous term's rows and
 *    `activeSearch` kept the previous term, which meant Load more went on
 *    paging a query the search box no longer showed.
 *
 * 2. A failed browse must not render as "No public challenges to join right
 *    now." That is a different fact, and the sibling loader in the same file
 *    has surfaced it as an error + retry since issue #357.
 */

const RPC = '**/rest/v1/rpc/browse_public_challenges*';

function row(title: string) {
	return {
		id: `00000000-0000-4000-8000-${title.padEnd(12, '0').slice(0, 12)}`,
		creator_id: USER_B.id,
		club_id: null,
		title,
		description: null,
		metric: 'distance',
		scope: 'individual',
		activity_type: null,
		goal_value: 100000,
		starts_at: '2026-01-01T00:00:00Z',
		ends_at: '2030-01-01T00:00:00Z',
		is_public: true,
		created_at: '2026-01-01T00:00:00Z',
		participant_count: 3
	};
}

test.describe('/challenges — Browse search', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a search typed over an in-flight one still lands', async ({ page }) => {
		await page.route(RPC, async (route) => {
			const body = JSON.parse(route.request().postData() ?? '{}');
			const term: string | null = body.p_search ?? null;
			// The first term's response is held open; the second must not be
			// refused by it, and must not be overwritten when it lands.
			if (term === 'alpha') {
				await new Promise((r) => setTimeout(r, 2500));
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([row('alpha-hit')])
				});
				return;
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify(term === 'alphabet' ? [row('alphabet-hit')] : [])
			});
		});

		await page.goto('/challenges');
		const search = page.getByRole('searchbox', { name: 'Search challenges' });
		await expect(search).toBeVisible({ timeout: 15_000 });

		await search.fill('alpha');
		// Let the debounce fire and the slow request get on the wire.
		await page.waitForTimeout(700);
		await search.fill('alphabet');

		await expect(page.getByText('alphabet-hit')).toBeVisible({ timeout: 15_000 });

		// The stale response resolves after ours; it must not win.
		await page.waitForTimeout(2500);
		await expect(page.getByText('alphabet-hit')).toBeVisible();
		await expect(page.getByText('alpha-hit')).toHaveCount(0);
	});

	test('a failed browse shows an error + retry, not the empty state', async ({ page }) => {
		let failNext = true;
		await page.route(RPC, async (route) => {
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated browse failure' })
				});
				return;
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify([row('recovered')])
			});
		});

		await page.goto('/challenges');

		const banner = page
			.getByRole('alert')
			.filter({ hasText: "Couldn't load challenges." })
			.filter({ hasText: 'simulated browse failure' });
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(page.getByText('No public challenges to join right now.')).toHaveCount(0);

		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByText('recovered')).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveCount(0);
	});
});
