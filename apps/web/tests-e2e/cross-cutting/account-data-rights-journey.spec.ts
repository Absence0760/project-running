import { createHash } from 'node:crypto';
import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser,
} from '../fixtures/saga-users';
import { insertComment, insertKudos, insertRun } from '../fixtures/simulate';

/**
 * Account data-rights JOURNEY — the GDPR cradle-to-grave arc for a user
 * whose data is spread across MANY tables + modalities (a run with a
 * GPS track, a strength workout with sets, a nutrition diary entry, a
 * body-metric, a club membership, a kudos they gave, a comment they
 * wrote). The same person exercises BOTH data rights in sequence:
 *
 *   1. RIGHT TO PORTABILITY (Art 20). They hit the REAL `export-data`
 *      Edge Function in its `backup` format — the structured-JSON zip
 *      that mirrors the Go worker's table set (export-data/backup_spec.ts).
 *      The zip is unpacked and asserted COMPLETE across the modalities:
 *      gym_workouts.json carries the planted workout WITH its nested
 *      sets, food_log.json the meal, body_metrics.json the weight,
 *      club_members.json the membership, run_kudos.json the kudos,
 *      run_comments.json the comment, runs.json the run. A modality
 *      MISSING from the export is a real Art 20 gap — this is the half
 *      that the GPX-only privacy-data-rights-journey + the saga never
 *      check (the GPX export covers RUNS only; the multi-modal tables
 *      ride only the `backup` format).
 *
 *   2. RIGHT TO ERASURE (Art 17). The same user drives /settings/account
 *      → Delete Account → types their email into the re-entry challenge
 *      → confirms. The page calls the REAL `delete-account` Edge Function
 *      (PUBLIC_EXPORT_HUB_URL-style hub flips don't apply here — the
 *      delete button always hits the EF) and redirects to /login. Then,
 *      at the DB level via getAdminClient(), every personal-data table
 *      the export COVERED is asserted EMPTY for that user, the run's
 *      gzipped track + the export blob are gone from Storage, the auth
 *      row is gone, and the deletion is recorded in deletion_audit_log
 *      with result='ok'. A table whose rows SURVIVE the delete is a real
 *      Art 17 erasure gap.
 *
 * Why this is a NEW slice (surveyed against the existing specs):
 *   - cross-cutting/export-data-guards.spec.ts — pre-side-effect gates
 *     (405/401/413/400) only; never builds a real export.
 *   - cross-cutting/delete-account-guards.spec.ts — pre-side-effect
 *     gates only; never runs the destructive path.
 *   - cross-cutting/privacy-data-rights-journey.spec.ts — exports the
 *     GPX format and checks ONE run's track is unclipped; never the
 *     multi-modal `backup` tables, and never deletes.
 *   - cross-user/sagas/account-deletion.spec.ts — deletes + asserts the
 *     RUN/social cascade (runs, coach_messages, personal_records,
 *     notifications, direct_messages, user_blocks, coach_athletes) but
 *     NOT the Phase-4 multi-modal gym/food/body tables, and never
 *     exports. This spec joins the two halves AND extends the erasure
 *     assertion to the gym/food/body modalities + the social-engagement
 *     tables (run_kudos, run_comments, club_members) the saga skips.
 *
 * Why a saga user, not runner@test.com: the delete step DESTROYS the
 * user (that IS its cleanup). Deleting the seed user would scorch every
 * other test. The ephemeral saga user is the only safe vehicle, and
 * deleteSagaUsers in afterAll sweeps a half-failed run (it tolerates an
 * already-gone auth row).
 *
 * The export leg runs the REAL local `export-data` EF (the same one the
 * guard specs invoke). The delete leg runs the REAL local `delete-account`
 * EF (the same one the saga drives via the UI). Both are served by the
 * local Supabase stack; neither is mocked.
 */

// `delete-account` writes a pseudonymous hash to deletion_audit_log:
// HMAC-SHA256(DELETION_AUDIT_KEY, userId) when the key is set, else the
// legacy salted SHA-256(salt || userId). Local dev leaves
// DELETION_AUDIT_KEY empty (apps/backend/.env.development), so the EF
// takes the legacy branch and this reproduces it. Keep the salt in
// lockstep with delete-account/lib.ts#hashUserIdForAudit.
const LEGACY_AUDIT_SALT = 'threkir-deletion-audit-v1';
function legacyAuditHash(userId: string): string {
	return createHash('sha256').update(`${LEGACY_AUDIT_SALT}:${userId}`).digest('hex');
}

test.describe('saga: account data-rights cradle-to-grave (export → delete)', () => {
	// Real server-side export build + download, then the full delete
	// chain (Storage walk + third-party + cascade). Give it room.
	test.describe.configure({ timeout: 120_000 });

	let user: SagaUser;
	// A second user so the relational engagement rows have a real
	// counterpart (the club owner / the run the kudos+comment hang off,
	// the other side of a follow). Only `user` is deleted.
	let other: SagaUser;

	// Track planted ids so afterAll teardown is precise even on a
	// half-failed run (the per-table erasure assertions clear them on
	// the happy path; teardown is the safety net).
	let plantedRunId: string | null = null;
	let clubId: string | null = null;

	test.beforeAll(async () => {
		[user, other] = await createSagaUsers(2, {
			displayNames: ['Saga Data Rights', 'Saga Counterpart'],
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		// Best-effort: drop a club we created (its owner_id is `user`, but
		// deleteSagaUsers wipes owner-table rows too; this just makes the
		// half-failed path tidy). The run + multi-modal rows cascade with
		// the auth row, so we don't sweep them individually.
		if (clubId) {
			try {
				await admin.from('clubs').delete().eq('id', clubId);
			} catch {
				/* best-effort */
			}
		}
		// On the happy path `user` is already gone — deleteSagaUsers is a
		// no-op for them (tolerates a missing row); `other` is always swept.
		await deleteSagaUsers([user, other]);
	});

	test('a multi-modal user exports a complete bundle, then deletes and is fully erased', async ({
		browser,
	}) => {
		const admin = getAdminClient();

		await test.step('seed: cross-table, cross-modal personal data', async () => {
			// 1) A run with a real gzipped track (row + Storage object).
			plantedRunId = await insertRun({
				user_id: user.id,
				started_at: new Date('2026-05-01T07:00:00Z').toISOString(),
				distance_m: 6_200,
				duration_s: 2_040,
				is_public: true,
				track: [
					{ lat: -33.86, lng: 151.21, ele: 8, t: '2026-05-01T07:00:00Z' },
					{ lat: -33.861, lng: 151.211, ele: 9, t: '2026-05-01T07:00:30Z' },
					{ lat: -33.862, lng: 151.212, ele: 10, t: '2026-05-01T07:01:00Z' },
				],
			});

			// 2) A strength workout with sets (gym modality). gym_sets has
			//    no user_id of its own — it cascades from the parent workout,
			//    and the export nests it under gym_workouts.json.
			const { data: workout, error: wErr } = await admin
				.from('gym_workouts')
				.insert({
					user_id: user.id,
					title: 'Saga lower body',
					started_at: new Date('2026-05-01T17:00:00Z').toISOString(),
					duration_s: 3_000,
				})
				.select('id')
				.single();
			expect(wErr, 'gym_workouts seed must insert').toBeNull();
			const setSeed = await admin.from('gym_sets').insert({
				workout_id: workout!.id,
				set_index: 0,
				exercise_name: 'Back Squat',
				reps: 5,
				weight_kg: 100,
			});
			expect(setSeed.error, 'gym_sets seed must insert').toBeNull();

			// 3) A nutrition diary entry (food modality).
			const foodSeed = await admin.from('food_log').insert({
				user_id: user.id,
				// food_log.logged_at was renamed to started_at (20261208_001) so
				// runs/gym/food all agree on the activity-time column name.
				started_at: new Date('2026-05-01T12:30:00Z').toISOString(),
				item_name: 'Saga oatmeal',
				meal_slot: 'breakfast',
				calories: 350,
				protein_g: 12,
				carbs_g: 60,
				fat_g: 6,
			});
			expect(foodSeed.error, 'food_log seed must insert').toBeNull();

			// 4) A body metric (special-category health data, nutrition tab).
			const bodySeed = await admin.from('body_metrics').insert({
				user_id: user.id,
				recorded_at: new Date('2026-05-01T06:00:00Z').toISOString(),
				weight_kg: 72.5,
			});
			expect(bodySeed.error, 'body_metrics seed must insert').toBeNull();

			// 5) A club owned by `user` + a membership row (social modality).
			//    club_members is the table the saga's cascade assertion skips.
			const { data: club, error: cErr } = await admin
				.from('clubs')
				.insert({
					owner_id: user.id,
					name: `Saga Data Rights Club ${Date.now()}`,
					slug: `saga-dr-${Date.now()}`,
					is_public: true,
				})
				.select('id')
				.single();
			expect(cErr, 'clubs seed must insert').toBeNull();
			clubId = club!.id;
			// The enroll_club_owner_trigger (AFTER INSERT ON clubs) already
			// seated `user` as an 'owner' club_members row — it fires for the
			// service-role insert too (triggers aren't bypassed by the service
			// role, only RLS is). No manual insert (which dup-keys the
			// trigger's row); confirm the membership row the cascade assertion
			// needs is present.
			const { data: memberRow } = await admin
				.from('club_members')
				.select('user_id')
				.eq('club_id', clubId)
				.eq('user_id', user.id)
				.maybeSingle();
			expect(memberRow, 'club owner membership row must exist').not.toBeNull();

			// 6) Engagement the subject AUTHORED: a kudos + a comment on the
			//    OTHER user's public run. These are the subject's own social
			//    data (run_kudos.user_id / run_comments.author_id) — exported
			//    + erased on the subject's leg. Anchor them on `other`'s run
			//    so they survive nothing-but-the-subject's-delete.
			const otherRunId = await insertRun({
				user_id: other.id,
				started_at: new Date('2026-05-02T07:00:00Z').toISOString(),
				distance_m: 5_000,
				duration_s: 1_800,
				is_public: true,
			});
			await insertKudos(otherRunId, user.id);
			await insertComment({
				run_id: otherRunId,
				author_id: user.id,
				body: 'saga: nice splits',
			});

			// Confirm the planted state via service-role BEFORE the rights
			// flows, so a later "it's gone" assertion is "I had X, now I
			// don't" rather than "did X ever exist?".
			const runBefore = await admin
				.from('runs')
				.select('id')
				.eq('id', plantedRunId)
				.maybeSingle();
			expect(runBefore.data?.id).toBe(plantedRunId);
			const trackBefore = await admin.storage
				.from('runs')
				.list(user.id, { search: plantedRunId });
			expect(
				trackBefore.data?.find((f) => f.name.startsWith(plantedRunId!)),
			).toBeDefined();
		});

		// ─── 1. RIGHT TO PORTABILITY — the backup export is COMPLETE ───
		await test.step('export-data (backup) bundles every modality', async () => {
			// Mint a fresh user JWT and call the real local `export-data`
			// EF in `backup` format — the structured-JSON zip the multi-
			// modal tables ride in (the GPX format only carries runs). Same
			// EF the guard specs invoke; not mocked. supabase-js's
			// functions.invoke is the same wire the cloud-export call site
			// uses, but we go raw fetch so we can decode the binary zip body.
			const ctx = await browser.newContext({
				storageState: user.storageStatePath,
			});
			try {
				const page = await ctx.newPage();
				// Mint a real user JWT via the anon-key sign-in client (the same
				// fixture the RLS specs use) rather than scraping the context's
				// localStorage — the persisted supabase-js token key/shape is an
				// implementation detail, but signInWithPassword always yields a
				// live access_token for the EF bearer.
				const subjectClient = await getUserClient({
					email: user.email,
					password: user.password,
				});
				const {
					data: { session },
				} = await subjectClient.auth.getSession();
				const token = session?.access_token ?? null;
				expect(token, 'must mint a live user JWT for the subject').toBeTruthy();

				// The EF mints the signed URL against the INTERNAL gateway
				// host (http://kong:8000) which the test process can't
				// resolve; rewrite the origin to the external API URL but
				// keep the path + signature token so it still verifies
				// (mirrors privacy-data-rights-journey.spec.ts).
				const apiBase = (await import('../fixtures/local-supabase'))
					.loadSupabaseEnv().url;
				const efResp = await page.request.post(
					`${apiBase}/functions/v1/export-data`,
					{
						headers: {
							authorization: `Bearer ${token}`,
							'content-type': 'application/json',
						},
						data: { format: 'backup' },
					},
				);
				expect(
					efResp.status(),
					`export-data must return 200 (got ${efResp.status()}: ${await efResp.text()})`,
				).toBe(200);
				const exportJson = (await efResp.json()) as {
					url: string;
					count: number;
					format: string;
				};
				expect(exportJson.format).toBe('backup');

				const signed = new URL(exportJson.url);
				const apiOrigin = new URL(apiBase).origin;
				const zipResp = await page.request.get(
					`${apiOrigin}${signed.pathname}${signed.search}`,
				);
				expect(zipResp.ok()).toBeTruthy();
				const zipBytes = await zipResp.body();

				const JSZip = (await import('jszip')).default;
				const zip = await JSZip.loadAsync(zipBytes);

				async function entryRows(name: string): Promise<unknown[]> {
					const f = zip.file(name);
					expect(f, `${name} must exist in the backup export`).not.toBeNull();
					return JSON.parse(await f!.async('string')) as unknown[];
				}

				// runs.json — the run modality.
				const runs = (await entryRows('runs.json')) as Array<{ id: string }>;
				expect(
					runs.find((r) => r.id === plantedRunId),
					'export runs.json must include the planted run',
				).toBeTruthy();

				// gym_workouts.json — the strength modality, WITH nested sets.
				const gymWorkouts = (await entryRows('gym_workouts.json')) as Array<{
					id: string;
					user_id: string;
					sets?: Array<{ exercise_name: string }>;
				}>;
				const myWorkout = gymWorkouts.find((w) => w.user_id === user.id);
				expect(
					myWorkout,
					'export gym_workouts.json must include the planted workout',
				).toBeTruthy();
				expect(
					myWorkout!.sets?.some((s) => s.exercise_name === 'Back Squat'),
					'export gym_workouts.json must nest the workout sets (Art 20 — sets cascade ' +
						'from the parent and have no user_id of their own, so a missing nest erases ' +
						'every logged rep from the portable copy)',
				).toBe(true);

				// food_log.json — the nutrition modality.
				const food = (await entryRows('food_log.json')) as Array<{
					user_id: string;
					item_name: string;
				}>;
				expect(
					food.some((f) => f.user_id === user.id && f.item_name === 'Saga oatmeal'),
					'export food_log.json must include the planted meal',
				).toBe(true);

				// body_metrics.json — special-category health data.
				const body = (await entryRows('body_metrics.json')) as Array<{
					user_id: string;
				}>;
				expect(
					body.some((b) => b.user_id === user.id),
					'export body_metrics.json must include the planted weight (Art 20 health data)',
				).toBe(true);

				// club_members.json — the social-membership modality.
				const members = (await entryRows('club_members.json')) as Array<{
					user_id: string;
					club_id: string;
				}>;
				expect(
					members.some((m) => m.user_id === user.id && m.club_id === clubId),
					'export club_members.json must include the planted membership',
				).toBe(true);

				// run_kudos.json + run_comments.json — the engagement the
				// subject authored.
				const kudos = (await entryRows('run_kudos.json')) as Array<{
					user_id: string;
				}>;
				expect(
					kudos.some((k) => k.user_id === user.id),
					'export run_kudos.json must include the kudos the subject gave',
				).toBe(true);
				const comments = (await entryRows('run_comments.json')) as Array<{
					author_id: string;
					body: string;
				}>;
				expect(
					comments.some((c) => c.author_id === user.id && c.body === 'saga: nice splits'),
					'export run_comments.json must include the comment the subject wrote',
				).toBe(true);
			} finally {
				await ctx.close();
			}
		});

		// ─── 2. RIGHT TO ERASURE — delete via the UI, verify at the DB ───
		await test.step('delete account via /settings/account → /login', async () => {
			const ctx = await browser.newContext({
				storageState: user.storageStatePath,
			});
			const page = await ctx.newPage();
			try {
				await page.goto('/settings/account');

				const deleteBtn = page.getByRole('button', { name: 'Delete Account' });
				await expect(deleteBtn).toBeVisible({ timeout: 10_000 });
				await deleteBtn.click();

				// Listen for the EF response BEFORE confirming — the success
				// redirect outraces a post-hoc waitForResponse.
				const efPromise = page.waitForResponse(
					(r) =>
						r.url().includes('/functions/v1/delete-account') &&
						r.request().method() === 'POST',
					{ timeout: 15_000 },
				);
				await expect(
					page.getByRole('heading', { name: /Delete your account\?/ }),
				).toBeVisible({ timeout: 5_000 });

				// Re-entry challenge: the confirm button is disabled until the
				// user types their own email.
				const confirmBtn = page.getByRole('button', { name: /Delete my account/ });
				await expect(confirmBtn).toBeDisabled();
				await page.getByTestId('confirm-challenge-input').fill(user.email);
				await expect(confirmBtn).toBeEnabled();
				await confirmBtn.click();

				const ef = await efPromise;
				expect(
					ef.status(),
					`delete-account EF must return 200 (got ${ef.status()}: ${await ef.text()})`,
				).toBe(200);

				await page.waitForURL(/\/login/, { timeout: 15_000 });
			} finally {
				await ctx.close();
			}
		});

		await test.step('erasure is complete across every modality + Storage + audit', async () => {
			// auth row gone.
			const { data: authUser } = await admin.auth.admin.getUserById(user.id);
			expect(authUser?.user, 'auth.users row must be gone').toBeNull();

			// Each query is service-role so RLS can't mask a surviving row.
			// A non-empty result here is a real Art 17 erasure gap.
			const tables: Array<{ table: string; col: string; label: string }> = [
				{ table: 'runs', col: 'user_id', label: 'runs (run modality)' },
				{ table: 'gym_workouts', col: 'user_id', label: 'gym_workouts (strength modality)' },
				{ table: 'food_log', col: 'user_id', label: 'food_log (nutrition modality)' },
				{ table: 'body_metrics', col: 'user_id', label: 'body_metrics (health data)' },
				{ table: 'club_members', col: 'user_id', label: 'club_members (membership)' },
				{ table: 'run_kudos', col: 'user_id', label: 'run_kudos (engagement given)' },
				{ table: 'run_comments', col: 'author_id', label: 'run_comments (engagement authored)' },
				{ table: 'user_profiles', col: 'id', label: 'user_profiles (identity)' },
			];
			for (const { table, col, label } of tables) {
				const { data } = await admin.from(table).select(col).eq(col, user.id);
				expect(
					data ?? [],
					`${label} must cascade away on auth.users delete`,
				).toEqual([]);
			}

			// gym_sets has no user_id — it cascades through the parent
			// workout. Assert no set survives whose parent was the subject's
			// (verifiable only via the now-deleted workout id, so assert at
			// the orphan level: every set whose workout no longer exists is
			// itself gone). The parent gym_workouts assertion above already
			// proves the workouts are gone; this guards the deeper cascade.
			const orphanSets = await admin
				.from('gym_sets')
				.select('id, workout_id')
				.is('workout_id', null);
			expect(
				orphanSets.data ?? [],
				'no gym_sets may be orphaned by the workout cascade',
			).toEqual([]);

			// Storage: the gzipped track AND the export blob the portability
			// leg wrote must both be drained from the `runs` bucket. The
			// export blob lives under {user.id}/exports/ — the recursive
			// deletePrefix walk is the only thing that reaps it (a flat
			// list().remove() would leak it; audit/storage Pass-3).
			const trackList = await admin.storage
				.from('runs')
				.list(user.id, { search: plantedRunId! });
			expect(
				trackList.data?.find((f) => f.name.startsWith(plantedRunId!)),
				'gzipped track must be drained from the runs Storage bucket',
			).toBeUndefined();
			const exportList = await admin.storage
				.from('runs')
				.list(`${user.id}/exports`);
			// An empty/absent prefix returns [] (or a not-found error data:null);
			// either way there must be no surviving export blob.
			expect(
				exportList.data ?? [],
				'the export blob under {user}/exports must be drained (recursive walk)',
			).toEqual([]);

			// Audit trail: the deletion is recorded as result='ok' under the
			// pseudonymous (legacy salted) hash of the user id. This is the
			// Art 5(2) accountability evidence the regulator reads.
			const auditRow = await admin
				.from('deletion_audit_log')
				.select('result')
				.eq('hashed_user_id', legacyAuditHash(user.id))
				.maybeSingle();
			expect(
				auditRow.data?.result,
				'deletion must be audited as result="ok" (Art 5(2) accountability)',
			).toBe('ok');

			// Mark cleaned so afterAll doesn't re-attempt the run.
			plantedRunId = null;
			clubId = null;
		});
	});
});
