import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The fundraiser SECTION — a failed campaign read must not read as "there is
 * no campaign".
 *
 * `fetchFundraiserForRun` / `fetchFundraiserForEvent` throw on a failed read
 * now, but the section's own loader catches it and leaves `fundraiser = null`
 * on purpose, so the owner's "Create fundraiser" CTA cannot be hidden by a
 * blip. The consequence for the OTHER reader went unfixed: a supporter opening
 * a campaign whose read failed saw the section render nothing at all — byte
 * for byte what an anchor with no campaign renders.
 *
 * The anchor is a CLUB EVENT, not a run, because the club-event page is the
 * only surface on which a non-owner mounts `FundraiserSection` at all.
 * `/runs/[id]` mounts it inside the branch a non-owner never enters: a viewer
 * who does not own the run falls into the `otherRunOwner` branch, which
 * renders `RunShareView` and no fundraiser section — so a run-anchored
 * non-owner spec asserts against a component that was never on the page, and
 * both its failure assertion and its absence assertion are vacuous. See the
 * followup filed by the round-41 e2e lane.
 *
 * USER_B is an active `member` of richmond-run-club (seed.sql) and USER_A owns
 * it, so USER_B reads the event page with `isEventOrganiser` false — the
 * non-owner state this spec is about. The seeded storage state already carries
 * an accepted cookie consent (fixtures/auth.ts), so no banner floats over the
 * section.
 */
const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_RUN_CLUB_SLUG = 'richmond-run-club';

test.describe('event fundraiser section — a failed read is not "no campaign"', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let fundraiserId = '';
	let eventId = '';

	test.beforeEach(async () => {
		const admin = getAdminClient();
		// The `fundraisers` open-status trigger refuses a campaign whose owner
		// has no charges-enabled payout account.
		await admin.from('instructor_payout_accounts').upsert({
			user_id: USER_A.id,
			stripe_connect_account_id: `acct_e2e_frsec_${USER_A.id.slice(0, 8)}`,
			charges_enabled: true,
			payouts_enabled: true,
			details_submitted: true,
			country: 'US',
			default_currency: 'usd',
		});
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-fundraiser-section-failure ${Date.now()}`,
		});
		const { data, error } = await admin
			.from('fundraisers')
			.insert({
				owner_user_id: USER_A.id,
				event_id: eventId,
				charity_name: 'Test Charity',
				title: `e2e-fundraiser-section-failure ${Date.now()}`,
				goal_cents: 50_000,
				currency: 'usd',
				status: 'open',
			})
			.select('id')
			.single();
		if (error || !data) throw error ?? new Error('seed fundraiser failed');
		fundraiserId = data.id as string;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (fundraiserId) await admin.from('fundraisers').delete().eq('id', fundraiserId);
		if (eventId) await deleteEvent(eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
		fundraiserId = '';
		eventId = '';
	});

	test('a non-owner gets a retry, and the retry brings the campaign back', async ({ page }) => {
		let failRead = true;
		// The RPC totals read lives at /rest/v1/rpc/fundraiser_totals, which this
		// matcher deliberately does not touch — a totals failure is a different
		// branch with its own message.
		await page.route(/\/rest\/v1\/fundraisers\?/, async (route) => {
			if (failRead && route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated fundraiser read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto(`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/${eventId}`);

		const banner = page.getByTestId('fundraiser-section-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		// A club member is not the organiser, so the Create CTA must not be
		// offered to them whether the read worked or not.
		await expect(page.getByTestId('fundraiser-create-cta')).toHaveCount(0);

		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('fundraiser-section-load-error')).toHaveCount(0, {
			timeout: 15_000,
		});
		await expect(page.locator('.fundraiser-section')).toBeVisible({ timeout: 15_000 });
		await expect(
			page.locator('.fundraiser-section').getByRole('link', { name: 'Recent supporters' })
		).toBeVisible();
	});

	test('an event with genuinely no campaign shows nothing at all to a non-owner', async ({
		page,
	}) => {
		// The control the first test needs to mean anything: the empty case and
		// the failed case rendered identically, so the fix is only real if the
		// empty case still renders nothing.
		const admin = getAdminClient();
		await admin.from('fundraisers').delete().eq('id', fundraiserId);
		fundraiserId = '';

		await page.goto(`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
		// The section is on the page for a non-owner (unlike on /runs/[id]) — it
		// is its own render that must stay empty, not an unmounted component.
		await expect(page.locator('.fundraiser-section')).toHaveCount(0);
		await expect(page.getByTestId('fundraiser-section-load-error')).toHaveCount(0);
		await expect(page.getByTestId('fundraiser-create-cta')).toHaveCount(0);
	});
});
