import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Workout structured-interval edit (web).
 *
 * The audit found that `plans/workout-detail.spec.ts` +
 * `plans/workout-runner-surfaces.spec.ts` pin the read-side of a
 * structured workout (warmup + repeats + steady + cooldown rows) and
 * the unlink confirm dialog, but no test exercises the WRITE side —
 * creating or editing the interval structure (warmup distance, rep
 * count, recovery distance, pace target).
 *
 * Current state of the WorkoutEditor (apps/web/src/lib/components/
 * WorkoutEditor.svelte): the modal exposes kind / distance / pace /
 * tolerance / zone / notes fields, but NO UI to add or remove an
 * interval, change the rep count, set the recovery distance, or
 * tweak the rep pace target. The structure column is only ever
 * cleared (kind→rest, kind→easy/long/recovery sets `structure: null`)
 * or left untouched (`structure: undefined`).
 *
 * Until a structure-editor UI lands, this saga can't pass — there's
 * nothing for the test to drive. Tracked here as a single `test.skip`
 * with the canonical TODO so the gap stays visible.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('Workout structured-interval edit (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.skip(
		'edit interval structure (warmup + reps + recovery) and persist',
		async () => {
			// TODO: wire a structure editor into WorkoutEditor (or onto
			// the /plans/[id]/workouts/[wid] detail page) before this
			// can be unskipped. Today the only `structure` mutations
			// from a client are:
			//   - `structure: null` (when kind transitions to an
			//     unstructured kind), and
			//   - `structure: undefined` (no-op).
			// Neither path covers add/remove an interval, change a
			// rep count, or tweak a pace target. Pinning the read
			// side already lives in plans/workout-runner-surfaces.spec
			// .ts ("Interval workout renders warmup + repeats +
			// cooldown") so the rendering invariant is safe; the
			// missing leg is the writable round-trip.
		}
	);

	test('structure column is cleared when kind transitions to an unstructured kind', async ({
		page
	}) => {
		// The one write-side structure behaviour that IS wired: when
		// the user flips kind to easy / long / recovery / rest, the
		// editor sends `structure: null` so an old structured payload
		// doesn't outlive its kind. Pin that contract end-to-end so
		// a regression that left a stale structure on an "easy" row
		// (which would then render a Structure card on the read page)
		// surfaces here.
		const admin = getAdminClient();
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id, week_index')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		const { data: wo } = await admin
			.from('plan_workouts')
			.select('id, kind, structure, target_distance_m, scheduled_date')
			.in('week_id', weekIds)
			.eq('scheduled_date', '2026-04-14')
			.maybeSingle();
		expect(wo).not.toBeNull();
		const workoutId = (wo as { id: string }).id;
		const beforeKind = (wo as { kind: string }).kind;
		const beforeStructure = (wo as { structure: unknown }).structure;
		const beforeDistance = (wo as { target_distance_m: number | null }).target_distance_m;
		expect(beforeKind).toBe('interval');
		expect(beforeStructure).not.toBeNull();

		try {
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const intervalDay = page
				.locator('.weeks .week .day:not(.completed) .day-link', {
					hasText: /Interval/
				})
				.first();
			await expect(intervalDay).toBeVisible({ timeout: 10_000 });
			await intervalDay.click();

			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.locator('select').first().selectOption('easy');
			await modal.getByRole('button', { name: /^Save/ }).click();
			await expect(modal).toHaveCount(0);

			const { data: after } = await admin
				.from('plan_workouts')
				.select('kind, structure')
				.eq('id', workoutId)
				.maybeSingle();
			expect((after as { kind: string }).kind).toBe('easy');
			expect((after as { structure: unknown }).structure).toBeNull();
		} finally {
			await admin
				.from('plan_workouts')
				.update({
					kind: beforeKind,
					structure: beforeStructure,
					target_distance_m: beforeDistance
				})
				.eq('id', workoutId);
		}
	});
});
