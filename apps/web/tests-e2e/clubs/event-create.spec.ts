import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Event create via UI — admin creates an event from /clubs/[slug].
 *
 * The slug-page admin "New event" button mounts EventEditor inside a
 * Modal (handler `handleEventCreated` refreshes the upcoming events
 * list and shows a toast — no navigation, the admin stays on the
 * club page). The standalone /clubs/[slug]/events/new route uses the
 * same EventEditor and navigates to /events/[id] on save; that path
 * isn't exercised here because real admins use the modal.
 *
 * The batch-12 RSVP test plants events via service-role
 * (`simulate.insertEvent`); this test pins the canonical UI create
 * path. Cleanup deletes via service-role.
 */

test.describe('/clubs/[slug] — admin event create', () => {
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

	test('admin opens New-event modal, fills EventEditor, event lands in upcoming list', async ({
		page
	}) => {
		const title = `e2e-event-create ${Date.now()}`;
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// "New event" admin button → Modal opens with the EventEditor.
		// The button label "New event" appears alongside an `add`
		// material symbol; the role-name regex matches.
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// EventEditor exposes title / description / date / time /
		// duration / meet point / route / capacity / pace. Title +
		// date + time are required; defaults handle the rest.
		await modal.getByPlaceholder('Sunday long run').fill(title);
		await modal.locator('input[type="date"]').first().fill(dayIso);
		await modal.locator('input[type="time"]').first().fill('07:30');

		await modal.getByRole('button', { name: /Create event/ }).click();
		// The handler closes the modal, refreshes events, shows a toast.
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		// The new event appears in the slug page's upcoming-events
		// list (Events tab). Switch tabs and find the row.
		await page.getByRole('tab', { name: /^Events/ }).click();
		const eventRow = page.locator(`a[href*="/events/"]`, { hasText: title });
		await expect(eventRow).toBeVisible({ timeout: 10_000 });

		// Capture the id from the row's href for cleanup.
		const href = (await eventRow.getAttribute('href')) ?? '';
		eventId = href.match(/\/events\/([0-9a-f-]+)$/)![1];
	});

	test('admin "Delete event" button opens confirmation dialog (cancel preserves event)', async ({
		page
	}) => {
		// /events/[id] exposes a "Delete event" button to admins only.
		// Clicking it opens a ConfirmDialog. Pin both the admin gate
		// + the dialog open, then Cancel out so the seed event
		// survives for the afterEach cleanup. The actual delete path
		// is exercised by clubs/event-delete.spec.ts.
		const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
		const title = `e2e-event-delete-confirm ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(
			page.getByRole('heading', { name: title })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /Delete event/ }).click();
		// ConfirmDialog mounts as a .modal; its title carries the
		// "Delete event" copy.
		const dialog = page.locator('.modal', { hasText: /Delete event/i });
		await expect(dialog).toBeVisible({ timeout: 5_000 });

		// Cancel — event must remain.
		await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
		await expect(dialog).toHaveCount(0);

		// DB confirms the event is still there.
		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('id')
			.eq('id', eventId)
			.maybeSingle();
		expect(row).not.toBeNull();
	});
});
