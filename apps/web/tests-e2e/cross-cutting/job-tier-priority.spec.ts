import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Tier-aware job scheduling — Pro / lifetime users jump the
 * `jobs` queue; free users wait `FREE_TIER_DELAY_SECONDS` (30 s) so
 * their `map_match` job becomes claimable later. The worker's
 * `claim_next_job` already filters `scheduled_at <= now()` and
 * orders by `(scheduled_at, id)`, so a Pro job is always claimable
 * strictly before a free job inserted at the same wall-clock
 * moment.
 *
 * This pins the contract end-to-end:
 *   1. Plant runner's run (free tier) with a track. The auto-enqueue
 *      trigger fires; observe `scheduled_at` ~30 s in the future.
 *   2. Plant morgan's run (pro tier) with a track. The same trigger
 *      fires; observe `scheduled_at` ≈ now().
 *   3. Assert morgan's `scheduled_at` is at least 25 s earlier than
 *      runner's. (25 s gives margin against test-runner clock slip;
 *      the actual gap is ~30 s minus the few-ms wall-clock drift
 *      between the two `insertRun` calls.)
 *   4. Sanity: both jobs exist in `jobs`, both kind='map_match',
 *      both status='queued'.
 *
 * Redeems the existing /settings/upgrade Pro promise — "Priority
 * processing — Faster responses when the service is under heavy
 * load." Until migration 20260730_001 that copy was unredeemed:
 * `claim_next_job` was strict FIFO and the trigger stamped
 * `scheduled_at = default now()` for everyone.
 *
 * What this DOESN'T test: the helper function
 * `job_scheduled_at_for_user(uuid)` itself, in isolation. That's
 * a one-line CASE expression and the assertion above is a more
 * useful end-to-end pin (the helper-and-trigger composition).
 */

const FREE_TIER_DELAY_SECONDS = 30;

test.describe('jobs queue — Pro tier jumps the line', () => {
	test('two simultaneous run inserts: morgan (pro) is claimable ~30 s before runner (free)', async () => {
		// Plant the free-tier run first so morgan's later insert with
		// `scheduled_at = now()` lands on a slightly later wall-clock
		// `now()`. That makes the priority-jump assertion stronger:
		// morgan was enqueued AFTER runner but is still claimable
		// FIRST.
		const runnerRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T07:00:00Z').toISOString(),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-30T07:00:00Z' },
				{ lat: -33.89, lng: 151.28, ele: 11, t: '2026-04-30T07:01:00Z' }
			]
		});

		const morganRunId = await insertRun({
			user_id: USER_C_PRO.id,
			started_at: new Date('2026-04-30T08:00:00Z').toISOString(),
			distance_m: 6_000,
			duration_s: 1_700,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-30T08:00:00Z' },
				{ lat: -33.89, lng: 151.28, ele: 11, t: '2026-04-30T08:01:00Z' }
			]
		});

		try {
			const admin = getAdminClient();

			// Read both jobs the trigger enqueued. The dedupe index
			// guarantees one row per run_id while queued/running, so
			// `.single()` is safe here.
			const { data: rows, error } = await admin
				.from('jobs')
				.select('id, kind, status, scheduled_at, payload')
				.eq('kind', 'map_match')
				.in('status', ['queued', 'running'])
				.in('payload->>run_id', [runnerRunId, morganRunId]);
			expect(error).toBeNull();
			expect(rows?.length, 'one map_match job per run').toBe(2);

			const runnerJob = rows?.find(
				(r) => (r.payload as { run_id: string }).run_id === runnerRunId
			);
			const morganJob = rows?.find(
				(r) => (r.payload as { run_id: string }).run_id === morganRunId
			);
			expect(runnerJob).toBeDefined();
			expect(morganJob).toBeDefined();

			const runnerSched = new Date(runnerJob!.scheduled_at as string).getTime();
			const morganSched = new Date(morganJob!.scheduled_at as string).getTime();
			const gapSeconds = (runnerSched - morganSched) / 1000;

			expect(
				gapSeconds,
				`morgan (pro) should be at least ${FREE_TIER_DELAY_SECONDS - 5} s earlier than runner (free); ` +
					`got gap = ${gapSeconds.toFixed(2)} s. The 30 s constant is in migration ` +
					`20260730_001 — if the constant changes, update this margin too.`
			).toBeGreaterThanOrEqual(FREE_TIER_DELAY_SECONDS - 5);

			// The Pro job should be claimable now-ish; the free job should
			// not be claimable yet. The worker's `claim_next_job` filters
			// `scheduled_at <= now()`, so this is the property that
			// matters under contention.
			const now = Date.now();
			expect(
				morganSched - now,
				'morgan (pro) job should be claimable within ~5 s of insert'
			).toBeLessThan(5_000);
			expect(
				runnerSched - now,
				'runner (free) job should NOT be claimable yet (still in the future)'
			).toBeGreaterThan(20_000);
		} finally {
			await deleteRun(runnerRunId);
			await deleteRun(morganRunId);
		}
	});

	test('helper job_scheduled_at_for_user returns now for pro, now+30s for free', async () => {
		// Direct unit-style test of the helper via service-role RPC
		// call. Keeps the CASE expression honest in case someone
		// later "simplifies" it into a different shape.
		const admin = getAdminClient();

		const { data: proAt, error: proErr } = await admin.rpc(
			'job_scheduled_at_for_user',
			{ p_user_id: USER_C_PRO.id }
		);
		expect(proErr).toBeNull();
		const proGap = new Date(proAt as string).getTime() - Date.now();
		expect(
			proGap,
			'pro user: scheduled_at should be ≈ now() (within ±5 s for clock + RPC round-trip)'
		).toBeGreaterThan(-5_000);
		expect(proGap).toBeLessThan(5_000);

		const { data: freeAt, error: freeErr } = await admin.rpc(
			'job_scheduled_at_for_user',
			{ p_user_id: USER_A.id }
		);
		expect(freeErr).toBeNull();
		const freeGap =
			new Date(freeAt as string).getTime() - Date.now();
		expect(
			freeGap,
			`free user: scheduled_at should be ≈ now() + ${FREE_TIER_DELAY_SECONDS}s`
		).toBeGreaterThan((FREE_TIER_DELAY_SECONDS - 5) * 1000);
		expect(freeGap).toBeLessThan((FREE_TIER_DELAY_SECONDS + 5) * 1000);

		// Unknown / non-existent user: helper falls back to free
		// (conservative default — see the migration comment).
		const fakeId = '00000000-0000-0000-0000-000000000000';
		const { data: unknownAt } = await admin.rpc(
			'job_scheduled_at_for_user',
			{ p_user_id: fakeId }
		);
		const unknownGap =
			new Date(unknownAt as string).getTime() - Date.now();
		expect(
			unknownGap,
			'unknown user: scheduled_at must be the free-tier delay (conservative default)'
		).toBeGreaterThan((FREE_TIER_DELAY_SECONDS - 5) * 1000);
	});

	test('manual re-match via enqueue_run_rematch RPC also honours tier priority', async () => {
		// Plant a runner-owned run, then call enqueue_run_rematch as
		// runner — the rematch RPC reuses the helper, so the new job
		// should land with `scheduled_at = now() + 30 s`. Then plant a
		// morgan-owned run + call rematch for it — should land at
		// `now()`.
		const admin = getAdminClient();

		const runnerRunId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-04-30T09:00:00Z').toISOString(),
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, t: '2026-04-30T09:00:00Z' }
			]
		});
		const morganRunId = await insertRun({
			user_id: USER_C_PRO.id,
			started_at: new Date('2026-04-30T09:00:00Z').toISOString(),
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, t: '2026-04-30T09:00:00Z' }
			]
		});

		try {
			// Clear the auto-enqueued jobs so we can isolate the
			// rematch path. (`status='cancelled'` lets the dedupe
			// index allow a fresh insert.)
			await admin
				.from('jobs')
				.update({ status: 'cancelled' })
				.eq('kind', 'map_match')
				.in('payload->>run_id', [runnerRunId, morganRunId]);

			// Use a real user JWT for each rematch — the RPC checks
			// auth.uid() against the run's user_id.
			const { getUserClient } = await import('../fixtures/local-supabase');
			const runnerClient = await getUserClient({
				email: USER_A.email,
				password: USER_A.password
			});
			const morganClient = await getUserClient({
				email: USER_C_PRO.email,
				password: USER_C_PRO.password
			});

			const { error: rerrR } = await runnerClient.rpc(
				'enqueue_run_rematch',
				{ p_run_id: runnerRunId }
			);
			expect(rerrR).toBeNull();
			const { error: rerrM } = await morganClient.rpc(
				'enqueue_run_rematch',
				{ p_run_id: morganRunId }
			);
			expect(rerrM).toBeNull();

			const { data: rows } = await admin
				.from('jobs')
				.select('payload, scheduled_at')
				.eq('kind', 'map_match')
				.eq('status', 'queued')
				.in('payload->>run_id', [runnerRunId, morganRunId]);
			expect(rows?.length).toBe(2);

			const runnerJob = rows?.find(
				(r) => (r.payload as { run_id: string }).run_id === runnerRunId
			);
			const morganJob = rows?.find(
				(r) => (r.payload as { run_id: string }).run_id === morganRunId
			);
			const gap =
				(new Date(runnerJob!.scheduled_at as string).getTime() -
					new Date(morganJob!.scheduled_at as string).getTime()) /
				1000;
			expect(
				gap,
				'manual rematch must apply the same tier offset as the auto-trigger'
			).toBeGreaterThanOrEqual(FREE_TIER_DELAY_SECONDS - 5);
		} finally {
			await deleteRun(runnerRunId);
			await deleteRun(morganRunId);
		}
	});
});
