import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/[id] + /dashboard — one lift logged under two spellings is ONE
 * exercise on every surface (decisions § 1248).
 *
 * The grouping key is `normaliseExerciseName` (lib/gym/gym_prs.ts): the named
 * whitespace class collapsed, then the frozen Unicode fold. Five web surfaces
 * derived it with `trim().toLowerCase()` instead, which collapses neither an
 * internal whitespace run nor the code points the table covers. Two of them
 * were a lookup WRITTEN under the PR engine's display spelling and READ back
 * under the block's own, so the second block of a lift spelled two ways lost
 * its PR chips with no failure anywhere.
 *
 * The double space is the witness rather than a case difference on purpose:
 * it is the one collapse both runtimes miss, so the same input exercises the
 * defect on web and on the Dart twin. A single-spaced ASCII pair would pass
 * either way, which is exactly how this survived the existing suite.
 *
 * `blocks` groups on the RAW spelling, so the two spellings render as two
 * exercise blocks — the assertion is that both carry the chip and that the
 * header counts them as one exercise.
 */
test.describe('/gym/[id] — two spellings of one lift', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Housekeeping only: the stamp makes each run's titles unique, so an orphan
	// from an earlier failed run cannot be mistaken for this run's -- but this
	// account is shared with every other gym spec and the rows would otherwise
	// accumulate forever. (`gym-log` opens a fresh editor modal; the in-flight
	// `metadata.gym_session_draft` resume is a separate card on the same page,
	// `gym-session-draft-card`, which these steps never touch.)
	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin.from('gym_workouts').delete().eq('user_id', USER_A.id).like('title', 'E2E%Fold%');
	});

	// The two session titles must not be prefixes of one another. `hasText` is a
	// SUBSTRING match, so while the second was `... pr` and the first `... prior`
	// the post-save wait matched the row session 1 had already put on the page
	// and returned instantly -- the assertion passed without the second workout
	// existing, and the service-role read below then raced the insert and found
	// one row. That is what made this look order-dependent: nothing here waited
	// for the second save at all, so whether it had landed was a matter of how
	// loaded the machine was.
	test('both blocks keep their PR chips and the header counts one exercise', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const single = `E2E Fold ${stamp}`;
		const doubled = `E2E  Fold ${stamp}`;
		const titles = [`${single} sessionA`, `${single} sessionB`];
		const workoutIds: Record<string, string> = {};

		// Session 1 establishes a prior best under the single-spaced spelling.
		await page.goto('/gym');
		await page.getByTestId('gym-log').click();
		await page.getByPlaceholder('e.g. Push day').fill(titles[0]);
		await page.getByPlaceholder('Exercise name').first().fill(single);
		const priorRow = page.locator('.set-row').first();
		await priorRow.locator('input[type="number"]').nth(0).fill('5');
		await priorRow.locator('input[type="number"]').nth(1).fill('100');
		await page.getByRole('button', { name: 'Save workout' }).click();
		await expect(page.locator('.workout-row', { hasText: titles[0] })).toBeVisible({
			timeout: 10_000,
		});

		// Session 2 beats it, logged as two exercises whose names differ only by
		// the internal whitespace run.
		await page.getByTestId('gym-log').click();
		await page.getByPlaceholder('e.g. Push day').fill(titles[1]);
		await page.getByPlaceholder('Exercise name').first().fill(single);
		const firstRow = page.locator('.set-row').first();
		await firstRow.locator('input[type="number"]').nth(0).fill('5');
		await firstRow.locator('input[type="number"]').nth(1).fill('110');
		await page.getByRole('button', { name: 'Add exercise' }).click();
		await page.getByPlaceholder('Exercise name').nth(1).fill(doubled);
		const secondRow = page.locator('.set-row').nth(1);
		await secondRow.locator('input[type="number"]').nth(0).fill('5');
		await secondRow.locator('input[type="number"]').nth(1).fill('120');
		await page.getByRole('button', { name: 'Save workout' }).click();
		await expect(page.locator('.workout-row', { hasText: titles[1] })).toBeVisible({
			timeout: 10_000,
		});

		const { data: created } = await admin
			.from('gym_workouts')
			.select('id, title')
			.eq('user_id', USER_A.id)
			.like('title', `E2E%Fold ${stamp}%`);
		for (const w of created ?? []) workoutIds[w.title as string] = w.id as string;
		expect(Object.keys(workoutIds).length).toBe(2);

		try {
			await page.goto(`/gym/${workoutIds[titles[1]]}`);
			const blocks = page.locator('.exercise-block');
			await expect(blocks).toHaveCount(2, { timeout: 10_000 });

			// The chip on the SECOND block is the regression. Its spelling is not
			// the one the PR engine reports as the display name, so the naive
			// key missed and the chip never rendered.
			await expect(blocks.nth(0).locator('.pr-chip').first()).toBeVisible();
			await expect(blocks.nth(1).locator('.pr-chip').first()).toBeVisible();

			// Two blocks, one exercise: the header stat buckets on the key.
			const exercisesStat = page
				.locator('.summary-stat')
				.filter({ hasText: 'Exercises' })
				.locator('.summary-value');
			await expect(exercisesStat).toHaveText('1');

			// The dashboard's recent-lifts list counts the same workout the same
			// way. The row is a link to the workout, so it can be addressed by
			// href rather than by position in a list this account shares with
			// every other gym spec.
			await page.goto('/dashboard');
			const liftRow = page.locator(`a.run-row[href="/gym/${workoutIds[titles[1]]}"]`);
			await expect(liftRow).toBeVisible({ timeout: 10_000 });
			await expect(liftRow.locator('.run-pace')).toHaveText('1 exercise');
		} finally {
			for (const id of Object.values(workoutIds)) {
				await admin.from('gym_workouts').delete().eq('id', id);
			}
		}
	});
});
