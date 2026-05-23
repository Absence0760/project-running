import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — admin deletes an event from the
 * detail page.
 *
 * Two cases: a plain delete (event has no children), and a delete
 * against an event that already carries attendee + result rows —
 * the FK cascades on events should sweep both children, leaving no
 * orphan rows.
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

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title }))
			.toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Delete event' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete event' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await page.waitForURL(/\/clubs\/richmond-run-club$/, { timeout: 10_000 });
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('tab', { name: /^Events/ }).click();
		await expect(page.locator('a[href*="/events/"]', { hasText: title }))
			.toHaveCount(0, { timeout: 10_000 });

		eventId = null;
	});

	test('admin delete cascades: attendees + results rows are swept by the events FK on delete', async ({
		page
	}) => {
		const title = `e2e-event-delete-cascade ${Date.now()}`;
		const startsAt = new Date(Date.now() + 4 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title,
			starts_at: startsAt
		});

		const admin = getAdminClient();
		const { error: attErr } = await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_A.id,
			instance_start: startsAt,
			status: 'going'
		});
		if (attErr) throw attErr;
		const { error: resErr } = await admin.from('event_results').insert({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_A.id,
			duration_s: 1800,
			distance_m: 5000,
			finisher_status: 'finished'
		});
		if (resErr) throw resErr;

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title }))
			.toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Delete event' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete event' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await page.waitForURL(/\/clubs\/richmond-run-club$/, { timeout: 10_000 });

		const { data: eventRow } = await admin
			.from('events')
			.select('id')
			.eq('id', eventId)
			.maybeSingle();
		expect(eventRow).toBeNull();

		const { data: attRows } = await admin
			.from('event_attendees')
			.select('event_id')
			.eq('event_id', eventId);
		expect(attRows?.length ?? 0).toBe(0);

		const { data: resRows } = await admin
			.from('event_results')
			.select('event_id')
			.eq('event_id', eventId);
		expect(resRows?.length ?? 0).toBe(0);

		eventId = null;
	});
});
