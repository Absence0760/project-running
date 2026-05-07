import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * `runs.external_id` UNIQUE-constraint resilience under concurrent
 * insert. This is the import-pipeline equivalent of the
 * `kudos-concurrency.spec.ts` test for run_kudos.
 *
 * Same activity surfacing through two paths simultaneously is a
 * realistic scenario:
 *   1. User clicks "Sync Strava" while a webhook for that same
 *      activity is in flight from `strava-webhook`.
 *   2. Two browser tabs both press "Sync" within the same second.
 *   3. A retry on a flaky network races itself.
 *   4. parkrun's bulk import fans out one user's events twice.
 *
 * The DB defence is `runs_external_id_key` — a UNIQUE constraint on
 * `external_id` (since 20260405_001_initial_schema.sql) plus the
 * partial unique index `runs_external_id` on
 * `external_id WHERE external_id IS NOT NULL`. One INSERT wins; the
 * losers raise 23505 (`unique_violation`).
 *
 * The application defence: every import path is supposed to swallow
 * 23505 as a no-op (the activity already exists, semantically a
 * success). The strava-import EF reads existing strava_ids into a
 * Set before fetching; strava-webhook's `ingestActivity` catches and
 * counts the dupe; the parkrun importer skips on conflict. A
 * regression that surfaced 23505 as a fatal error to the caller
 * would crash a sync mid-page.
 *
 * What this test pins:
 *   - Five simultaneous inserts with the same `external_id`
 *     produce exactly one row.
 *   - Every loser surfaces 23505, not a different error code (a
 *     different code would suggest the constraint is missing /
 *     mis-shaped and a different layer raised the error first).
 *
 * What this DOESN'T cover:
 *   - The strava-import / strava-webhook handlers themselves.
 *     They're Deno code reachable only via `supabase functions
 *     serve`, not from the SvelteKit dev server. The contract pinned
 *     here (DB-level dedupe) is what those handlers depend on.
 */

const PARALLEL = 5;

test.describe('runs.external_id — concurrent insert resilience', () => {
	test('5 parallel inserts with the same external_id land exactly 1 row', async () => {
		const admin = getAdminClient();
		// A unique-per-test external id so reruns don't collide with a
		// leftover row.
		const externalId = `e2e-strava-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const startedAt = new Date('2026-04-30T11:00:00Z').toISOString();

		const insertOne = () =>
			admin
				.from('runs')
				.insert({
					user_id: USER_A.id,
					started_at: startedAt,
					duration_s: 1500,
					distance_m: 5000,
					source: 'strava',
					external_id: externalId,
					is_public: false,
					metadata: { activity_type: 'run', strava_id: externalId }
				})
				.select('id')
				.single();

		const results = await Promise.allSettled(
			Array.from({ length: PARALLEL }, insertOne)
		);

		try {
			let winners = 0;
			let dupeFailures = 0;
			let otherFailures: { code?: string; msg?: string }[] = [];
			for (const r of results) {
				if (r.status === 'rejected') {
					throw new Error(
						`unexpected rejection (the supabase-js client should fulfil with error data): ${r.reason}`
					);
				}
				const { data, error } = r.value;
				if (data && !error) {
					winners++;
				} else if (error) {
					if (error.code === '23505') dupeFailures++;
					else otherFailures.push({ code: error.code, msg: error.message });
				}
			}

			expect(
				winners,
				'exactly one INSERT must win — anything else means the UNIQUE constraint regressed'
			).toBe(1);
			expect(
				dupeFailures,
				'every non-winner must raise 23505; a different code would suggest the constraint shape changed'
			).toBe(PARALLEL - 1);
			expect(
				otherFailures,
				`no non-23505 errors expected; got: ${JSON.stringify(otherFailures)}`
			).toEqual([]);

			// Service-role count: exactly one row landed.
			const { count } = await admin
				.from('runs')
				.select('*', { count: 'exact', head: true })
				.eq('external_id', externalId);
			expect(count, 'exactly one runs row must persist').toBe(1);
		} finally {
			// Cleanup the surviving row.
			await admin.from('runs').delete().eq('external_id', externalId);
		}
	});

	test('an INSERT with the same external_id from a previous run gets a clean 23505', async () => {
		// Different shape from the concurrent test: a second sync after
		// the first one already wrote the row. This is the steady-state
		// dedupe path that strava-import's pre-fetch Set is supposed to
		// short-circuit, but if the Set goes stale (e.g. cache TTL,
		// pagination across pages where some are already imported), the
		// DB constraint is the backstop. Pin that backstop.
		const admin = getAdminClient();
		const externalId = `e2e-replay-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const baseRow = {
			user_id: USER_A.id,
			started_at: new Date('2026-04-29T08:00:00Z').toISOString(),
			duration_s: 1800,
			distance_m: 6000,
			source: 'strava' as const,
			external_id: externalId,
			is_public: false,
			metadata: { activity_type: 'run', strava_id: externalId }
		};

		const first = await admin.from('runs').insert(baseRow).select('id').single();
		expect(first.error).toBeNull();
		expect(first.data?.id).toBeTruthy();

		try {
			// Now try to insert the SAME row a second time. Must 23505
			// — and the error message should mention the constraint /
			// duplicate so a debugger can map it to the right cause.
			const second = await admin.from('runs').insert(baseRow);
			expect(second.error?.code).toBe('23505');
			expect(second.error?.message.toLowerCase()).toMatch(
				/duplicate|unique|external_id/
			);

			// Still exactly one row.
			const { count } = await admin
				.from('runs')
				.select('*', { count: 'exact', head: true })
				.eq('external_id', externalId);
			expect(count).toBe(1);
		} finally {
			await admin.from('runs').delete().eq('external_id', externalId);
		}
	});
});
