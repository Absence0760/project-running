import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * What a buyer READS when `events-checkout` refuses.
 *
 * `event-paid-register.spec.ts` covers the states the page can work out for
 * itself before the click — sold out and sales-closed as rendered from the
 * pure `registrationOpen` helper. This file covers the other half: the
 * refusals only the server knows, which arrive as a non-2xx from the Edge
 * Function after the buyer has already pressed Register.
 *
 * That path had no spec, and the reason it matters is that supabase-js's
 * `functions.invoke` does not surface the function's body on a non-2xx — it
 * throws a `FunctionsHttpError` whose `message` is the fixed internal string
 * "Edge Function returned a non-2xx status code" and whose `context` holds
 * the real `{ error: '<code>' }` envelope. Toasting `e.message` therefore
 * shows every refusal as that one sentence: sold out, sales closed, a host
 * whose Stripe account cannot take money, and a genuine outage all read
 * identically, and none of them tells the buyer anything. The sibling cancel
 * path already unwraps the envelope (`edgeFunctionErrorCode`); registration
 * did not.
 *
 * The function is stubbed at the network layer rather than driven for real:
 * the refusal branches need Stripe Connect keys and a host account in a
 * particular state, and what is under test here is the CLIENT's reading of
 * an envelope the function's own Deno tests already pin.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';

/// Same shape as event-paid-register.spec.ts: a charges-enabled payout
/// account so `enforce_pricing_requires_charges` accepts the pricing row.
async function priceEvent(hostId: string, eventId: string): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	await admin.from('instructor_payout_accounts').upsert({
		user_id: hostId,
		stripe_connect_account_id: `acct_e2e_${hostId.slice(0, 8)}`,
		charges_enabled: true,
		payouts_enabled: true,
		details_submitted: true,
		country: 'US',
		default_currency: 'usd',
	});
	const { error } = await admin.from('event_pricing').insert({
		event_id: eventId,
		instance_start: null,
		price_cents: 2200,
		currency: 'usd',
		modality: 'in_person',
		platform_fee_bps: 500,
		refund_policy: 'full_until_24h',
		sales_close_offset_minutes: 0,
	});
	if (error) throw new Error(`priceEvent failed: ${error.message}`);
	return async () => {
		await admin.from('event_pricing').delete().eq('event_id', eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', hostId);
	};
}

test.describe('paid registration — what a refusal tells the buyer', () => {
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

	/// Plant a priced event and stub the checkout function's answer.
	async function pricedEventRefusing(
		page: import('@playwright/test').Page,
		status: number,
		code: string,
	): Promise<void> {
		const title = `e2e-refusal ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 10,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
		});
		created.push(id);
		cleanups.push(await priceEvent(USER_A.id, id));

		await page.route('**/functions/v1/events-checkout', async (route) => {
			await route.fulfill({
				status,
				contentType: 'application/json',
				body: JSON.stringify({ error: code }),
			});
		});

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 15_000 });
		await page.getByTestId('register-cta').click();
	}

	const toast = (page: import('@playwright/test').Page) =>
		page.locator('[role="alert"], [role="status"]').filter({ hasText: /./ });

	test('a seat taken between render and click reads as sold out', async ({ page }) => {
		await pricedEventRefusing(page, 409, 'event_full');
		await expect(page.getByText('Sold out')).toBeVisible({ timeout: 10_000 });
		await expect(toast(page).filter({ hasText: /non-2xx|Edge Function/ })).toHaveCount(0);
	});

	test('a sales window that closed during the click reads as registration closed', async ({
		page,
	}) => {
		await pricedEventRefusing(page, 409, 'sales_closed');
		await expect(page.getByText('Registration closed')).toBeVisible({ timeout: 10_000 });
		await expect(toast(page).filter({ hasText: /non-2xx|Edge Function/ })).toHaveCount(0);
	});

	test('a host who cannot take payment is named as such, not as "try again"', async ({ page }) => {
		// Retrying cannot fix this one, so the generic "please try again" is
		// the wrong sentence as surely as the internal one is.
		await pricedEventRefusing(page, 409, 'host_cannot_take_payment');
		await expect(page.getByText(/host can't take payments/i)).toBeVisible({ timeout: 10_000 });
		await expect(toast(page).filter({ hasText: /non-2xx|Edge Function|try again/ })).toHaveCount(
			0,
		);
	});

	test('an unrecognised failure falls back to the generic retry copy, never the internal string', async ({
		page,
	}) => {
		await pricedEventRefusing(page, 500, 'checkout_failed');
		await expect(page.getByText('Could not start checkout. Please try again.')).toBeVisible({
			timeout: 10_000,
		});
		await expect(toast(page).filter({ hasText: /non-2xx|Edge Function/ })).toHaveCount(0);
	});

	test('the register button is released so the buyer can act on what they were told', async ({
		page,
	}) => {
		await pricedEventRefusing(page, 500, 'checkout_failed');
		await expect(page.getByTestId('register-cta')).toBeEnabled({ timeout: 10_000 });
	});
});
