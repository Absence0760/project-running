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
 * Cross-user event RSVP saga: USER_A (admin of Richmond Run Club) creates
 * an event. USER_B (alex, already a club member per seed.sql) RSVPs
 * "Going" via the event detail page. USER_A receives a notification
 * ("Alex Chen RSVP'd Going to your event …"). Wired by the
 * notify_event_rsvp trigger in migration
 * 20260903_001_notify_event_rsvp.sql (decisions §38).
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const SYDNEY_RUN_CLUB_SLUG = 'richmond-run-club';

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

	test(
		'inbox shows an event-RSVP notification',
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
});
