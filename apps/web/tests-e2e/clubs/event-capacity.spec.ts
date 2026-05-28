import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Event capacity + waitlist (event-organizer persona #42, migration
 * 20261018_001). The DB triggers are unit-pinned in
 * apps/backend/supabase/tests/event_capacity_waitlist_test.sql; this spec
 * pins the web surface: a capped event that's full puts the next "I'm in"
 * onto the waitlist, and a freed slot auto-promotes them.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const INSTANCE = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

test.describe('/clubs/[slug]/events/[id] — capacity + waitlist', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort; event_attendees cascade on event delete */
			}
			eventId = null;
		}
	});

	test('full event waitlists the next RSVP, then auto-promotes on a freed slot', async ({
		page
	}) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e-capacity ${Date.now()}`,
			starts_at: INSTANCE,
			capacity: 1
		});

		// USER_B takes the single 'going' slot (admin insert bypasses RLS;
		// the capacity trigger still applies — this lands 'going').
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: INSTANCE
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const goingButton = page.getByRole('button', { name: /^(I'm in|Going|Waitlisted)$/ });
		await expect(goingButton).toBeVisible({ timeout: 10_000 });

		// USER_A clicks "I'm in" — capacity is full, so the trigger demotes
		// the RSVP to waitlisted and the button reflects it.
		await goingButton.click();
		await expect(page.getByRole('button', { name: 'Waitlisted' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText(/on waitlist/)).toBeVisible();

		// Verify the persisted status, then free the slot by removing USER_B.
		const { data: before } = await admin
			.from('event_attendees')
			.select('status')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.eq('instance_start', INSTANCE)
			.single();
		expect(before?.status).toBe('waitlisted');

		await admin
			.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_B.id)
			.eq('instance_start', INSTANCE);

		// The promote trigger should have flipped USER_A to going.
		const { data: after } = await admin
			.from('event_attendees')
			.select('status')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.eq('instance_start', INSTANCE)
			.single();
		expect(after?.status).toBe('going');

		// UI reflects the promotion after a reload.
		await page.reload();
		await expect(page.getByRole('button', { name: 'Going' })).toBeVisible({
			timeout: 10_000
		});
	});
});
