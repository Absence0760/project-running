import { expect, test } from '@playwright/test';

import { deleteRoute, insertRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes — the name search folds, and the A–Z sort is a folded order rather
 * than a collation ([§ 1337](../../../../docs/architecture/decisions.md)).
 *
 * The mobile half of § 1337 is pinned by three widget tests in
 * `routes_screen_test.dart`; the web half had none, because `/routes` is a
 * `.svelte` page and the web unit suite runs under `tsx --test`, which cannot
 * compile one (§ 1278). `compareFoldedNames` and `fold` have their own unit
 * tests, and those prove the comparator is right — not that the page calls it.
 * That is the whole gap: the pre-§ 1337 page called `toLowerCase` and
 * `localeCompare`, both of which are also "right", and no test on this side
 * could tell the two pages apart.
 *
 * **The sort case is NOT the one the followup proposed, and the difference is
 * the point.** It asked for `Åre` before `Zaragoza`, which does not
 * discriminate: a collation files `Å` beside `A`, so `localeCompare` puts Åre
 * first too and the assertion passes against the page it was meant to fail
 * against. The pair that actually separates the two orderings is `Ørsted`
 * against `Zaragoza` — `Ø` has no canonical decomposition, so the fold leaves
 * U+00F8 and a code-unit compare files it AFTER `z`, while a collation files
 * it beside `O` and puts it BEFORE. Measured in Node's ICU under the `en-GB`
 * locale this suite pins: `localeCompare` gives Åre, İstanbul, Ørsted,
 * Zaragoza; the folded order gives Åre, İstanbul, Zaragoza, Ørsted. So Åre
 * stays in the assertion as the seed § 1337's own worked example uses, and
 * the load-bearing half is the tail.
 *
 * That the folded order is not what a Norwegian reader calls alphabetical is
 * § 1337's stated residual, not a defect this spec is papering over: one
 * order everywhere beats a per-host order the phone cannot reproduce.
 *
 * The rows are scoped by a stamped token so the assertions are about this
 * run's four routes and not about however many the shared account holds.
 */
test.describe('/routes — name fold + A–Z order', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const NAMES = ['Zaragoza Loop', 'Åre Trail', 'Ørsted Way', 'İstanbul Loop'];
	let tag = '';
	let routeIds: string[] = [];

	test.beforeEach(async () => {
		tag = `zzq${Date.now()}`;
		routeIds = [];
		for (const name of NAMES) {
			routeIds.push(
				await insertRoute({
					user_id: USER_A.id,
					name: `${name} ${tag}`,
					waypoints: [
						{ lat: 51.5, lng: -0.12 },
						{ lat: 51.51, lng: -0.12 },
					],
					distance_m: 5_000,
				}),
			);
		}
	});

	test.afterEach(async () => {
		for (const id of routeIds) await deleteRoute(id);
		routeIds = [];
	});

	test('typing `istanbul` finds a route named with U+0130', async ({ page }) => {
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({ timeout: 15_000 });

		// `'İstanbul Loop'.toLowerCase()` is `i̇stanbul loop` in a browser — an
		// `i` plus a combining dot — which does NOT contain `istanbul`. The
		// fold strips the mark, so it does. Measured: the same string reaches
		// the row on the phone, which is the reversal § 1337 closed.
		// The query is a bare `istanbul` and not `istanbul <tag>`: the filter is
		// a SUBSTRING test over the whole folded name, and the tag sits after
		// `Loop`, so the two together match nothing on any version of the page.
		await page.getByLabel('Search routes').fill('istanbul');
		await expect(
			page.getByRole('heading', { name: `İstanbul Loop ${tag}`, exact: true }),
		).toBeVisible();
		// ...and the list really is filtered, so the row above is a match and
		// not a search that quietly stopped narrowing.
		await expect(
			page.getByRole('heading', { name: `Zaragoza Loop ${tag}`, exact: true }),
		).toHaveCount(0);

		// The control: all four seeded rows are reachable by the tag alone, so
		// the narrowing above is the fold and not a missing row.
		await page.getByLabel('Search routes').fill(tag);
		await expect(page.locator('.route-card')).toHaveCount(NAMES.length);
	});

	test('A–Z orders on the folded key, so Zaragoza precedes Ørsted', async ({ page }) => {
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({ timeout: 15_000 });

		await page.getByLabel('Search routes').fill(tag);
		await expect(page.locator('.route-card')).toHaveCount(NAMES.length);

		await page.getByLabel('Sort').selectOption('az');
		await expect
			.poll(() => page.locator('.route-card h3').allTextContents(), { timeout: 10_000 })
			.toEqual([
				`Åre Trail ${tag}`,
				`İstanbul Loop ${tag}`,
				`Zaragoza Loop ${tag}`,
				`Ørsted Way ${tag}`,
			]);
	});
});
