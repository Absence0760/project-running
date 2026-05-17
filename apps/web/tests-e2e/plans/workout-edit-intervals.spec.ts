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

	test('edit interval structure (warmup + reps + recovery) and persist', async ({
		page
	}) => {
		// 2026-04-14 is the seeded interval: 1.5 km warmup + 5×1000m @
		// 4:00 with 400 m jog recovery + 1.5 km cooldown. Drive the
		// WorkoutEditor's structure block: bump warmup to 2 km, count
		// to 6, recovery to 500 m, rep pace to 4:10. Save → re-read
		// the DB row and assert each field round-tripped.
		const admin = getAdminClient();
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		const { data: wo } = await admin
			.from('plan_workouts')
			.select('id, structure')
			.in('week_id', weekIds)
			.eq('scheduled_date', '2026-04-14')
			.maybeSingle();
		expect(wo).not.toBeNull();
		const workoutId = (wo as { id: string }).id;
		const beforeStructure = (wo as { structure: unknown }).structure;

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

			const structure = modal.locator('fieldset.structure');
			await expect(structure).toBeVisible();

			await structure.locator('label.warmup input').fill('2');
			await structure.locator('label.cooldown input').fill('2');

			const repeats = structure.locator('fieldset.repeats');
			await expect(repeats).toBeVisible();
			const repeatInputs = repeats.locator('> label input[type="number"]');
			await repeatInputs.nth(0).fill('6');
			await repeatInputs.nth(1).fill('1');
			const pace = repeats.locator('fieldset .pace-row input');
			await pace.nth(0).fill('4');
			await pace.nth(1).fill('10');
			await repeats.locator('label.recovery input').fill('0.5');

			await modal.getByRole('button', { name: /^Save/ }).click();
			await expect(modal).toHaveCount(0);

			const { data: after } = await admin
				.from('plan_workouts')
				.select('structure')
				.eq('id', workoutId)
				.maybeSingle();
			const next = (after as { structure: Record<string, unknown> }).structure;
			expect(next).not.toBeNull();
			const warmup = next.warmup as { distance_m: number };
			const repeatsRow = next.repeats as {
				count: number;
				distance_m: number;
				pace_sec_per_km: number;
				recovery_distance_m: number;
				recovery_pace: string;
			};
			const cooldown = next.cooldown as { distance_m: number };
			expect(warmup.distance_m).toBe(2000);
			expect(cooldown.distance_m).toBe(2000);
			expect(repeatsRow.count).toBe(6);
			expect(repeatsRow.distance_m).toBe(1000);
			expect(repeatsRow.pace_sec_per_km).toBe(250);
			expect(repeatsRow.recovery_distance_m).toBe(500);
			expect(repeatsRow.recovery_pace).toBe('jog');

			// Reload + re-open: editor reflects the persisted values.
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const reopened = page
				.locator('.weeks .week .day:not(.completed) .day-link', {
					hasText: /Interval/
				})
				.first();
			await reopened.click();
			const modal2 = page.locator('.modal');
			await expect(modal2).toBeVisible({ timeout: 5_000 });
			const structure2 = modal2.locator('fieldset.structure');
			await expect(structure2.locator('label.warmup input')).toHaveValue('2');
			const repeats2 = structure2.locator('fieldset.repeats');
			await expect(repeats2.locator('> label input[type="number"]').nth(0))
				.toHaveValue('6');
			await expect(repeats2.locator('label.recovery input')).toHaveValue('0.5');
		} finally {
			await admin
				.from('plan_workouts')
				.update({ structure: beforeStructure })
				.eq('id', workoutId);
		}
	});

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
