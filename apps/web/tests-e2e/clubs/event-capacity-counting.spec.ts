import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Event capacity headcount semantics (migration 20261018_001).
 *
 * `event-capacity.spec.ts` pins the full-event → waitlist → auto-promote
 * path. This file pins the orthogonal half of the contract the trigger
 * documents ("a maybe/declined does NOT consume capacity; only going does"):
 *
 *   (a) on a capacity-1 event already holding one 'maybe' RSVP, a fresh
 *       "I'm in" still lands 'going' (not waitlisted) — maybe never occupied
 *       the slot;
 *   (b) a 'going' attendee who downgrades to 'maybe' frees the slot, so the
 *       previously-waitlisted runner is the only contended seat.
 *
 * USER_A drives the UI; USER_B is the pre-seeded other attendee.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const INSTANCE = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

test.describe('/clubs/[slug]/events/[id] — capacity headcount', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* attendees cascade */
			}
			eventId = null;
		}
	});

	test("a 'maybe' does not consume a capped slot: the next 'I'm in' still lands going", async ({
		page
	}) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-cap-maybe ${Date.now()}`,
			starts_at: INSTANCE,
			capacity: 1
		});

		// USER_B is a 'maybe' on the single-seat event. A maybe is not a
		// confirmed attendee, so the one seat is still open.
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'maybe',
			instance_start: INSTANCE
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const goingButton = page.getByRole('button', { name: /^(I'm in|Going|Waitlisted)$/ });
		await expect(goingButton).toBeVisible({ timeout: 10_000 });

		// USER_A clicks "I'm in" → lands 'going', NOT waitlisted, because the
		// maybe didn't occupy the seat.
		await goingButton.click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});

		const { data } = await admin
			.from('event_attendees')
			.select('status')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.eq('instance_start', INSTANCE)
			.single();
		expect(data?.status).toBe('going');
	});

	test('downgrading the sole going attendee to maybe frees the capped seat', async ({ page }) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-cap-downgrade ${Date.now()}`,
			starts_at: INSTANCE,
			capacity: 1
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('button', { name: "I'm in" })).toBeVisible({ timeout: 10_000 });

		// USER_A takes the only seat.
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('event_attendees')
					.select('status')
					.eq('event_id', eventId!)
					.eq('user_id', USER_A.id)
					.single();
				return data?.status;
			})
			.toBe('going');

		// Downgrade to maybe → the seat is free, so a subsequently-inserted
		// going attendee lands going (not waitlisted).
		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(page.getByRole('button', { name: 'Maybe' })).toHaveClass(/active/, {
			timeout: 10_000
		});

		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: INSTANCE
		});
		const { data: bRow } = await admin
			.from('event_attendees')
			.select('status')
			.eq('event_id', eventId)
			.eq('user_id', USER_B.id)
			.eq('instance_start', INSTANCE)
			.single();
		expect(bRow?.status).toBe('going');
	});
});
