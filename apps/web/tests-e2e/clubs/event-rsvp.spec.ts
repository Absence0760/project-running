import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — event detail + per-instance RSVP.
 *
 * Plants an event under Sydney Run Club (runner is the owner) via
 * service-role, drives the RSVP buttons in the UI, then deletes the
 * event so the suite stays idempotent. Surfaces the events tab on
 * /clubs/[slug] (which lists upcoming events) AND the rsvpEvent RPC
 * + the realtime push that flips `viewer_rsvp` on the open page.
 *
 * Future depth: instance picker on a recurring event, capacity-full
 * waitlist branch, Cancel-event admin flow, attendee list refresh
 * across two browser contexts (kudos-style cross-user assertion).
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — RSVP', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test('I\'m in → Going round-trip on a freshly-planted event', async ({
		page
	}) => {
		// Event is 7 days out so it lands in the upcoming bucket on
		// /clubs/[slug] (events split on now()), and so the RSVP
		// buttons render at all (past events hide the RSVP row).
		const title = `e2e RSVP ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		// Navigate via the club page so we exercise the events-list →
		// detail link too. The club detail's Events tab is a button
		// labelled "Events" (with an optional " (n)" suffix when there
		// are upcoming events) — match by prefix.
		await page.goto('/clubs/sydney-run-club');
		await page.getByRole('button', { name: /^Events/ }).click();

		// The event row is an anchor with href ending in /events/<id>.
		await page.locator(`a[href$="/events/${eventId}"]`).click();
		await expect(page).toHaveURL(new RegExp(`/events/${eventId}$`));

		// Hero header pins the event title — proves the row loaded
		// past the loading skeleton.
		await expect(
			page.getByRole('heading', { name: title })
		).toBeVisible({ timeout: 10_000 });

		// Pre-RSVP state: primary action reads "I'm in" (the no-rsvp
		// label). The text flips to "Going" once `event.viewer_rsvp`
		// flips via the rsvpEvent RPC.
		const primary = page.getByRole('button', { name: "I'm in" });
		await expect(primary).toBeVisible();

		// Click → expect the button text to flip to "Going". The page
		// re-derives the label from `event.viewer_rsvp`, which updates
		// after the realtime push from event_attendees.
		await primary.click();
		await expect(
			page.getByRole('button', { name: 'Going', exact: true })
		).toBeVisible({ timeout: 10_000 });

		// Switch to Maybe — verifies non-toggle transitions work too
		// (rsvpEvent with a different status, NOT a same-status
		// toggle-off). After Maybe, the primary button should swing
		// back to "I'm in" because `viewer_rsvp` is no longer 'going'.
		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(
			page.getByRole('button', { name: "I'm in" })
		).toBeVisible({ timeout: 10_000 });

		// Toggle Maybe off (same-status second click → null) so the
		// post-test event-delete cleanup runs against a clean
		// event_attendees state.
		await page.getByRole('button', { name: 'Maybe' }).click();
	});

	test('rsvpEvent UPSERT contract: status changes overwrite the same row, never duplicate', async ({
		page
	}) => {
		// Backend boundary: event_attendees has primary key
		// (event_id, user_id, instance_start) — a user changing their
		// status across "I'm in" → Maybe → "Can't make it" must
		// produce ONE row whose status changes, not three. The data
		// layer's rsvpEvent uses .upsert with onConflict on those
		// three columns. A regression that broke the constraint or
		// the onConflict target would surface as the count > 1 here.
		const title = `e2e RSVP upsert ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/sydney-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title }))
			.toBeVisible({ timeout: 10_000 });

		// Going (the primary "I'm in" button).
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true }))
			.toBeVisible({ timeout: 10_000 });

		// Maybe — separate button, switches status to 'maybe'.
		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(page.getByRole('button', { name: "I'm in" }))
			.toBeVisible({ timeout: 10_000 });

		// Can't make it — switches status to 'declined'. The button
		// gets the .active class once the upsert completes and the
		// realtime push lands; using it as a sync point avoids racing
		// the DB read against the in-flight RPC.
		const declineBtn = page.getByRole('button', { name: "Can't make it" });
		await declineBtn.click();
		await expect(declineBtn).toHaveClass(/active/, { timeout: 10_000 });

		// Backend assertion: exactly ONE row with status='declined'
		// (the latest), not three rows or a stale 'going'.
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('event_attendees')
			.select('status, instance_start')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
		expect(rows?.length).toBe(1);
		expect(rows?.[0]?.status).toBe('declined');

		// Cleanup the row so afterEach's deleteEvent doesn't trip on
		// FK ordering (event_attendees → events is on delete cascade
		// so this is belt + braces, but explicit beats lucky).
		await admin.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});
});
