import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Personal-records / PB journey — a run that sets a new personal best
 * threads from the runs table, through the trigger-maintained
 * `personal_records` cache, onto the /dashboard PB card, and the
 * delete of the PB run recomputes the cache back to the previous best.
 * This is the derived-cache contract (docs/backend/derived_state.md §
 * personal_records) walked end to end via the UI rather than pinned in
 * isolation by pgtap — it exercises the insert→trigger→cache→read seam
 * and the delete→recompute seam that the focused suites don't.
 *
 * The 5k bracket (4900-5100 m) already holds a pre-existing best for
 * USER_A (seed / seed-extension), so this spec does NOT assume an empty
 * canvas. It READS the current cached 5k best at setup and derives two
 * faster times from it (existing - 60 and existing - 120, floored), so
 * the journey is deterministic whatever the seed's 5k time is:
 *
 *   1. Establish a NEW BASELINE 5k PB by inserting a 5000 m run that
 *      beats the pre-existing best by 60 s. best-time-wins ranks it as
 *      the cache's 5k row. The runs insert trigger fires
 *      refresh_personal_records_for_user, so the cache updates without a
 *      manual rebuild, and the /dashboard PB card's 5k row reads it.
 *   2. Set a NEW PB: insert a 5000 m run 60 s faster again (120 s under
 *      the original best). The cache's 5k row flips to it (backend
 *      cross-check via the admin client) and the dashboard reflects it.
 *   3. Delete the faster PB run. The delete trigger recomputes the
 *      cache, which must fall back to our step-1 baseline (still faster
 *      than the pre-existing seed best, because we made it so) — the
 *      cache=authoritative-query contract: the row is not left stale at
 *      the deleted run's time. The dashboard reflects the baseline.
 *
 * Surfaces: the ONLY UI PB surface today is the /dashboard PB table
 * (.pr-table, distance label '5k' → .pr-time = formatDuration). The
 * run-detail page carries no PR badge (it only reads is_dnf, which
 * EXCLUDES a run from PR scoring — confirmed in
 * src/routes/runs/[id]/+page.svelte), so there's nothing to assert
 * there. The records roll-up under /gym/records is gym-only, not run
 * PBs. So the dashboard table is the sole read surface.
 *
 * Bracket math (migration 20260831_001, the live refresher body):
 *   5k = distance_m between 4900 and 5100 → 5000 m lands cleanly.
 *   Best time wins per bracket; DNFs + non-tracked sources excluded
 *   (source must be app/watch/strava/garmin/healthkit/healthconnect —
 *   insertRun defaults source 'app', is_dnf false, so both inserts
 *   count).
 *
 * formatDuration (lib/format/time.ts) renders a sub-hour time as
 * `M:SS` with no hours segment, so the derived seconds are formatted
 * the same way and compared as a label computed at runtime.
 */

// formatDuration (lib/format/time.ts) for a sub-hour time: `M:SS`, no
// hours segment, seconds zero-padded. Mirrors the cell the PB table
// renders so we can assert the dashboard against a runtime-derived best.
function mmss(totalSeconds: number): string {
	const m = Math.floor(totalSeconds / 60);
	const s = totalSeconds % 60;
	return `${m}:${String(s).padStart(2, '0')}`;
}

test.describe('personal records journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('baseline 5k PB → faster run sets new PB (cache + dashboard) → delete recomputes to previous best', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Both 5k runs; ids captured so the finally-block sweeps whatever
		// survived a mid-journey failure.
		let baselineRunId = '';
		let pbRunId = '';

		// The 5k row's time cell on the dashboard PB table: scope to the
		// .pr-table row whose .pr-distance is the '5k' label so a parallel
		// session's runs (other brackets) can't disambiguate the read.
		const prFiveKTime = page
			.locator('.pr-table tbody tr', {
				has: page.locator('.pr-distance', { hasText: /^5k$/ })
			})
			.locator('.pr-time');

		// Read the cached 5k best straight from the trigger-maintained table.
		const cached5kBest = async (): Promise<number | null> => {
			const { data } = await admin
				.from('personal_records')
				.select('best_time_s')
				.eq('user_id', USER_A.id)
				.eq('distance', '5k')
				.maybeSingle();
			return (data?.best_time_s as number | undefined) ?? null;
		};

		// Derive the journey's two times from whatever 5k best the seed
		// already holds, rather than hardcoding a baseline that a faster
		// pre-existing 5k run would silently out-rank (the cache correctly
		// keeps the faster time, so a slower hardcoded baseline never
		// becomes the cache's row). If the bracket happens to be empty,
		// fall back to a 25:00 anchor so the relative math still has a
		// realistic floor. BASELINE beats the existing best by 60 s, the
		// PB by 120 s — both clamped to a positive realistic floor so the
		// arithmetic can't go non-positive on an already-fast seed.
		const existingBest = (await cached5kBest()) ?? 1500;
		const BASELINE_S = Math.max(existingBest - 60, 600);
		const NEW_PB_S = Math.max(existingBest - 120, BASELINE_S - 60);
		const BASELINE_LABEL = mmss(BASELINE_S);
		const NEW_PB_LABEL = mmss(NEW_PB_S);
		expect(NEW_PB_S).toBeLessThan(BASELINE_S);
		expect(BASELINE_S).toBeLessThan(existingBest);

		try {
			// ── 1. Establish the new baseline 5k PB ────────────────────
			await test.step('insert a 5000 m run that beats the existing 5k best → new cache record', async () => {
				// Service-role insert fires the runs→personal_records trigger.
				baselineRunId = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - 3 * 86_400_000).toISOString(),
					distance_m: 5000,
					duration_s: BASELINE_S
				});

				// The trigger runs synchronously inside the insert txn, so the
				// cache row is present immediately; poll only to absorb any
				// connection-pool lag on the admin read.
				await expect.poll(cached5kBest, { timeout: 10_000 }).toBe(BASELINE_S);

				// The dashboard PB card shows the baseline. fetchPersonalRecords
				// reads the same cache and labels the bracket '5k'.
				await page.goto('/dashboard');
				await expect(prFiveKTime).toHaveText(BASELINE_LABEL, { timeout: 15_000 });
			});

			// ── 2. A faster run sets a new PB ──────────────────────────
			await test.step('insert a faster 5000 m run → cache + dashboard flip to the new best', async () => {
				pbRunId = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - 1 * 86_400_000).toISOString(),
					distance_m: 5000,
					duration_s: NEW_PB_S
				});

				// best-time-wins: the cache's 5k row recomputes to the faster time.
				await expect.poll(cached5kBest, { timeout: 10_000 }).toBe(NEW_PB_S);
				// And it points at the faster run, not the slower baseline.
				const { data: pbRow } = await admin
					.from('personal_records')
					.select('run_id')
					.eq('user_id', USER_A.id)
					.eq('distance', '5k')
					.maybeSingle();
				expect(pbRow?.run_id).toBe(pbRunId);

				// The PB card reflects the improved time (a reload, not stale
				// local state — the dashboard fetches on mount).
				await page.goto('/dashboard');
				await expect(prFiveKTime).toHaveText(NEW_PB_LABEL, { timeout: 15_000 });
			});

			// ── 3. Deleting the PB recomputes to the previous best ─────
			await test.step('delete the faster run → cache falls back to the baseline, not stale at the deleted PB', async () => {
				await deleteRun(pbRunId);
				const deletedPbId = pbRunId;
				pbRunId = ''; // deleted — finally-block skips it

				// The delete trigger recomputes: the 5k row must equal the
				// authoritative query again, which is now the surviving
				// baseline (still faster than the pre-existing seed best) —
				// NOT left orphaned at the deleted run's faster time.
				await expect.poll(cached5kBest, { timeout: 10_000 }).toBe(BASELINE_S);
				const { data: afterRow } = await admin
					.from('personal_records')
					.select('run_id')
					.eq('user_id', USER_A.id)
					.eq('distance', '5k')
					.maybeSingle();
				expect(afterRow?.run_id).toBe(baselineRunId);
				expect(afterRow?.run_id).not.toBe(deletedPbId);

				// Dashboard re-reads the recomputed cache and shows 25:00.
				await page.goto('/dashboard');
				await expect(prFiveKTime).toHaveText(BASELINE_LABEL, { timeout: 15_000 });
			});
		} finally {
			// Safety net — sweep whichever 5k runs survived (the baseline
			// always; the PB run if a step failed before its delete). The
			// delete re-fires the trigger, leaving the seed's 5k-less cache
			// state intact for downstream specs.
			for (const id of [pbRunId, baselineRunId].filter(Boolean)) {
				await deleteRun(id).catch(() => {});
			}
		}
	});
});
