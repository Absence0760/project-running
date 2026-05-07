import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /runs/new — standalone manual run wrapper.
 *
 * The same RunEditor is mounted in a modal from /runs (covered by
 * runs/list.spec.ts). This standalone surface is the deep-linkable
 * version — kept as a thin page wrapper so /runs/new opens cleanly
 * from a back-button history or an external link. Pin the create
 * flow lands on /runs/[new-id].
 */

test.describe('/runs/new', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('manual run create from the standalone page → land on /runs/[new] with the right user_id + activity', async ({
		page
	}) => {
		// RunEditor has no title field — just started_at / activity /
		// distance / duration / route / notes. The mounting page is
		// the standalone /runs/new wrapper. Pin the create round-trip
		// hits the canonical onCreated → goto(`/runs/<id>`) path with
		// a deterministic distance value verifiable against the row.
		const admin = getAdminClient();
		let plantedId: string | null = null;

		try {
			await page.goto('/runs/new');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Add a run' })
			).toBeVisible({ timeout: 10_000 });

			// Pick Walk so the row is distinguishable from the seed runs
			// even before we read user_id.
			await page.getByRole('button', { name: 'Walk', exact: true }).click();

			// Distance + Duration min are required; defaults won't
			// satisfy the form. Distance input is the first number
			// field, duration min is the second, sec is the third.
			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill('3.14');
			await numberInputs.nth(1).fill('25');

			await page.getByRole('button', { name: /Save/ }).click();

			// onCreated → goto(`/runs/${run.id}`).
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
			plantedId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

			// Backend assertion: the row exists, user_id is runner's,
			// activity_type=walk lives in metadata, distance is 3140 m.
			const { data: row } = await admin
				.from('runs')
				.select('user_id, distance_m, metadata')
				.eq('id', plantedId)
				.single();
			expect(row?.user_id).toBe(USER_A.id);
			expect(Math.round((row?.distance_m as number) ?? 0)).toBe(3140);
			expect((row?.metadata as Record<string, unknown>)?.activity_type)
				.toBe('walk');
		} finally {
			if (plantedId) {
				await admin.from('runs').delete().eq('id', plantedId);
			}
		}
	});
});
