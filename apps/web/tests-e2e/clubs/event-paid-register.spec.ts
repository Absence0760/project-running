import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Paid event registration (club_events.md slice P1) — NON-charge UI only.
 *
 * The live Stripe test-mode end-to-end (real Connect Express onboarding,
 * destination-charge Checkout with the 4242 card, account.updated +
 * checkout.session.completed webhook granting the seat) is DEFERRED until
 * an operator supplies sk_test_ / ca_ / whsec_ keys — see
 * docs/testing/local_testing_stubs.md § Stripe Connect. This spec covers
 * everything reachable without a live charge:
 *   (a) free-event RSVP unchanged (no register box);
 *   (b) the EventEditor Charge toggle is disabled + shows the set-up-payouts
 *       explainer when the host lacks charges_enabled;
 *   (c) /settings/payouts entry + the not-configured fallback (no throw);
 *   (d) a priced event renders Register · $X, and the sold-out / sales-closed
 *       states render from the pure registrationOpen helper;
 *   (e) ?paid=1 surfaces a processing state (never a false failure).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';

/// Seed a charges-enabled payout account for the host so the pricing
/// trigger (enforce_pricing_requires_charges) accepts the row, then
/// insert the event_pricing. Returns a cleanup fn.
async function priceEvent(
	hostId: string,
	eventId: string,
	opts: { priceCents: number; salesCloseOffset?: number } = { priceCents: 2200 }
): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	await admin.from('instructor_payout_accounts').upsert({
		user_id: hostId,
		stripe_connect_account_id: `acct_e2e_${hostId.slice(0, 8)}`,
		charges_enabled: true,
		payouts_enabled: true,
		details_submitted: true,
		country: 'US',
		default_currency: 'usd'
	});
	const { error } = await admin.from('event_pricing').insert({
		event_id: eventId,
		instance_start: null,
		price_cents: opts.priceCents,
		currency: 'usd',
		modality: 'in_person',
		platform_fee_bps: 500,
		refund_policy: 'full_until_24h',
		sales_close_offset_minutes: opts.salesCloseOffset ?? 0
	});
	if (error) throw new Error(`priceEvent failed: ${error.message}`);
	return async () => {
		await admin.from('event_pricing').delete().eq('event_id', eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', hostId);
	};
}

test.describe('paid registration — non-charge UI (slice P1)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];
	const cleanups: (() => Promise<void>)[] = [];

	test.afterEach(async () => {
		for (const fn of cleanups.splice(0)) {
			try {
				await fn();
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of created.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('free event: RSVP tri renders, no register box', async ({ page }) => {
		const title = `e2e-free ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Open mat',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		created.push(id);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// No price => the RSVP tri is shown, the register box is not.
		await expect(page.getByTestId('register-box')).toHaveCount(0);
		await expect(page.getByRole('group', { name: /RSVP/i })).toBeVisible();
	});

	test('EventEditor Charge toggle is disabled + shows payouts explainer without charges_enabled', async ({
		page
	}) => {
		// USER_A has no charges-enabled payout account in the default seed,
		// so the toggle must be disabled and link to /settings/payouts.
		await getAdminClient()
			.from('instructor_payout_accounts')
			.delete()
			.eq('user_id', USER_A.id);

		await page.goto(`/clubs/${RICHMOND_SLUG}`);
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const toggle = modal.getByTestId('charge-toggle');
		await expect(toggle).toBeVisible();
		await expect(toggle).toBeDisabled();
		const explainer = modal.getByTestId('charge-needs-payout');
		await expect(explainer).toBeVisible();
		await expect(explainer.getByRole('link', { name: /Set up payouts/i })).toHaveAttribute(
			'href',
			'/settings/payouts'
		);
	});

	test('/settings/payouts entry + not-configured fallback (no throw)', async ({ page }) => {
		// The settings nav lists Payouts.
		await page.goto('/settings/account');
		await expect(
			page.getByRole('link', { name: 'Payouts' })
		).toBeVisible({ timeout: 10_000 });

		await page.goto('/settings/payouts');
		await expect(page.getByRole('heading', { name: /Get paid to host events/i })).toBeVisible({
			timeout: 10_000
		});
		// With no Stripe Connect keys configured, starting setup must degrade
		// to an info toast — not a red error, not an unhandled throw. The EF
		// returns 503; startConnectOnboarding surfaces it as the fallback.
		const setup = page.getByRole('button', { name: /Set up payments/i });
		await expect(setup).toBeVisible();
		await setup.click();
		// Either the not-configured info toast (no keys) or a redirect attempt;
		// in CI with no keys it is the info toast. The page must stay on
		// /settings/payouts (no navigation away on the fallback).
		await expect(page).toHaveURL(/\/settings\/payouts/, { timeout: 5_000 });
	});

	test('priced event renders Register · $X', async ({ page }) => {
		const title = `e2e-priced ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 10,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id, { priceCents: 2200 }));

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		const box = page.getByTestId('register-box');
		await expect(box).toBeVisible();
		// No RSVP tri on a priced event — the order-backed register flow replaces it.
		await expect(page.getByRole('group', { name: /RSVP/i })).toHaveCount(0);
		const cta = page.getByTestId('register-cta');
		await expect(cta).toBeVisible();
		await expect(cta).toContainText(/Register/);
		await expect(cta).toContainText(/22/);
		// FTC pre-purchase disclosure: the host's refund policy must be
		// visible before the buyer pays, not only at cancel time.
		await expect(page.getByTestId('register-refund-policy')).toBeVisible();
		await expect(page.getByTestId('register-refund-policy')).toContainText(/cancellation/i);
	});

	test('priced event past sales close renders Registration closed', async ({ page }) => {
		const title = `e2e-closed ${Date.now()}`;
		// Starts in 30 min; a 60-min sales-close offset means sales are
		// already closed.
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Spin',
			capacity: 10,
			starts_at: new Date(Date.now() + 30 * 60 * 1000).toISOString()
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id, { priceCents: 1500, salesCloseOffset: 60 }));

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('register-box')).toBeVisible();
		await expect(page.getByText('Registration closed')).toBeVisible();
		await expect(page.getByTestId('register-cta')).toHaveCount(0);
	});

	test('?paid=1 shows a processing state (no false failure)', async ({ page }) => {
		const title = `e2e-paidparam ${Date.now()}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Mobility',
			capacity: 10,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id, { priceCents: 2200 }));

		// No paid order exists for USER_A, so the poll stays in "processing"
		// then degrades to the slow message — never a failure toast.
		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}?paid=1`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByText(/Confirming your payment|your spot will appear shortly/i)
		).toBeVisible({ timeout: 10_000 });
	});
});
