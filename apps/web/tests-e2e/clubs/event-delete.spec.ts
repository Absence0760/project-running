import { expect, test } from '@playwright/test';

import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — admin deletes an event from the
 * detail page.
 *
 * `event-create.spec.ts` covers the create-event modal on the slug
 * page; `event-rsvp.spec.ts` covers the per-instance RSVP toggle on
 * the detail page. This pins the OTHER admin affordance on the detail
 * page — the "Delete event" button + ConfirmDialog → goto(/clubs/[slug]).
 *
 * Plant via service-role to keep the test focused on the delete path.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — admin event delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort — UI delete should have already removed it */
			}
			eventId = null;
		}
	});

	test('admin opens the event detail, clicks Delete event, lands back on /clubs/[slug] with the event gone', async ({
		page
	}) => {
		const title = `e2e-event-delete ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title
		});

		await page.goto(`/clubs/sydney-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title }))
			.toBeVisible({ timeout: 10_000 });

		// Delete event button is admin-only; clicking opens
		// ConfirmDialog with confirmLabel="Delete".
		await page.getByRole('button', { name: 'Delete event' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete event' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		// Handler navigates back to /clubs/[slug].
		await page.waitForURL(/\/clubs\/sydney-run-club$/, { timeout: 10_000 });
		await expect(
			page.getByRole('heading', { level: 1, name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Event no longer in the upcoming list. Switch to Events tab
		// and assert the row is missing.
		await page.getByRole('tab', { name: /^Events/ }).click();
		await expect(page.locator('a[href*="/events/"]', { hasText: title }))
			.toHaveCount(0, { timeout: 10_000 });

		// Mark cleanup as done — the UI delete already removed the row.
		eventId = null;
	});
});
