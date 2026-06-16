import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Coach <-> athlete roster lifecycle JOURNEY, told from the angle the existing
 * coaching specs leave open: the CONSENT-GATED PRIVATE-RUN VISIBILITY TIER
 * (RLS migration 20261103_001 / decisions §98) and what happens to it when the
 * link is revoked.
 *
 * The existing coaching-roster-journey.spec already walks mint -> accept ->
 * review -> revoke with the two SEEDED users, but it only asserts that SOME runs
 * render on the review surface and that the surface is refused after revoke. It
 * never distinguishes a public run from a private one, so it can't catch the
 * specific failure that the §98 policy is the only guard against: a coach
 * reading an athlete's PRIVATE runs (the `public_runs` view is is-public-only,
 * so the "active coach reads athlete runs" base-table policy is the SOLE path to
 * private rows). If revoke failed to sever that path, a private run would stay
 * visible to an ex-coach — a real, silent data leak.
 *
 * So this journey pins exactly that boundary, end to end:
 *   1. A coach mints an invite link in the UI; the token is captured off the
 *      clipboard (the only UI-reachable source — mintInvite copies it, the DOM
 *      never renders it) and cross-checked against the DB.
 *   2. The athlete redeems it in a SECOND browser context (a genuine second
 *      signed-in user, not a tab of the coach).
 *   3. The coach opens /coaching/athletes/[id] and sees BOTH the athlete's
 *      public AND private runs — with the `.r-private` badge on the private one
 *      ("Private", visible-to-you-as-their-coach) — proving the §98 tier is
 *      live, plus the assigned-plan compliance roll-up renders real counts.
 *   4. The coach revokes the link; the journey then proves the private-run
 *      visibility is GONE on both sides: the review surface is refused (RLS, not
 *      a hidden row), AND the athlete's own /coaching page drops the coach.
 *
 * Ephemeral saga users (coach + athlete), per the two-context saga pattern, so
 * the spec leaves no seeded-user state behind — deleteSagaUsers CASCADE-cleans
 * the runs + the coach_athletes rows in one shot. createCoachInvite is a plain
 * INSERT with no rate-limit trigger, so no reset is needed between runs.
 */

test.describe('coach <-> athlete roster lifecycle: private-run visibility tier (invite -> accept -> review -> revoke)', () => {
	test.describe.configure({ timeout: 120_000 });

	let users: SagaUser[] = [];
	let coach: SagaUser;
	let athlete: SagaUser;

	// The athlete's two runs: one public, one private. Both are now()-relative so
	// they land in the newest-first review window. Public is the longer of the two
	// so its distance is distinguishable on the page.
	const PUBLIC_RUN_DISTANCE_M = 9000;
	const PRIVATE_RUN_DISTANCE_M = 5000;
	let publicRunId = '';
	let privateRunId = '';
	let planId = '';

	function isoDate(offsetDays: number): string {
		const d = new Date();
		d.setDate(d.getDate() + offsetDays);
		return d.toISOString().slice(0, 10);
	}

	test.beforeAll(async () => {
		users = await createSagaUsers(2, { displayNames: ['Saga Coach', 'Saga Athlete'] });
		[coach, athlete] = users;

		// The athlete's runs. The private one is the load-bearing fixture: a coach
		// can only ever reach it through the §98 base-table policy.
		publicRunId = await insertRun({
			user_id: athlete.id,
			started_at: new Date(Date.now() - 2 * 86_400_000).toISOString(),
			duration_s: 2700,
			distance_m: PUBLIC_RUN_DISTANCE_M,
			is_public: true
		});
		privateRunId = await insertRun({
			user_id: athlete.id,
			started_at: new Date(Date.now() - 1 * 86_400_000).toISOString(),
			duration_s: 1500,
			distance_m: PRIVATE_RUN_DISTANCE_M,
			is_public: false
		});

		// An active plan with one done + two missed workouts so the plan-compliance
		// roll-up renders real numbers (1/3 done, 2 missed) on the review surface.
		const admin = getAdminClient();
		const { data: plan, error: planErr } = await admin
			.from('training_plans')
			.insert({
				user_id: athlete.id,
				name: 'Saga Compliance Plan',
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				start_date: isoDate(-7),
				end_date: isoDate(21),
				status: 'active'
			})
			.select('id')
			.single();
		if (planErr || !plan) throw new Error(`plan seed failed: ${planErr?.message}`);
		planId = plan.id as string;

		const { data: week, error: weekErr } = await admin
			.from('plan_weeks')
			.insert({ plan_id: planId, week_index: 0, phase: 'base' })
			.select('id')
			.single();
		if (weekErr || !week) throw new Error(`week seed failed: ${weekErr?.message}`);

		// Every row sets manually_completed explicitly — a PostgREST batch insert
		// unions keys across the array and writes an explicit NULL for any row that
		// omits a key the batch otherwise carries, which the NOT NULL column rejects.
		const { error: woErr } = await admin.from('plan_workouts').insert([
			{ week_id: week.id, scheduled_date: isoDate(-2), kind: 'easy', manually_completed: true },
			{ week_id: week.id, scheduled_date: isoDate(-3), kind: 'easy', manually_completed: false },
			{ week_id: week.id, scheduled_date: isoDate(-4), kind: 'easy', manually_completed: false }
		]);
		if (woErr) throw new Error(`workouts seed failed: ${woErr.message}`);
	});

	test.afterAll(async () => {
		// deleteSagaUsers CASCADE-strips runs + coach_athletes; OWNER_TABLES sweeps
		// the training_plans (and their plan_weeks/plan_workouts via FK cascade).
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('a coach links an athlete, reviews their public AND private runs, then revoke severs private-run visibility', async ({
		browser
	}) => {
		const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7777';

		// The coach owns the primary context; the athlete acts in a second one.
		const coachContext: BrowserContext = await browser.newContext({
			baseURL,
			storageState: coach.storageStatePath
		});
		await coachContext.grantPermissions(['clipboard-read', 'clipboard-write']);
		const coachPage: Page = await coachContext.newPage();

		let athleteContext: BrowserContext | null = null;
		let inviteToken = '';

		try {
			await test.step('coach mints an invite link and captures the token', async () => {
				await coachPage.goto('/coaching');
				await expect(
					coachPage.getByRole('heading', { level: 1, name: 'Coaching' })
				).toBeVisible({ timeout: 15_000 });
				// Clean roster: a fresh saga coach has no athletes and no pending invite.
				await expect(coachPage.getByText('Pending invite')).toHaveCount(0);
				await expect(coachPage.getByText('No athletes yet')).toBeVisible();

				await coachPage.getByRole('button', { name: 'Invite an athlete' }).click();

				// The pending-invite row appears once the INSERT lands.
				await expect(coachPage.getByText('Pending invite')).toBeVisible({ timeout: 10_000 });

				// mintInvite copies the /coaching/accept/<token> URL to the clipboard;
				// the DOM never renders the token. Read it back, then cross-check the DB
				// so a clipboard hiccup fails loudly instead of redeeming a bogus token.
				const clipText = await coachPage.evaluate(() => navigator.clipboard.readText());
				const match = clipText.match(/\/coaching\/accept\/([0-9a-f]+)/i);
				expect(match, `invite URL not on clipboard, got: ${clipText}`).not.toBeNull();
				inviteToken = match![1];
				expect(inviteToken.length).toBeGreaterThan(0);

				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('invite_token, status, athlete_id')
					.eq('coach_id', coach.id)
					.is('athlete_id', null)
					.single();
				expect(data?.invite_token).toBe(inviteToken);
				expect(data?.status).toBe('pending');
			});

			await test.step('athlete redeems the invite in a second context', async () => {
				athleteContext = await browser.newContext({
					baseURL,
					storageState: athlete.storageStatePath
				});
				const athletePage = await athleteContext.newPage();

				// The public accept landing redeems via redeem_coach_invite and, on
				// success, redirects the signed-in athlete to /coaching.
				await athletePage.goto(`/coaching/accept/${inviteToken}`);
				await athletePage.waitForURL(/\/coaching$/, { timeout: 15_000 });
				await expect(
					athletePage.getByRole('heading', { level: 2, name: 'My coaches' })
				).toBeVisible({ timeout: 10_000 });
				await expect(athletePage.locator(`a[href="/u/${coach.id}"]`)).toBeVisible({
					timeout: 10_000
				});

				// The link is active in the DB — the invite was consumed by THIS athlete.
				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('status, athlete_id')
					.eq('coach_id', coach.id)
					.eq('invite_token', inviteToken)
					.single();
				expect(data?.status).toBe('active');
				expect(data?.athlete_id).toBe(athlete.id);

				await athletePage.close();
			});

			await test.step('coach sees the new athlete on the roster', async () => {
				await coachPage.goto('/coaching');
				await expect(
					coachPage.getByRole('heading', { level: 1, name: 'Coaching' })
				).toBeVisible({ timeout: 10_000 });
				await expect(coachPage.getByText('Pending invite')).toHaveCount(0, { timeout: 10_000 });
				await expect(
					coachPage.locator(`a.link-name[href="/coaching/athletes/${athlete.id}"]`)
				).toHaveText('Saga Athlete');
			});

			await test.step('review surface shows BOTH public and private runs (§98 tier live)', async () => {
				await coachPage.goto(`/coaching/athletes/${athlete.id}`);
				await expect(
					coachPage.getByRole('heading', { level: 2, name: 'Recent runs' })
				).toBeVisible({ timeout: 10_000 });

				// Both runs render — the private one is reachable ONLY via the §98
				// base-table policy, so its presence proves the coach-read tier is live.
				await expect(coachPage.getByText('No runs recorded yet.')).toHaveCount(0);
				const rows = coachPage.locator('.run-list .run-row');
				await expect(rows).toHaveCount(2);

				// Exactly one row carries the private badge — the private run — and it
				// reads "Private" with the coach-scoped tooltip. The public run has none.
				const privateBadges = coachPage.locator('.run-list .run-row .r-private');
				await expect(privateBadges).toHaveCount(1);
				await expect(privateBadges.first()).toHaveText('Private');
				await expect(privateBadges.first()).toHaveAttribute(
					'title',
					'Private run — visible to you as their coach'
				);

				// Belt-and-braces at the data layer: both run ids are the athlete's two
				// seeded runs (one public, one private), confirming the page isn't
				// silently dropping the private row before render.
				const { data: visible } = await getAdminClient()
					.from('runs')
					.select('id, is_public')
					.eq('user_id', athlete.id);
				const ids = (visible ?? []).map((r) => r.id).sort();
				expect(ids).toEqual([publicRunId, privateRunId].sort());
				expect((visible ?? []).filter((r) => r.is_public === false)).toHaveLength(1);
			});

			await test.step('plan compliance renders real counts on the review surface', async () => {
				await expect(
					coachPage.getByRole('heading', { level: 2, name: 'Plan compliance' })
				).toBeVisible({ timeout: 10_000 });
				await expect(coachPage.getByText('Saga Compliance Plan')).toBeVisible();
				await expect(coachPage.getByText('1/3 done')).toBeVisible();
				await expect(coachPage.getByText('2 missed')).toBeVisible();
				await expect(coachPage.locator('.status-pill.status-done').first()).toBeVisible();
				await expect(coachPage.locator('.status-pill.status-missed').first()).toBeVisible();
			});

			await test.step('coach revokes the link; the review surface is refused', async () => {
				await coachPage.goto('/coaching');
				const athleteLink = coachPage.locator(`a[href="/coaching/athletes/${athlete.id}"]`);
				await expect(athleteLink.first()).toBeVisible({ timeout: 10_000 });

				// Remove routes through the shared ConfirmDialog.
				await coachPage.getByRole('button', { name: 'Remove' }).first().click();
				const dialog = coachPage.locator('.modal', { hasText: 'Remove' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Remove' }).click();
				await expect(athleteLink).toHaveCount(0, { timeout: 10_000 });

				// The review surface is now refused — RLS, not just a hidden list row.
				await coachPage.goto(`/coaching/athletes/${athlete.id}`);
				await expect(
					coachPage.getByRole('heading', { name: 'Not on your roster' })
				).toBeVisible({ timeout: 10_000 });
				// And crucially: the private run is NOT rendered anywhere on the refused
				// page. The "Recent runs" section never mounts when notOnRoster is true.
				await expect(
					coachPage.getByRole('heading', { level: 2, name: 'Recent runs' })
				).toHaveCount(0);
				await expect(coachPage.locator('.run-list .run-row .r-private')).toHaveCount(0);

				// The link row is ended (not deleted) — `is_active_coach_of` only
				// matches 'active', so this severs the §98 private-run visibility.
				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('status')
					.eq('coach_id', coach.id)
					.eq('athlete_id', athlete.id)
					.single();
				expect(data?.status).toBe('ended');
			});

			await test.step('the athlete no longer sees the coach (link ended on both sides)', async () => {
				const athletePage = await athleteContext!.newPage();
				await athletePage.goto('/coaching');
				await expect(
					athletePage.getByRole('heading', { level: 1, name: 'Coaching' })
				).toBeVisible({ timeout: 10_000 });
				await expect(athletePage.locator(`a[href="/u/${coach.id}"]`)).toHaveCount(0, {
					timeout: 10_000
				});
				await expect(athletePage.getByText("You're not linked to any coach yet.")).toBeVisible({
					timeout: 10_000
				});
				await athletePage.close();
			});
		} finally {
			if (athleteContext) await athleteContext.close();
			await coachContext.close();
		}
	});
});
