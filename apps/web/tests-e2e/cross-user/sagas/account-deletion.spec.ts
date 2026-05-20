import { expect, test } from '@playwright/test';

import { getAdminClient } from '../../fixtures/local-supabase';
import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser
} from '../../fixtures/saga-users';
import { insertRun } from '../../fixtures/simulate';

/**
 * Account deletion saga — full /settings/account UI round-trip
 * verifying the privacy-deletion contract end-to-end.
 *
 * The `delete-account` Edge Function does (a) recursive Storage drain
 * across the `runs` + `run-photos` buckets keyed on the user's id,
 * then (b) `auth.admin.deleteUser(user.id)` which fires every
 * `ON DELETE CASCADE` FK back to `auth.users` (runs, routes,
 * user_profiles, user_settings, run_kudos, run_comments,
 * user_follows, notifications, …). A regression in either layer is
 * a privacy-deletion silent failure — the user can't observe the
 * orphaned data and can't retry (their auth row is already gone).
 *
 * This test exercises the full path:
 *   1. Mint an ephemeral saga user.
 *   2. Plant a run (with gzipped track in the `runs` Storage bucket
 *      via insertRun) so there's both a row AND a Storage object to
 *      reap.
 *   3. Drive /settings/account → click "Delete Account" → confirm
 *      the modal → wait for the goto('/login') redirect.
 *   4. Assert the user is gone via service-role queries:
 *      - auth.users row absent
 *      - user_profiles row absent
 *      - runs row absent
 *      - Storage object at `{user.id}/{run.id}.json.gz` absent
 *
 * Why a saga and not the runner@test.com fixture: deleting runner
 * would scorch every other test in the suite. Ephemeral users are
 * the only safe path for a destructive end-to-end test like this,
 * and they double as the realistic scenario (a user actually clicking
 * "delete my account" only does it to their own account).
 *
 * Failure modes this catches:
 *  - The recursive `deletePrefix` walk regressing to a flat
 *    `list().remove()` and leaking blobs at `{user.id}/exports/...`
 *    (the audit/storage Pass-3 bug).
 *  - A future cascading-FK addition that DOESN'T list `on delete
 *    cascade` orphaning rows after auth.users delete.
 *  - The EF returning 200 OK but skipping one of the two buckets.
 *  - Auth-side regression (rate-limit RPC failing closed without
 *    surfacing) silently breaking the destructive path.
 */

test.describe('saga: account deletion via /settings/account', () => {
	test.describe.configure({ timeout: 90_000 });

	let user: SagaUser;
	let plantedRunId: string | null = null;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, {
			displayNames: ['Saga Self-Delete']
		});
	});

	test.afterAll(async () => {
		// If the test passed, the user is already gone — deleteSagaUsers
		// is a no-op (and tolerates a missing row). If the test failed
		// part-way, this still cleans up.
		await deleteSagaUsers([user]);
	});

	test('owner deletes their own account → all rows + Storage objects gone', async ({
		browser
	}) => {
		// 1) Plant a run so there's row + storage state to delete.
		plantedRunId = await insertRun({
			user_id: user.id,
			started_at: new Date('2026-04-30T10:00:00Z').toISOString(),
			distance_m: 4_500,
			duration_s: 1_500,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-30T10:00:00Z' },
				{ lat: -33.89, lng: 151.28, ele: 11, t: '2026-04-30T10:00:30Z' }
			]
		});

		// Confirm the planted state via service-role BEFORE the delete —
		// so a delete-failure assertion is "I had X, now I don't" not
		// "did X ever exist?".
		const admin = getAdminClient();

		const before = await admin
			.from('runs')
			.select('id')
			.eq('id', plantedRunId)
			.maybeSingle();
		expect(before.data?.id).toBe(plantedRunId);

		const beforeList = await admin.storage
			.from('runs')
			.list(user.id, { search: plantedRunId });
		expect(beforeList.data?.find((f) => f.name.startsWith(plantedRunId)))
			.toBeDefined();

		// 2) Drive the UI flow.
		const ctx = await browser.newContext({
			storageState: user.storageStatePath
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/account');

			// "Delete Account" sits at the bottom of the Danger Zone card.
			// Wait for the danger zone to be reachable — saga users hit the
			// auth-race poll on first paint, so the button isn't always
			// immediate.
			const deleteBtn = page.getByRole('button', { name: 'Delete Account' });
			await expect(deleteBtn).toBeVisible({ timeout: 10_000 });
			await deleteBtn.click();

			// ConfirmDialog opens. Listen for the EF response BEFORE the
			// click so we don't miss it (the redirect chain on success is
			// fast enough to outrace a post-hoc waitForResponse).
			const efPromise = page.waitForResponse(
				(r) =>
					r.url().includes('/functions/v1/delete-account') &&
					r.request().method() === 'POST',
				{ timeout: 10_000 }
			);
			await expect(
				page.getByRole('heading', { name: /Delete your account\?/ })
			).toBeVisible({ timeout: 5_000 });
			await page
				.getByRole('button', { name: /Delete my account/ })
				.click();

			const ef = await efPromise;
			expect(
				ef.status(),
				`delete-account EF must return 200 (got ${ef.status()}: ${await ef.text()})`
			).toBe(200);

			await page.waitForURL(/\/login/, { timeout: 15_000 });
		} finally {
			await ctx.close();
		}

		// 3) Verify the deletion landed everywhere.
		const after = await admin
			.from('runs')
			.select('id')
			.eq('id', plantedRunId)
			.maybeSingle();
		expect(after.data, 'runs row must cascade away on auth.users delete')
			.toBeNull();

		const profileAfter = await admin
			.from('user_profiles')
			.select('id')
			.eq('id', user.id)
			.maybeSingle();
		expect(
			profileAfter.data,
			'user_profiles row must cascade away'
		).toBeNull();

		const { data: authUser } = await admin.auth.admin.getUserById(user.id);
		expect(authUser?.user, 'auth.users row must be gone').toBeNull();

		const afterList = await admin.storage
			.from('runs')
			.list(user.id, { search: plantedRunId });
		const orphan = afterList.data?.find((f) =>
			f.name.startsWith(plantedRunId)
		);
		expect(
			orphan,
			'gzipped track must be drained from the runs Storage bucket — ' +
				'a privacy-deletion silent failure if blobs survive after the auth row is gone'
		).toBeUndefined();

		// Mark plantedRunId as cleaned so the afterAll doesn't re-attempt.
		plantedRunId = null;
	});
});
