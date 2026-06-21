import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Concurrent UNIQUE-constraint resilience on `run_kudos`.
 *
 * `run_kudos` has `primary key (user_id, run_id)` — a kudos pair is
 * unique by definition. The toggleKudos UI handler is optimistic
 * (flip the count locally → write → reconcile on error). A
 * double-tap, a misbehaving Realtime echo, or two browser tabs
 * firing the same insert race the PK constraint — one INSERT wins,
 * the others raise 23505. The data layer must swallow that as a
 * no-op (the kudos already exists, semantically equivalent to
 * success) rather than surfacing a flash error.
 *
 * This test pins that contract end-to-end: fire N simultaneous
 * kudos inserts via supabase-js and assert (a) exactly one row
 * lands, (b) no INSERT raises a non-23505 error. A regression that
 * removed the dedupe fallback (e.g. switching to `insert(... { onConflict: 'ignore' })` later
 * dropped) would surface as multiple errors here. A regression that
 * made the kudos table non-UNIQUE (e.g. losing the PK) would
 * surface as N rows landing.
 */

const PARALLEL = 5;

test.describe('run_kudos — concurrent insert resilience', () => {
	test('5 parallel kudos inserts for same (user, run) pair land exactly 1 row', async () => {
		// Plant a public run owned by runner so alex can kudos it.
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T07:00:00Z').toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title: 'concurrent-kudos test' }
		});

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});

			// Fire N parallel inserts. Each is the canonical kudos shape
			// the UI uses today. `Promise.allSettled` lets us see ALL
			// outcomes — one settled fulfilled (the winner), rest may be
			// fulfilled with `error.code = '23505'` (dedupe path) or
			// fulfilled with no error if supabase-js silently swallows.
			const results = await Promise.allSettled(
				Array.from({ length: PARALLEL }, () =>
					alex.from('run_kudos').insert({ run_id: runId, user_id: USER_B.id })
				)
			);

			// Every outcome must be either (a) fulfilled with no error
			// (winning INSERT) OR (b) fulfilled with a 23505 (PK
			// violation — the expected dedupe outcome). NO rejection,
			// and no 4xx-other-than-23505 / 5xx errors. A regression
			// that surfaced 4xx-other-than-23505 here would crash the
			// optimistic UI handler.
			for (const [i, r] of results.entries()) {
				if (r.status === 'rejected') {
					throw new Error(
						`kudos insert #${i} rejected (should fulfil with error data, not throw): ${r.reason}`
					);
				}
				const { error } = r.value;
				if (error) {
					expect(
						error.code,
						`kudos insert #${i} returned a non-23505 error (${error.code}: ${error.message})`
					).toBe('23505');
				}
			}

			// Service-role count: exactly one row landed.
			const admin = getAdminClient();
			const { count, error: countErr } = await admin
				.from('run_kudos')
				.select('*', { count: 'exact', head: true })
				.eq('run_id', runId)
				.eq('user_id', USER_B.id);
			expect(countErr).toBeNull();
			expect(
				count,
				`exactly one kudos row must land after ${PARALLEL} concurrent inserts; ` +
					`a non-1 count means the PK is missing or the dedupe path regressed`
			).toBe(1);
		} finally {
			await deleteRun(runId);
		}
	});

	/**
	 * Pins the data-layer contract the optimistic kudos UI relies on
	 * (giveKudos/rescindKudos in core/data.ts return whether the row
	 * ACTUALLY changed). The drift bug: a stale local
	 * `viewer_has_kudos: false` (kudos given from another tab) made
	 * toggleKudos fire an insert that 23505s as a no-op, yet the UI
	 * still bumped the count `+1` — the displayed total drifted one
	 * above the server's. The fix keys the optimistic delta on the
	 * real mutation outcome:
	 *   - a duplicate INSERT lands no row (23505) → no `+1`,
	 *   - a DELETE that matched nothing returns zero rows → no `-1`.
	 */
	test('duplicate insert is a no-op and delete reports rows actually removed', async () => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T08:00:00Z').toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title: 'kudos-noop test' }
		});

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});

			// First kudos lands a row (giveKudos would return true).
			const first = await alex.from('run_kudos').insert({ run_id: runId, user_id: USER_B.id });
			expect(first.error, 'first kudos insert should succeed').toBeNull();

			// Second insert (the stale-flag re-tap) is a 23505 no-op —
			// giveKudos returns false, so the UI must NOT add a second `+1`.
			const dup = await alex.from('run_kudos').insert({ run_id: runId, user_id: USER_B.id });
			expect(dup.error?.code, 'duplicate kudos insert must 23505 (no new row)').toBe('23505');

			const admin = getAdminClient();
			const afterInsert = await admin
				.from('run_kudos')
				.select('*', { count: 'exact', head: true })
				.eq('run_id', runId)
				.eq('user_id', USER_B.id);
			expect(afterInsert.count, 'still exactly one kudos row after the duplicate').toBe(1);

			// Delete-with-select returns the rows it removed —
			// rescindKudos reads `.length > 0` to drive the optimistic `-1`.
			const del = await alex
				.from('run_kudos')
				.delete()
				.eq('run_id', runId)
				.eq('user_id', USER_B.id)
				.select('user_id');
			expect(del.error, 'delete should succeed').toBeNull();
			expect(
				(del.data ?? []).length,
				'delete must report the one removed row so the UI applies the -1'
			).toBe(1);

			// A second delete matches nothing → zero rows → no `-1`.
			const delAgain = await alex
				.from('run_kudos')
				.delete()
				.eq('run_id', runId)
				.eq('user_id', USER_B.id)
				.select('user_id');
			expect(delAgain.error).toBeNull();
			expect(
				(delAgain.data ?? []).length,
				'a delete that matched nothing returns zero rows (rescindKudos → false)'
			).toBe(0);
		} finally {
			await deleteRun(runId);
		}
	});
});
