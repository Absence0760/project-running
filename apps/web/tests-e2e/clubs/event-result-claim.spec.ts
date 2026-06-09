import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — bib-result claim flow (#43 follow-up).
 *
 * USER_A owns richmond-run-club (organiser). USER_B is a member. We seed a
 * bib-only imported result (no account), then exercise both sides:
 *   1. USER_B taps "This is me" → the row shows "Claim pending".
 *   2. USER_A sees the claim in the organiser queue and approves it → the
 *      row attaches to USER_B and the queue empties.
 * afterEach deletes the event (results + claims cascade).
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

async function seedBibResult(eventId: string, instanceStart: string, resultId: string) {
	await getAdminClient()
		.from('event_results')
		.insert({
			id: resultId,
			event_id: eventId,
			instance_start: instanceStart,
			user_id: null,
			bib: '101',
			finisher_name: 'Alice Anon',
			duration_s: 2400,
			distance_m: 10000,
			finisher_status: 'finished',
			organiser_approved: true
		});
}

test.describe('bib-result claim — claimant side', () => {
	test.use({ storageState: USER_B.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-claim ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 10000
		});
		await seedBibResult(eventId, instanceStart, crypto.randomUUID());
	});
	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* cascade best-effort */
			}
			eventId = null;
		}
	});

	test('a member can claim a bib-only result', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const claimBtn = page.getByRole('button', { name: 'This is me' });
		await expect(claimBtn).toBeVisible({ timeout: 10_000 });
		await claimBtn.click();

		await expect(page.getByText('Claim pending')).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('bib-result claim — organiser approval', () => {
	test.use({ storageState: USER_A.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 8 * 24 * 3600 * 1000).toISOString();

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-claim-approve ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 10000
		});
		const resultId = crypto.randomUUID();
		await seedBibResult(eventId, instanceStart, resultId);
		// USER_B has already claimed it — seed the pending claim directly.
		await getAdminClient()
			.from('event_result_claims')
			.insert({ result_id: resultId, claimant_id: USER_B.id, status: 'pending' });
	});
	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* cascade best-effort */
			}
			eventId = null;
		}
	});

	test('an organiser sees and approves a pending claim', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await expect(page.getByRole('heading', { name: /^Result claims/ })).toBeVisible({
			timeout: 10_000
		});
		const approve = page.getByRole('button', { name: 'Approve' }).first();
		await expect(approve).toBeVisible();
		await approve.click();

		// Queue empties once the only pending claim is decided.
		await expect(page.getByRole('heading', { name: /^Result claims/ })).toHaveCount(0, {
			timeout: 10_000
		});
	});

	test('an organiser can reject a pending claim', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await expect(page.getByRole('heading', { name: /^Result claims/ })).toBeVisible({
			timeout: 10_000
		});
		await page.getByRole('button', { name: 'Reject' }).first().click();

		// Queue empties, and the row stays bib-only (no account attached).
		await expect(page.getByRole('heading', { name: /^Result claims/ })).toHaveCount(0, {
			timeout: 10_000
		});
		const { data } = await getAdminClient()
			.from('event_results')
			.select('user_id')
			.eq('event_id', eventId!)
			.eq('bib', '101')
			.single();
		expect(data?.user_id).toBeNull();
	});
});
