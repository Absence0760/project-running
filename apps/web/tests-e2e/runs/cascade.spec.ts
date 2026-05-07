import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	deleteRun,
	insertComment,
	insertKudos,
	insertRun
} from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Backend boundary: deleting a `runs` row cascades to every child
 * table whose FK is `on delete cascade` AND a Storage object lives at
 * `runs/{user_id}/{run_id}.json.gz`. Seven such FKs ship today
 * (run_kudos, run_comments, run_photos, run_segment_efforts,
 * live_run_pings, notifications, run_matched_tracks) — a regression
 * that drops `cascade` on any of them would silently leak rows.
 *
 * pgtap pins the SQL-level rule, but we want a smoke-test that the
 * UI delete (deleteRun in data.ts → goto('/runs')) actually fires the
 * cascade against a row that has children. This plants a run with
 * kudos + comment, drives the trash-icon delete from /runs/[id],
 * then asserts via service-role that ZERO child rows remain. Also
 * verifies the auto-generated kudos / comment notifications for the
 * RUN OWNER got swept (notification trigger fires INSERT, then run
 * delete cascades).
 *
 * Why an e2e test instead of pure pgtap: the UI exercises the
 * deleteRun() path that combines a Storage object remove with the
 * row delete. A backend regression that breaks Storage cleanup but
 * leaves the row delete intact would NOT fail pgtap (which doesn't
 * touch Storage). Belt + braces.
 */

test.describe('/runs/[id] — delete cascades through every child table', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('plant kudos + comment + notifications → delete via UI → all child rows gone', async ({
		page
	}) => {
		const admin = getAdminClient();

		// ── Setup: plant a run, then engagement ──
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 6_000,
			duration_s: 1_800,
			is_public: true,
			// Add a track so the Storage object is on disk to be swept.
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-01T08:00:00Z' },
				{ lat: -33.89, lng: 151.28, ele: 11, t: '2026-04-01T08:01:00Z' }
			]
		});
		await insertKudos(runId, USER_B.id);
		await insertComment({
			run_id: runId,
			author_id: USER_B.id,
			body: 'e2e-cascade — strong session!'
		});

		// Sanity: the trigger fan-out planted notifications for runner
		// (the run's owner). 1 kudos + 1 comment = 2 unread notifications
		// referencing this run_id.
		const { count: notifBefore } = await admin
			.from('notifications')
			.select('id', { count: 'exact', head: true })
			.eq('run_id', runId);
		expect(notifBefore).toBe(2);

		// ── UI delete ──
		await page.goto(`/runs/${runId}`);
		await page.waitForLoadState('networkidle');
		await page.locator('button[title="Delete"]').click();
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
		await page.waitForURL(/\/runs$/, { timeout: 10_000 });

		// ── Cascade verification ──
		// The seven cascading children:
		//   run_kudos, run_comments, run_photos, run_segment_efforts,
		//   live_run_pings, notifications, run_matched_tracks
		// Plus the row itself + its Storage object.
		const tables = [
			'run_kudos',
			'run_comments',
			'run_photos',
			'segment_efforts',
			'live_run_pings',
			'run_matched_tracks'
		] as const;
		for (const t of tables) {
			const { count } = await admin
				.from(t)
				.select('run_id', { count: 'exact', head: true })
				.eq('run_id', runId);
			expect(count, `${t} should have 0 rows for the deleted run`).toBe(0);
		}

		// notifications.run_id is on delete cascade too.
		const { count: notifAfter } = await admin
			.from('notifications')
			.select('id', { count: 'exact', head: true })
			.eq('run_id', runId);
		expect(notifAfter).toBe(0);

		// The runs row itself is gone.
		const { data: stillThere } = await admin
			.from('runs')
			.select('id')
			.eq('id', runId)
			.maybeSingle();
		expect(stillThere).toBeNull();

		// Storage object swept by deleteRun()'s pre-delete remove.
		const { data: list } = await admin.storage
			.from('runs')
			.list(USER_A.id, { search: runId });
		expect(list?.find((f) => f.name.startsWith(runId))).toBeUndefined();
	});
});
