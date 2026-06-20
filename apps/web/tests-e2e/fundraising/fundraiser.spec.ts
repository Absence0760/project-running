import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Charity fundraising pages (fundraising.md) — NON-charge UI only.
 *
 * The live Stripe test-mode donate round-trip (destination-charge Checkout with
 * the 4242 card + the webhook CAS pending→paid) is DEFERRED until an operator
 * supplies sk_test_ / whsec_ keys, exactly like paid events
 * (docs/testing/local_testing_stubs.md § Stripe Connect). This spec covers
 * everything reachable without a live charge:
 *   (a) owner sees the "Raise money for a charity" CTA on their own run, gated
 *       behind a charges-enabled payout account;
 *   (b) a fundraiser on a public run renders the thermometer (0% at start) +
 *       Donate CTA on the public /fundraisers/[id] page;
 *   (c) a planted PAID donation surfaces in the public feed + advances the
 *       thermometer (the webhook is the sole writer — we plant via service role);
 *   (d) a closed fundraiser shows the closed notice, no Donate CTA;
 *   (e) a fundraiser on a PRIVATE run is not reachable by a non-owner (the
 *       anchor-visibility RLS gate, fail-closed);
 *   (f) ?donated=1 surfaces the thank-you state (never a false failure).
 */

/// Seed a charges-enabled payout account so the requires-charges trigger
/// accepts the fundraiser. Mirrors priceEvent in event-paid-register.spec.ts.
async function enablePayouts(userId: string): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	await admin.from('instructor_payout_accounts').upsert({
		user_id: userId,
		stripe_connect_account_id: `acct_e2e_fr_${userId.slice(0, 8)}`,
		charges_enabled: true,
		payouts_enabled: true,
		details_submitted: true,
		country: 'US',
		default_currency: 'usd'
	});
	return async () => {
		await admin.from('instructor_payout_accounts').delete().eq('user_id', userId);
	};
}

/// Plant a fundraiser on a run via service role (bypasses the owner-owns-anchor
/// + requires-charges RLS/trigger the same way the EF does). Returns its id.
async function plantFundraiser(opts: {
	ownerId: string;
	runId: string;
	goalCents: number;
	status?: 'open' | 'closed';
}): Promise<string> {
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('fundraisers')
		.insert({
			owner_user_id: opts.ownerId,
			run_id: opts.runId,
			charity_name: 'Test Charity',
			title: `e2e-fundraiser ${Date.now()}`,
			goal_cents: opts.goalCents,
			currency: 'usd',
			status: opts.status ?? 'open'
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`plantFundraiser failed: ${error?.message}`);
	return data.id as string;
}

/// Plant a PAID donation via service role — the webhook is the sole writer in
/// production, but the test stands in for it so the public feed + totals show.
async function plantPaidDonation(opts: {
	fundraiserId: string;
	ownerId: string;
	amountCents: number;
	displayName?: string;
	message?: string;
}): Promise<void> {
	const admin = getAdminClient();
	const { error } = await admin.from('donations').insert({
		fundraiser_id: opts.fundraiserId,
		owner_user_id: opts.ownerId,
		display_name: opts.displayName ?? 'Jane D.',
		message: opts.message ?? null,
		amount_cents: opts.amountCents,
		currency: 'usd',
		status: 'paid',
		is_anonymous: false,
		paid_at: new Date().toISOString()
	});
	if (error) throw new Error(`plantPaidDonation failed: ${error.message}`);
}

const createdRuns: string[] = [];
const createdFundraisers: string[] = [];
const cleanups: (() => Promise<void>)[] = [];

async function cleanupAll(): Promise<void> {
	const admin = getAdminClient();
	for (const id of createdFundraisers.splice(0)) {
		try {
			await admin.from('fundraisers').delete().eq('id', id);
		} catch (_) {
			/* best-effort; donations cascade */
		}
	}
	for (const id of createdRuns.splice(0)) {
		try {
			await admin.from('runs').delete().eq('id', id);
		} catch (_) {
			/* best-effort */
		}
	}
	for (const fn of cleanups.splice(0)) {
		try {
			await fn();
		} catch (_) {
			/* best-effort */
		}
	}
}

test.describe('fundraising — non-charge UI (owner, USER_A)', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.afterEach(cleanupAll);

	test('owner sees the create CTA on their own run, gated on payouts', async ({ page }) => {
		await getAdminClient().from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		createdRuns.push(runId);

		await page.goto(`/runs/${runId}`);
		const cta = page.getByTestId('fundraiser-create-cta');
		await expect(cta).toBeVisible({ timeout: 10_000 });
		await cta.click();
		// Without a charges-enabled account the editor shows the payouts gate
		// and Save stays disabled.
		await expect(page.getByTestId('fundraiser-needs-payout')).toBeVisible();
		await expect(page.getByTestId('fundraiser-save')).toBeDisabled();
	});

	test('public page: thermometer at 0%, Donate CTA, empty feed', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		createdRuns.push(runId);
		const fr = await plantFundraiser({ ownerId: USER_A.id, runId, goalCents: 500_00 });
		createdFundraisers.push(fr);

		await page.goto(`/fundraisers/${fr}`);
		await expect(page.getByRole('progressbar')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('0%')).toBeVisible();
		await expect(page.getByTestId('donate-cta')).toBeVisible();
	});

	test('a planted paid donation shows in the feed + advances the thermometer', async ({
		page
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		createdRuns.push(runId);
		const fr = await plantFundraiser({ ownerId: USER_A.id, runId, goalCents: 100_00 });
		createdFundraisers.push(fr);
		await plantPaidDonation({
			fundraiserId: fr,
			ownerId: USER_A.id,
			amountCents: 50_00,
			displayName: 'Jane D.',
			message: 'Go get it!'
		});

		await page.goto(`/fundraisers/${fr}`);
		// 50 of 100 => 50%.
		await expect(page.getByText('50%')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Jane D.')).toBeVisible();
		await expect(page.getByText('Go get it!')).toBeVisible();
		await expect(page.getByText(/1 supporters/)).toBeVisible();
	});

	test('closed fundraiser: closed notice, no Donate CTA', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		createdRuns.push(runId);
		const fr = await plantFundraiser({
			ownerId: USER_A.id,
			runId,
			goalCents: 100_00,
			status: 'closed'
		});
		createdFundraisers.push(fr);

		await page.goto(`/fundraisers/${fr}`);
		await expect(page.getByText('This fundraiser is closed.')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('donate-cta')).toHaveCount(0);
	});

	test('?donated=1 shows the thank-you state (no false failure)', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		createdRuns.push(runId);
		const fr = await plantFundraiser({ ownerId: USER_A.id, runId, goalCents: 100_00 });
		createdFundraisers.push(fr);

		await page.goto(`/fundraisers/${fr}?donated=1`);
		await expect(page.getByTestId('donation-thanks')).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('fundraising — anchor-visibility RLS (non-owner, USER_B)', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.afterEach(cleanupAll);

	test('a fundraiser on a PRIVATE run is not reachable by a non-owner (fail-closed)', async ({
		page
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});
		createdRuns.push(runId);
		const fr = await plantFundraiser({ ownerId: USER_A.id, runId, goalCents: 100_00 });
		createdFundraisers.push(fr);

		await page.goto(`/fundraisers/${fr}`);
		// USER_B can't see a fundraiser on USER_A's private run.
		await expect(page.getByText("This fundraiser isn't available.")).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('donate-cta')).toHaveCount(0);
	});
});
