import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * `find_stuck_jobs(interval)` + `jobs_stuck_summary(interval)` —
 * read-only operator surface that flags `status='running'` rows
 * older than the threshold. Companion to the round-9 tier-aware
 * scheduling: the priority semantic only holds if no single job
 * runs long enough to starve the queue, so any job stuck in
 * `running` past the threshold is by definition a contract
 * violation worth surfacing.
 *
 * Migration `20260731_001` schedules `jobs_stuck_summary()` via
 * pg_cron every 10 minutes. The function is also callable directly
 * via service-role for ad-hoc operator queries and (eventually) by
 * a Sentry / Grafana scraper. We do NOT auto-fail stuck jobs —
 * that would race a worker that's about to call `finish_job` for
 * the same row.
 *
 * Tests pin:
 *   - Idle queue → stuck_count=0, sample=[]
 *   - One stuck job (locked_at = 6 min ago) → stuck_count=1,
 *     sample contains the row's id + kind + age
 *   - Custom threshold honours the interval arg (a job locked
 *     2 min ago is stuck under `interval '1 minute'` but not
 *     under the default `interval '5 minutes'`)
 *   - find_stuck_jobs returns the same row identity as the
 *     summary's sample (consistency between the two functions)
 */

test.describe('jobs-stuck-alert — read-only operator surface', () => {
	test('idle queue returns stuck_count=0 + empty sample', async () => {
		const admin = getAdminClient();
		const { data, error } = await admin.rpc('jobs_stuck_summary');
		expect(error).toBeNull();

		// The seed enqueued 12 map_match jobs (one per seeded run);
		// none should be `status='running'` because no worker is
		// drained the queue in this test environment. Stuck count
		// MUST be 0 because stuck = running-and-old, not queued.
		const summary = data as {
			stuck_count: number;
			oldest_age_s: number;
			sample: unknown[];
			checked_at: string;
		};
		expect(summary.stuck_count).toBe(0);
		expect(summary.sample).toEqual([]);
		expect(summary.oldest_age_s).toBe(0);
		expect(typeof summary.checked_at).toBe('string');
	});

	test('a job locked > 5 min ago surfaces in stuck_count + sample', async () => {
		const admin = getAdminClient();

		// Plant a run so the trigger enqueues a fresh map_match job
		// we can manipulate without disturbing the seeded ones.
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-01T07:00:00Z').toISOString(),
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, t: '2026-05-01T07:00:00Z' }
			]
		});

		try {
			// Force the row into status='running' with locked_at 6 min ago
			// — mirrors a wedged worker that never called finish_job.
			const sixMinAgo = new Date(Date.now() - 6 * 60_000).toISOString();
			const { data: rows, error: setErr } = await admin
				.from('jobs')
				.update({
					status: 'running',
					locked_at: sixMinAgo,
					locked_by: 'e2e-stuck-job-fake-worker'
				})
				.eq('kind', 'map_match')
				.eq('payload->>run_id', runId)
				.select('id');
			expect(setErr).toBeNull();
			expect(rows?.length).toBe(1);
			const stuckJobId = rows![0].id as number;

			// Default threshold is 5 minutes; 6 min ago is over it.
			const { data, error } = await admin.rpc('jobs_stuck_summary');
			expect(error).toBeNull();
			const summary = data as {
				stuck_count: number;
				oldest_age_s: number;
				sample: Array<{ id: number; kind: string; age_s: number }>;
			};
			expect(summary.stuck_count, 'stuck_count must include our planted job')
				.toBeGreaterThanOrEqual(1);
			expect(summary.oldest_age_s, 'oldest_age_s must be ≥ ~6 min')
				.toBeGreaterThanOrEqual(330); // 5.5 min, leaves margin
			const ours = summary.sample.find((s) => s.id === stuckJobId);
			expect(ours, 'sample must reference our planted stuck job').toBeDefined();
			expect(ours!.kind).toBe('map_match');
			expect(ours!.age_s).toBeGreaterThanOrEqual(330);

			// And find_stuck_jobs should return the same row identity.
			const { data: rowList, error: listErr } = await admin.rpc(
				'find_stuck_jobs'
			);
			expect(listErr).toBeNull();
			const list = rowList as Array<{ id: number; kind: string }>;
			expect(list.find((r) => r.id === stuckJobId)).toBeDefined();
		} finally {
			// Reset the planted row back to a clean state before
			// deleteRun (which deletes via service-role).
			await admin
				.from('jobs')
				.update({ status: 'cancelled', locked_at: null, locked_by: null })
				.eq('kind', 'map_match')
				.eq('payload->>run_id', runId);
			await deleteRun(runId);
		}
	});

	test('custom threshold: a job locked 2 min ago is stuck under 1m but NOT under 5m', async () => {
		// Pin the threshold-arg behaviour: a recent-running job is
		// only "stuck" for a tighter window. Catches a regression
		// where the function ignored its argument and always used
		// the 5-min default.
		const admin = getAdminClient();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date('2026-05-01T08:00:00Z').toISOString(),
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, t: '2026-05-01T08:00:00Z' }
			]
		});

		try {
			const twoMinAgo = new Date(Date.now() - 2 * 60_000).toISOString();
			const { data: rows } = await admin
				.from('jobs')
				.update({
					status: 'running',
					locked_at: twoMinAgo,
					locked_by: 'e2e-threshold-test'
				})
				.eq('kind', 'map_match')
				.eq('payload->>run_id', runId)
				.select('id');
			const stuckJobId = rows![0].id as number;

			// Default 5-min threshold: NOT stuck.
			const { data: defaultSummary } = await admin.rpc('jobs_stuck_summary');
			const def = defaultSummary as {
				sample: Array<{ id: number }>;
			};
			expect(def.sample.find((s) => s.id === stuckJobId), '2-min-old should NOT be stuck under 5-min threshold')
				.toBeUndefined();

			// Custom 1-min threshold: IS stuck.
			const { data: customSummary } = await admin.rpc(
				'jobs_stuck_summary',
				{ p_stuck_after: '1 minute' }
			);
			const cus = customSummary as {
				stuck_count: number;
				sample: Array<{ id: number }>;
			};
			expect(cus.sample.find((s) => s.id === stuckJobId), '2-min-old MUST be stuck under 1-min threshold')
				.toBeDefined();
			expect(cus.stuck_count).toBeGreaterThanOrEqual(1);
		} finally {
			await admin
				.from('jobs')
				.update({ status: 'cancelled', locked_at: null, locked_by: null })
				.eq('kind', 'map_match')
				.eq('payload->>run_id', runId);
			await deleteRun(runId);
		}
	});

	test('pg_cron schedule `jobs-stuck-alert` is registered + active', async () => {
		// Migration registered the schedule via cron.schedule. Pin
		// that the row exists; a regression that dropped the cron
		// schedule (or renamed it) loses the alerting silently
		// without breaking any other test. PostgREST exposes only
		// `public` + `graphql_public`, so we go through the
		// `cron_schedule_status(text)` wrapper added by the same
		// migration.
		const admin = getAdminClient();
		const { data, error } = await admin.rpc('cron_schedule_status', {
			p_jobname: 'jobs-stuck-alert'
		});
		expect(error).toBeNull();
		expect(data, 'cron schedule jobs-stuck-alert must exist').not.toBeNull();
		const row = data as {
			jobname: string;
			schedule: string;
			active: boolean;
		};
		expect(row.schedule).toBe('*/10 * * * *');
		expect(row.active).toBe(true);
	});
});
