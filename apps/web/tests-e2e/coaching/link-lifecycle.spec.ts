import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Coach <-> athlete link lifecycle boundaries the existing coaching specs don't
 * cover. invite.spec/assign-plan.spec exercise minting, the roster list, plan
 * assignment, and the happy-path redemption; the gaps here are the ENDS of the
 * relationship and the access boundary that swings with it:
 *
 * 1. Coach revokes an athlete -> the review surface (/coaching/athletes/[id])
 *    becomes inaccessible (RLS, not just a hidden list row) and the link row is
 *    'ended'.
 * 2. Athlete leaves their coach from their own /coaching page -> the coach
 *    drops off "My coaches" and the link is 'ended'. (The whole athlete side is
 *    untested today.)
 * 3. An anonymous visitor to a valid invite URL gets the sign-in CTA, not an
 *    error or a redirect.
 * 4. A token that genuinely existed but was already redeemed shows the
 *    "Invite problem" card (distinct from invite.spec's fabricated-token case).
 * 5. Plan compliance: an assigned plan with mixed done/missed workouts renders
 *    the right counts + status pills on the review surface.
 */

const INVITE_TOKEN = 'e2elinklifecycletoken00000000001';

async function clearLinks() {
	const admin = getAdminClient();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
}

async function seedActiveLink() {
	await getAdminClient().from('coach_athletes').insert({
		coach_id: USER_B.id,
		athlete_id: USER_C_PRO.id,
		status: 'active',
		invite_token: INVITE_TOKEN,
		accepted_at: new Date().toISOString()
	});
}

function isoDate(offsetDays: number): string {
	const d = new Date();
	d.setDate(d.getDate() + offsetDays);
	return d.toISOString().slice(0, 10);
}

test.describe('/coaching — coach side (USER_B)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(clearLinks);
	test.afterEach(async () => {
		await getAdminClient().from('training_plans').delete().eq('user_id', USER_C_PRO.id);
		await clearLinks();
	});

	test('revoking an athlete locks the review surface and ends the link', async ({ page }) => {
		await seedActiveLink();

		// On-roster: the review surface loads.
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('heading', { level: 2, name: 'Recent runs' })).toBeVisible({
			timeout: 10_000
		});

		// Revoke from the roster.
		await page.goto('/coaching');
		await page.getByRole('button', { name: 'Remove' }).first().click();
		const dialog = page.locator('.modal', { hasText: 'Remove' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Remove' }).click();
		await expect(page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`)).toHaveCount(0, {
			timeout: 10_000
		});

		// The review surface is now refused — RLS, not just a hidden list row.
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('heading', { name: 'Not on your roster' })).toBeVisible({
			timeout: 10_000
		});

		// And the link row is ended (not deleted).
		const { data } = await getAdminClient()
			.from('coach_athletes')
			.select('status')
			.eq('coach_id', USER_B.id)
			.eq('athlete_id', USER_C_PRO.id)
			.single();
		expect(data?.status).toBe('ended');
	});

	test('an assigned plan shows compliance counts and done/missed pills', async ({ page }) => {
		await seedActiveLink();
		const admin = getAdminClient();

		const { data: plan } = await admin
			.from('training_plans')
			.insert({
				user_id: USER_C_PRO.id,
				name: 'E2E Compliance Plan',
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				start_date: isoDate(-7),
				end_date: isoDate(21),
				status: 'active',
				assigned_by_coach_id: USER_B.id
			})
			.select('id')
			.single();
		const planId = plan!.id as string;

		const { data: week } = await admin
			.from('plan_weeks')
			.insert({ plan_id: planId, week_index: 0, phase: 'base' })
			.select('id')
			.single();
		const weekId = week!.id as string;

		// One done (manually completed), two missed (past, not completed). Every
		// row sets manually_completed explicitly: a PostgREST batch insert unions
		// keys across the array and writes an explicit NULL — not the column
		// default — for any row that omits a key the batch otherwise carries,
		// which the NOT NULL constraint rejects.
		await admin.from('plan_workouts').insert([
			{ week_id: weekId, scheduled_date: isoDate(-2), kind: 'easy', manually_completed: true },
			{ week_id: weekId, scheduled_date: isoDate(-3), kind: 'easy', manually_completed: false },
			{ week_id: weekId, scheduled_date: isoDate(-4), kind: 'easy', manually_completed: false }
		]);

		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('heading', { level: 2, name: 'Plan compliance' })).toBeVisible({
			timeout: 10_000
		});

		// The plan is badged as ours and the compliance roll-up is correct.
		await expect(page.getByText('Assigned by you')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('1/3 done')).toBeVisible();
		await expect(page.getByText('2 missed')).toBeVisible();

		// Both status pills render in the focus list.
		await expect(page.locator('.status-pill.status-done').first()).toBeVisible();
		await expect(page.locator('.status-pill.status-missed').first()).toBeVisible();
	});
});

test.describe('/coaching — athlete side (USER_C_PRO)', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(clearLinks);
	test.afterEach(clearLinks);

	test('an athlete leaves their coach; the coach drops off and the link ends', async ({ page }) => {
		await seedActiveLink();

		await page.goto('/coaching');
		await expect(page.getByRole('heading', { level: 2, name: 'My coaches' })).toBeVisible({
			timeout: 10_000
		});
		const coachLink = page.locator(`a[href="/u/${USER_B.id}"]`);
		await expect(coachLink).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Leave' }).first().click();
		const dialog = page.locator('.modal', { hasText: 'Leave' });
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Leave' }).click();

		await expect(coachLink).toHaveCount(0, { timeout: 10_000 });

		const { data } = await getAdminClient()
			.from('coach_athletes')
			.select('status')
			.eq('coach_id', USER_B.id)
			.eq('athlete_id', USER_C_PRO.id)
			.single();
		expect(data?.status).toBe('ended');
	});
});

test.describe('/coaching/accept/[token] — anonymous visitor', () => {
	// No storageState — a logged-out visitor. The not-authed branch is decided
	// before any redemption, so the token need not be seeded for this path.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a logged-out visitor sees the sign-in CTA, not an error or redirect', async ({ page }) => {
		await page.goto(`/coaching/accept/${INVITE_TOKEN}`);

		await expect(
			page.getByRole('heading', { name: 'Sign in to accept this coaching invite' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('link', { name: 'Sign in' })).toBeVisible();
		await expect(page.getByRole('link', { name: 'Create a free account' })).toBeVisible();
		await expect(page).toHaveURL(new RegExp(`/coaching/accept/${INVITE_TOKEN}`));
	});
});

test.describe('/coaching/accept/[token] — already redeemed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(clearLinks);

	test('redeeming an already-active invite shows the invite-problem card', async ({ page }) => {
		await clearLinks();
		// The token exists but is already active (consumed by USER_C_PRO); a
		// third user (USER_A) trying to redeem it hits "already redeemed".
		await seedActiveLink();

		await page.goto(`/coaching/accept/${INVITE_TOKEN}`);
		await expect(page.getByRole('heading', { name: 'Invite problem' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('link', { name: 'Go to coaching' })).toBeVisible();
		await expect(page).toHaveURL(/\/coaching\/accept\//);

		// The existing link is untouched — USER_A did not get linked.
		const { data } = await getAdminClient()
			.from('coach_athletes')
			.select('athlete_id, status')
			.eq('coach_id', USER_B.id);
		expect(data).toHaveLength(1);
		expect(data![0].athlete_id).toBe(USER_C_PRO.id);
		expect(data![0].status).toBe('active');
	});
});
