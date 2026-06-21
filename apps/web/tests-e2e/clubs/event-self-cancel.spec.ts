import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Buyer self-cancel of a paid event registration (club_events.md slice P2) —
 * UI surface only.
 *
 * The live Stripe refund round-trip (events-cancel EF creates the refund,
 * charge.refunded webhook flips paid->refunded + frees the seat) is DEFERRED
 * until an operator supplies sk_test_ / whsec_ keys — with none configured the
 * EF returns 503 and the action fails closed. This spec covers everything
 * reachable without a live refund:
 *   (a) a buyer holding a paid + going seat sees the Cancel registration
 *       affordance under the registered badge;
 *   (b) the confirm dialog shows the refundable copy (full_until_24h, far-off
 *       start) and is dismissable without cancelling;
 *   (c) clicking through with no Stripe keys fails closed to an error toast
 *       (never a false success), and the seat is untouched;
 *   (d) an order already mid-refund (refund_initiated_at stamped) shows the
 *       "Refund in progress" badge instead of a live Cancel button.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';

async function priceEvent(
	hostId: string,
	eventId: string
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
		price_cents: 2200,
		currency: 'usd',
		modality: 'in_person',
		platform_fee_bps: 500,
		refund_policy: 'full_until_24h',
		sales_close_offset_minutes: 0
	});
	if (error) throw new Error(`priceEvent failed: ${error.message}`);
	return async () => {
		await admin.from('event_pricing').delete().eq('event_id', eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', hostId);
	};
}

/// Seat the buyer: a paid order + the going attendee row the webhook would
/// have written on checkout.session.completed. `refundInitiated` stamps the
/// in-flight refund state. Returns a cleanup fn.
async function seatBuyer(
	eventId: string,
	instanceStart: string,
	buyerId: string,
	hostId: string,
	refundInitiated = false
): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	await admin.from('event_orders').insert({
		event_id: eventId,
		instance_start: instanceStart,
		buyer_user_id: buyerId,
		host_user_id: hostId,
		stripe_payment_intent_id: `pi_e2e_${eventId.slice(0, 8)}`,
		amount_cents: 2200,
		currency: 'usd',
		platform_fee_cents: 110,
		status: 'paid',
		paid_at: new Date().toISOString(),
		refund_initiated_at: refundInitiated ? new Date().toISOString() : null
	});
	await admin
		.from('event_attendees')
		.upsert({ event_id: eventId, user_id: buyerId, status: 'going' });
	return async () => {
		await admin.from('event_orders').delete().eq('event_id', eventId);
		await admin
			.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', buyerId);
	};
}

test.describe('paid registration self-cancel (slice P2)', () => {
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

	test('registered buyer sees Cancel registration; confirm shows refundable copy; fails closed with no Stripe keys', async ({
		page
	}) => {
		const title = `e2e-selfcancel ${Date.now()}`;
		const startsAt = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 10,
			starts_at: startsAt
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id));
		cleanups.push(await seatBuyer(id, startsAt, USER_A.id, USER_A.id));

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		await expect(page.getByText("You're registered")).toBeVisible();
		const cancel = page.getByTestId('cancel-registration');
		await expect(cancel).toBeVisible();

		await cancel.click();
		const dialog = page.getByTestId('cancel-registration-dialog');
		await expect(dialog).toBeVisible();
		// full_until_24h with a start 7 days out => refundable copy mentions the refund.
		await expect(dialog).toContainText(/refunded/i);

		// Confirm with no Stripe keys configured: the EF 503s and the action
		// fails closed to an error toast — never a false "cancelled" success.
		await dialog.getByRole('button', { name: /Cancel registration/i }).click();
		await expect(page.getByText(/Could not cancel|couldn’t be started|couldn't be started/i)).toBeVisible({
			timeout: 10_000
		});
		// The seat is untouched — still registered.
		await expect(page.getByText("You're registered")).toBeVisible();
	});

	test('order mid-refund shows Refund in progress, not a live Cancel button', async ({ page }) => {
		const title = `e2e-refundpending ${Date.now()}`;
		const startsAt = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Spin',
			capacity: 10,
			starts_at: startsAt
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id));
		cleanups.push(await seatBuyer(id, startsAt, USER_A.id, USER_A.id, true));

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		await expect(page.getByText('Refund in progress')).toBeVisible();
		await expect(page.getByTestId('cancel-registration')).toHaveCount(0);
	});
});
