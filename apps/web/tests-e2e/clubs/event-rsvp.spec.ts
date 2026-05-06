import { expect, test } from '@playwright/test';

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
});
