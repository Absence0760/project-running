import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Depth coverage for the coach <-> athlete relationship that the existing
 * coaching specs (invite / assign-plan / load-error / link-lifecycle) don't
 * reach. Those cover: minting + the roster list + revoke->review-locked +
 * athlete-leave + anon accept CTA + already-redeemed token + the happy-path
 * done/missed compliance pills + plan assignment. The genuinely-uncovered
 * surfaces pinned here:
 *
 * 1. MULTI-ATHLETE roster — a coach with TWO active athletes; both rows render
 *    and link to their own review surface, and removing one leaves the other.
 * 2. redeem_coach_invite ERROR branches the RPC raises by name — self-coaching
 *    ('cannot coach yourself') and duplicate-link ('already linked to this
 *    coach') — surfaced on the public accept page as the "Invite problem" card.
 * 3. COACH RUN-REVIEW depth — an athlete with a MIX of public + private runs;
 *    the review surface lists several, with the private one flagged Private
 *    (the `active coach reads athlete runs` RLS policy).
 * 4. COMPLIANCE skipped-workout handling — a SKIPPED workout (skipped_at set)
 *    is off the books: excluded from the X/Y-done denominator and NOT counted
 *    as missed, distinct from a genuinely-missed past workout.
 * 5. ATHLETE consumption — a coach-assigned active plan is the athlete's own
 *    active plan: it appears on /plans and the athlete can open /plans/[id]
 *    (owner reads their own plan weeks + workouts).
 */

function isoDate(offsetDays: number): string {
	const d = new Date();
	d.setDate(d.getDate() + offsetDays);
	return d.toISOString().slice(0, 10);
}

// ─────────────────────────── 1. Multi-athlete roster ───────────────────────────

test.describe('/coaching — a coach with two active athletes (USER_B)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	// USER_C_PRO (Morgan) + USER_A (Jared) are both active athletes of USER_B.
	const TOKEN_C = 'e2edepthrostertokenmorgan0000001';
	const TOKEN_A = 'e2edepthrostertokenjared00000001';

	async function clearRoster() {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_A.id);
	}

	test.beforeEach(async () => {
		await clearRoster();
		await getAdminClient()
			.from('coach_athletes')
			.insert([
				{
					coach_id: USER_B.id,
					athlete_id: USER_C_PRO.id,
					status: 'active',
					invite_token: TOKEN_C,
					accepted_at: new Date().toISOString()
				},
				{
					coach_id: USER_B.id,
					athlete_id: USER_A.id,
					status: 'active',
					invite_token: TOKEN_A,
					accepted_at: new Date().toISOString()
				}
			]);
	});

	test.afterEach(clearRoster);

	test('both athletes render, each links to its own review surface, removing one keeps the other', async ({
		page
	}) => {
		await page.goto('/coaching');
		await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
			timeout: 10_000
		});

		// Both athletes appear, each name linking to its OWN /coaching/athletes/[id].
		const morganLink = page.locator(`a.link-name[href="/coaching/athletes/${USER_C_PRO.id}"]`);
		const jaredLink = page.locator(`a.link-name[href="/coaching/athletes/${USER_A.id}"]`);
		await expect(morganLink).toBeVisible({ timeout: 10_000 });
		await expect(jaredLink).toBeVisible({ timeout: 10_000 });
		await expect(morganLink).toHaveText('Morgan Lee');
		await expect(jaredLink).toHaveText('Jared Howard');

		// Two athlete rows, so two Remove buttons.
		await expect(page.getByRole('button', { name: 'Remove' })).toHaveCount(2);

		// Remove Morgan specifically (scope to her row), confirm in the dialog.
		const morganRow = page.locator('.link-row', { hasText: 'Morgan Lee' });
		await morganRow.getByRole('button', { name: 'Remove' }).click();
		const dialog = page.locator('.modal', { hasText: 'Remove' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Remove' }).click();

		// Morgan's row goes; Jared's stays — a per-athlete end, not a roster wipe.
		await expect(morganLink).toHaveCount(0, { timeout: 10_000 });
		await expect(jaredLink).toBeVisible();

		// DB: Morgan ended, Jared still active.
		const { data } = await getAdminClient()
			.from('coach_athletes')
			.select('athlete_id, status')
			.eq('coach_id', USER_B.id)
			.in('athlete_id', [USER_C_PRO.id, USER_A.id]);
		const byAthlete = new Map((data ?? []).map((r) => [r.athlete_id, r.status]));
		expect(byAthlete.get(USER_C_PRO.id)).toBe('ended');
		expect(byAthlete.get(USER_A.id)).toBe('active');
	});
});

// ───────────────────── 2. redeem_coach_invite error branches ─────────────────────

test.describe('/coaching/accept/[token] — redeem_coach_invite error branches', () => {
	async function clearLinks() {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_A.id);
	}

	test.describe('self-coaching is refused', () => {
		// USER_B mints an invite and tries to redeem THEIR OWN token: the RPC
		// raises 'cannot coach yourself' and the accept page shows the problem
		// card rather than linking a coach to themselves.
		test.use({ storageState: USER_B.storageStatePath });
		const TOKEN = 'e2edepthselfcoachtoken0000000001';

		test.beforeEach(async () => {
			await clearLinks();
			await getAdminClient().from('coach_athletes').insert({
				coach_id: USER_B.id,
				status: 'pending',
				invite_token: TOKEN
			});
		});
		test.afterEach(clearLinks);

		test("the coach redeeming their own token sees 'cannot coach yourself'", async ({ page }) => {
			await page.goto(`/coaching/accept/${TOKEN}`);
			await expect(page.getByRole('heading', { name: 'Invite problem' })).toBeVisible({
				timeout: 10_000
			});
			await expect(page.getByRole('alert')).toContainText(/cannot coach yourself/i);
			await expect(page).toHaveURL(/\/coaching\/accept\//);

			// The invite stays pending + athlete-less — self-redemption did not consume it.
			const { data } = await getAdminClient()
				.from('coach_athletes')
				.select('status, athlete_id')
				.eq('invite_token', TOKEN)
				.single();
			expect(data?.status).toBe('pending');
			expect(data?.athlete_id).toBeNull();
		});
	});

	test.describe('a duplicate link from the same coach is refused', () => {
		// USER_C_PRO is already active under USER_B, then tries to redeem a
		// SECOND fresh invite from the same coach: 'already linked to this coach'.
		test.use({ storageState: USER_C_PRO.storageStatePath });
		const ACTIVE_TOKEN = 'e2edepthdupactivetoken0000000001';
		const SECOND_TOKEN = 'e2edepthdupsecondtoken0000000001';

		test.beforeEach(async () => {
			await clearLinks();
			await getAdminClient()
				.from('coach_athletes')
				.insert([
					{
						coach_id: USER_B.id,
						athlete_id: USER_C_PRO.id,
						status: 'active',
						invite_token: ACTIVE_TOKEN,
						accepted_at: new Date().toISOString()
					},
					{ coach_id: USER_B.id, status: 'pending', invite_token: SECOND_TOKEN }
				]);
		});
		test.afterEach(clearLinks);

		test("an already-linked athlete redeeming a second token sees 'already linked to this coach'", async ({
			page
		}) => {
			await page.goto(`/coaching/accept/${SECOND_TOKEN}`);
			await expect(page.getByRole('heading', { name: 'Invite problem' })).toBeVisible({
				timeout: 10_000
			});
			await expect(page.getByRole('alert')).toContainText(/already linked to this coach/i);

			// The second invite is untouched (still pending) and the athlete still
			// has exactly one live link to this coach — the original active one.
			const admin = getAdminClient();
			const { data: second } = await admin
				.from('coach_athletes')
				.select('status, athlete_id')
				.eq('invite_token', SECOND_TOKEN)
				.single();
			expect(second?.status).toBe('pending');
			expect(second?.athlete_id).toBeNull();

			const { data: live } = await admin
				.from('coach_athletes')
				.select('invite_token, status')
				.eq('coach_id', USER_B.id)
				.eq('athlete_id', USER_C_PRO.id);
			expect(live).toHaveLength(1);
			expect(live![0].invite_token).toBe(ACTIVE_TOKEN);
			expect(live![0].status).toBe('active');
		});
	});
});

// ───────────────────── 3. Coach run-review: public + private mix ─────────────────────

test.describe('/coaching/athletes/[id] — run review lists public + private runs (USER_B)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const TOKEN = 'e2edepthrunreviewtoken0000000001';
	const seededRunIds: string[] = [];

	async function clearLinks() {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
	}

	test.beforeEach(async () => {
		await clearLinks();
		const admin = getAdminClient();
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: TOKEN,
			accepted_at: new Date().toISOString()
		});
		// Three athlete-owned runs: two public, one PRIVATE. The coach reads all
		// three via the `active coach reads athlete runs` policy (decisions §98).
		// Dated to NOW so they sort above the athlete's fixed-date seed runs and
		// land in the "recent" window the review surface shows.
		const base = Date.now();
		const rows = [
			{ started_at: new Date(base - 60_000).toISOString(), distance_m: 8000, duration_s: 2400, is_public: true },
			{ started_at: new Date(base - 120_000).toISOString(), distance_m: 5000, duration_s: 1500, is_public: false },
			{ started_at: new Date(base - 180_000).toISOString(), distance_m: 12000, duration_s: 3900, is_public: true }
		].map((r) => ({
			user_id: USER_C_PRO.id,
			source: 'app' as const,
			metadata: { activity_type: 'run' },
			...r
		}));
		const ins = await admin.from('runs').insert(rows).select('id');
		for (const r of ins.data ?? []) seededRunIds.push(r.id as string);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (seededRunIds.length) await admin.from('runs').delete().in('id', seededRunIds);
		seededRunIds.length = 0;
		await clearLinks();
	});

	test('the review surface lists multiple recent runs, the private one flagged Private', async ({
		page
	}) => {
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('heading', { level: 2, name: 'Recent runs' })).toBeVisible({
			timeout: 10_000
		});

		// The athlete's runs render (public + private alike). The athlete carries
		// its own seed runs too, so assert the surface lists at least the three we
		// seeded rather than an exact total.
		const privateBadges = page.locator('.run-list .r-private');
		await expect(privateBadges.first()).toBeVisible({ timeout: 10_000 });
		await expect(privateBadges.first()).toHaveText('Private');
		expect(await page.locator('.run-list .run-row').count()).toBeGreaterThanOrEqual(3);
	});
});

// ───────────────────── 4. Compliance: skipped is off the books ─────────────────────

test.describe('/coaching/athletes/[id] — a skipped workout leaves the denominator (USER_B)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const TOKEN = 'e2edepthskippedtoken000000000001';

	async function clean() {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		await admin.from('training_plans').delete().eq('user_id', USER_C_PRO.id);
	}

	test.beforeEach(async () => {
		await clean();
		const admin = getAdminClient();
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: TOKEN,
			accepted_at: new Date().toISOString()
		});

		const { data: plan } = await admin
			.from('training_plans')
			.insert({
				user_id: USER_C_PRO.id,
				name: 'E2E Skipped Plan',
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				start_date: isoDate(-14),
				end_date: isoDate(14),
				status: 'active',
				assigned_by_coach_id: USER_B.id
			})
			.select('id')
			.single();

		const { data: week } = await admin
			.from('plan_weeks')
			.insert({ plan_id: plan!.id, week_index: 0, phase: 'base' })
			.select('id')
			.single();

		// Four real workouts (no rest), so the skipped row is the only thing that
		// moves between the buggy and correct counts:
		//   - done (manually_completed)        : isoDate(-5)
		//   - missed (past, not done/skipped)  : isoDate(-4)
		//   - SKIPPED (past, skipped_at set)   : isoDate(-3)
		//   - upcoming (future)                : isoDate(+3)
		// `manually_completed` is set on every row of the batch (PostgREST unions
		// keys across the array and writes explicit NULL for omitted keys, which
		// the NOT NULL constraint rejects). Skipped is off the books: the done
		// denominator drops it (3 countable, not 4 -> "1/3 done") and it is NOT a
		// miss ("1 missed", not 2). fetchAthletePlanOverview.completionPct already
		// excludes it; this asserts the page's X/Y-done + N-missed roll-up agrees.
		await admin.from('plan_workouts').insert([
			{
				week_id: week!.id,
				scheduled_date: isoDate(-5),
				kind: 'easy',
				manually_completed: true,
				skipped_at: null
			},
			{
				week_id: week!.id,
				scheduled_date: isoDate(-4),
				kind: 'easy',
				manually_completed: false,
				skipped_at: null
			},
			{
				week_id: week!.id,
				scheduled_date: isoDate(-3),
				kind: 'easy',
				manually_completed: false,
				skipped_at: new Date().toISOString()
			},
			{
				week_id: week!.id,
				scheduled_date: isoDate(3),
				kind: 'easy',
				manually_completed: false,
				skipped_at: null
			}
		]);
	});

	test.afterEach(clean);

	test('a skipped workout is excluded from done count and not counted as missed', async ({
		page
	}) => {
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('heading', { level: 2, name: 'Plan compliance' })).toBeVisible({
			timeout: 10_000
		});

		// Done denominator excludes the skipped workout: 3 countable (not 4), 1
		// done -> "1/3 done". The page's X/Y-done roll-up must agree with the
		// skipped-aware completionPct fetchAthletePlanOverview computes.
		await expect(page.getByText('1/3 done')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('1/4 done')).toHaveCount(0);

		// Exactly one genuinely-missed workout — the skipped one is NOT a miss.
		await expect(page.getByText('1 missed')).toBeVisible();
		await expect(page.getByText('2 missed')).toHaveCount(0);
	});
});

// ───────────────────── 5. Athlete consumption of an assigned plan ─────────────────────

test.describe('/plans — an assigned plan is the athlete own active plan (USER_C_PRO)', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	const TOKEN = 'e2edepthathleteconsumetoken00001';
	const PLAN_NAME = 'E2E Coach-Assigned Marathon Block';

	async function clean() {
		const admin = getAdminClient();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		await admin.from('training_plans').delete().eq('user_id', USER_C_PRO.id);
	}

	let planId = '';

	test.beforeEach(async () => {
		await clean();
		const admin = getAdminClient();
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: TOKEN,
			accepted_at: new Date().toISOString()
		});

		// An ATHLETE-OWNED active plan whose provenance is the coach — exactly the
		// shape assign_plan_to_athlete produces (user_id = athlete, status =
		// active, assigned_by_coach_id = coach).
		const { data: plan } = await admin
			.from('training_plans')
			.insert({
				user_id: USER_C_PRO.id,
				name: PLAN_NAME,
				goal_event: 'distance_full',
				goal_distance_m: 42195,
				start_date: isoDate(-3),
				end_date: isoDate(25),
				status: 'active',
				assigned_by_coach_id: USER_B.id
			})
			.select('id')
			.single();
		planId = plan!.id as string;

		const { data: week } = await admin
			.from('plan_weeks')
			.insert({ plan_id: planId, week_index: 0, phase: 'base' })
			.select('id')
			.single();
		await admin.from('plan_workouts').insert([
			{ week_id: week!.id, scheduled_date: isoDate(-1), kind: 'easy', manually_completed: false },
			{ week_id: week!.id, scheduled_date: isoDate(1), kind: 'long', manually_completed: false }
		]);
	});

	test.afterEach(clean);

	test('the assigned plan appears on /plans and the athlete can open its detail', async ({
		page
	}) => {
		await page.goto('/plans');
		// The plan card links to its detail by name (the athlete owns it, so it
		// flows through the normal "users own their plans" read).
		const planCard = page.locator(`a.card[href="/plans/${planId}"]`);
		await expect(planCard).toBeVisible({ timeout: 10_000 });
		await expect(planCard).toContainText(PLAN_NAME);
		// Badged active.
		await expect(planCard.locator('.badge.status-active')).toBeVisible();

		// The athlete opens their own plan: owner reads weeks + workouts, so the
		// detail page renders the plan name as its heading (not the not-found card).
		await planCard.click();
		await page.waitForURL(new RegExp(`/plans/${planId}$`), { timeout: 10_000 });
		await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: 'Plan not found' })).toHaveCount(0);
	});
});
