import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym — the exercise-catalogue picker's three states, in a browser.
 *
 * [§ 1333](../../../../docs/architecture/decisions.md) moved the picker's
 * decision into `lib/components/exercise_catalogue_picker.ts` and pinned it
 * with 13 mutation-tested cases. Those hold the DECISION; none of them can
 * hold the RENDERING, and § 1278 recorded why: `apps/web` runs its unit suite
 * under `tsx --test`, which cannot compile a `.svelte` component. So nothing
 * proved that `view.matches` reaches the DOM as a result list, that
 * `view.hiddenExact` reaches it as a sentence under
 * `data-testid=catalogue-other-category`, or that the create button is absent
 * beside that sentence rather than merely absent from the module's answer.
 *
 * Two states, two tests, because they fail for different reasons:
 *
 * 1. The FOLD. Both sides of the name comparison go through
 *    `normaliseExerciseName`, so an entry stored with a non-breaking space is
 *    reachable by typing an ordinary one. The predecessor filter was
 *    `e.name.toLowerCase().includes(query.toLowerCase())`, under which
 *    `'e2e fold …'.includes('e2e fold …')` is false and the entry could
 *    not be found at all (§ 1276). The doubled-space query is the mirror: the
 *    QUERY is folded too, so `bench  press` reaches the seeded `Bench Press`.
 *    One case per side of the comparison — folding only the query, or only
 *    the entry, passes one and fails the other.
 *
 * 2. The HIDDEN EXACT. The exact-match test that suppresses the create button
 *    scans the WHOLE catalogue while the result list also applies the category
 *    filter, so a chest exercise named exactly while `legs` is selected leaves
 *    an empty list beside no create button. § 1332 added the third state so
 *    the page says which category the entry is filed under instead of
 *    rendering "No exercises match." — the assertion is that the sentence is
 *    present AND that `catalogue-create` is still absent, because the pair is
 *    the claim: an explanation with a create button beside it would invite a
 *    duplicate-key write, and a create button with no explanation is § 1276's
 *    dead end returning.
 *
 * The seeded row is inserted service-role rather than created through the
 * picker's own create button: the subject is the READ path, and driving the
 * write path to set it up would make a create-path regression read as a
 * search regression. `name_key` is deliberately not supplied —
 * `exercises_stamp_name_key` (migration 20270711000001) derives it, so the
 * fixture cannot disagree with the server's own fold.
 */

/** U+00A0 between the two words — the whitespace an ordinary space must reach. */
const NBSP = ' ';

test.describe('/gym — exercise catalogue picker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let customId = '';
	let customName = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// Stamped so a row orphaned by an earlier failed run cannot be mistaken
		// for this one's, and so the search query below can only match it.
		const stamp = Date.now();
		customName = `E2E${NBSP}Foldpick ${stamp}`;
		const { data, error } = await admin
			.from('exercises')
			.insert({ author_id: USER_A.id, name: customName, category: 'chest' })
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed exercise failed: ${error?.message ?? 'no row'}`);
		customId = (data as { id: string }).id;
	});

	test.afterEach(async () => {
		if (!customId) return;
		await getAdminClient().from('exercises').delete().eq('id', customId);
		customId = '';
	});

	/** Open the composer and the picker against its first exercise block. */
	async function openPicker(page: import('@playwright/test').Page) {
		await page.goto('/gym');
		await page.getByTestId('gym-log').click();
		// `catalogue-browse` only renders once the catalogue read has landed,
		// so this click IS the wait for it — a picker opened before then would
		// be filtering an empty list.
		await page.getByTestId('catalogue-browse').first().click();
		await expect(page.getByTestId('exercise-catalogue-picker')).toBeVisible({
			timeout: 10_000,
		});
	}

	test('a name stored with a non-breaking space is found by typing an ordinary one', async ({
		page,
	}) => {
		await openPicker(page);

		// Entry side: the stored name's NBSP folds, so the ordinary space the
		// reader types reaches it.
		await page.getByTestId('catalogue-search').fill(customName.replace(NBSP, ' '));
		const results = page.getByTestId('catalogue-results').getByTestId('catalogue-pick');
		await expect(results).toHaveCount(1);
		await expect(results.first()).toContainText('Foldpick');

		// The entry exists, so the create button must be absent — a second row
		// under the same folded key is the duplicate write § 1333 names.
		await expect(page.getByTestId('catalogue-create')).toHaveCount(0);

		// Query side: the seeded globals carry single spaces, and a doubled one
		// in the query collapses onto exactly the same set. Asserting the two
		// result LISTS are equal rather than naming a row keeps the claim off
		// however many seeded names happen to contain the phrase.
		await page.getByTestId('catalogue-search').fill('bench press');
		const names = page.getByTestId('catalogue-results').locator('.name');
		await expect(names.filter({ hasText: /^Bench Press$/ })).toHaveCount(1);
		const single = await names.allTextContents();

		await page.getByTestId('catalogue-search').fill('bench  press');
		await expect.poll(() => names.allTextContents(), { timeout: 10_000 }).toEqual(single);
	});

	test('a name the category filter hides is explained, and no create button appears beside it', async ({
		page,
	}) => {
		await openPicker(page);

		// The seeded row is filed under `chest`; ask for `legs`.
		await page.getByTestId('catalogue-category').selectOption('legs');
		await page.getByTestId('catalogue-search').fill(customName.replace(NBSP, ' '));

		// Nothing to list, because nothing under `legs` names it...
		await expect(page.getByTestId('catalogue-results')).toHaveCount(0);
		// ...and the page says why, naming the category it IS filed under.
		const explained = page.getByTestId('catalogue-other-category');
		await expect(explained).toBeVisible();
		await expect(explained).toContainText('Chest');
		// The pair is the claim: an explanation AND no create affordance.
		await expect(page.getByTestId('catalogue-create')).toHaveCount(0);

		// The control. Under `all` the same query lists the entry, so the
		// empty list above is the category filter and not a broken search.
		await page.getByTestId('catalogue-category').selectOption('all');
		await expect(
			page.getByTestId('catalogue-results').getByTestId('catalogue-pick'),
		).toHaveCount(1);
		await expect(page.getByTestId('catalogue-other-category')).toHaveCount(0);

		// And a name the catalogue does NOT hold offers the create button under
		// the same category filter — so the absence asserted above is the exact
		// match, not a create affordance that never renders.
		await page.getByTestId('catalogue-category').selectOption('legs');
		await page.getByTestId('catalogue-search').fill(`${customName.replace(NBSP, ' ')} nonesuch`);
		await expect(page.getByTestId('catalogue-create')).toBeVisible();
		await expect(page.getByTestId('catalogue-other-category')).toHaveCount(0);
	});
});
