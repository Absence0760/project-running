import { expect, test } from '@playwright/test';

import { getAdminClient } from '../../fixtures/local-supabase';
import {
	clearNotifications,
	deleteEvent,
	insertEvent
} from '../../fixtures/simulate';
import { USER_A, USER_B } from '../../fixtures/users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * Cross-user event RSVP saga: USER_A (admin of Sydney Run Club) creates
 * an event. USER_B (alex, already a club member per seed.sql) RSVPs
 * "Going" via the event detail page. The expectation is that USER_A
 * receives a notification ("Alex Chen RSVP'd to your event").
 *
 * Trigger gap (2026-05-16): inspecting
 * apps/backend/supabase/migrations/20260528_001_notifications.sql shows
 * triggers wired only on run_kudos / run_comments / user_follows. No
 * trigger fires on event_attendees inserts, and the notifications.kind
 * CHECK does not include 'event_rsvp'. The notification this saga
 * expects therefore does not exist and the test is skipped.
 *
 * To wire it: add an 'event_rsvp' kind to the CHECK, a
 * notify_event_rsvp() SECURITY DEFINER trigger that notifies the
 * event's created_by when status='going' (skip self-RSVP), an event_id
 * column on notifications, and matching verb in
 * NotificationsList.svelte + NotificationBell.svelte. Once shipped,
 * unskip and the rest of the spec should pass.
 *
 * Until then the spec lives here as a coverage placeholder so a future
 * grep for "event_rsvp" notifications surfaces the gap, and the
 * positive case can be turned on with a one-line edit.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const SYDNEY_RUN_CLUB_SLUG = 'sydney-run-club';

test.describe('saga: alex RSVPs runner-owned event → runner inbox row', () => {
	test.describe.configure({ timeout: 90_000 });

	let eventId: string | null = null;

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `E2E RSVP saga ${Date.now()}`
		});
	});

	test.afterEach(async () => {
		if (eventId) {
			const admin = getAdminClient();
			await admin.from('event_attendees').delete().eq('event_id', eventId);
			try {
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
		await clearNotifications(USER_A.id);
	});

	test.skip(
		'inbox shows an event-RSVP notification — TODO: requires notify_event_rsvp trigger (see migration 20260528_001_notifications.sql)',
		async ({ browser }) => {
			const ctxAlex = await browser.newContext({
				storageState: USER_B.storageStatePath
			});
			const ctxRunner = await browser.newContext({
				storageState: USER_A.storageStatePath
			});
			await ctxAlex.addInitScript(setConsentAccepted);
			await ctxRunner.addInitScript(setConsentAccepted);
			const alex = await ctxAlex.newPage();
			const runner = await ctxRunner.newPage();

			try {
				await alex.goto(
					`/clubs/${SYDNEY_RUN_CLUB_SLUG}/events/${eventId}`
				);
				const goingBtn = alex.locator('.rsvp-opt.rsvp-going');
				await expect(goingBtn).toBeVisible({ timeout: 10_000 });
				await goingBtn.click();
				await expect(goingBtn).toHaveClass(/active/, { timeout: 10_000 });

				await runner.goto(`/u/${USER_A.id}?tab=notifications`);
				const row = runner
					.locator('.item-wrap')
					.filter({ hasText: /Alex Chen/ })
					.filter({ hasText: /RSVP/i });
				await expect(row).toBeVisible({ timeout: 10_000 });

				const badge = runner.locator('.bell-wrap .badge');
				await expect(badge).toBeVisible({ timeout: 5_000 });
			} finally {
				await ctxAlex.close();
				await ctxRunner.close();
			}
		}
	);

	test('current behaviour: alex RSVPs but no notification fires (documents the gap)', async ({
		browser
	}) => {
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		await ctxAlex.addInitScript(setConsentAccepted);
		await ctxRunner.addInitScript(setConsentAccepted);
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

		try {
			await alex.goto(
				`/clubs/${SYDNEY_RUN_CLUB_SLUG}/events/${eventId}`
			);
			const goingBtn = alex.locator('.rsvp-opt.rsvp-going');
			await expect(goingBtn).toBeVisible({ timeout: 10_000 });
			await goingBtn.click();
			await expect(goingBtn).toHaveClass(/active/, { timeout: 10_000 });

			// Verify the RSVP actually committed at the DB layer before
			// asserting on the absent notification — otherwise a UI
			// regression would silently pass this assertion.
			const admin = getAdminClient();
			const { data: att, error: attErr } = await admin
				.from('event_attendees')
				.select('status')
				.eq('event_id', eventId!)
				.eq('user_id', USER_B.id)
				.single();
			expect(attErr).toBeNull();
			expect(att?.status).toBe('going');

			await runner.goto(`/u/${USER_A.id}?tab=notifications`);
			await runner
				.getByRole('heading', { level: 1 })
				.waitFor({ timeout: 10_000 });
			// Empty-state copy when there are no notifications.
			await expect(
				runner.getByText(/No notifications yet|You're all caught up/)
			).toBeVisible({ timeout: 10_000 });
			await expect(runner.locator('.bell-wrap .badge')).toHaveCount(0);
		} finally {
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});
});
