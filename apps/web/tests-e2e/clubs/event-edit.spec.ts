import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — an organiser edits an existing event (issue #335).
 *
 * Before this, EventEditor was create-only: fixing a typo'd title or wrong
 * meeting point meant delete-and-recreate, discarding attendees + results.
 * These cover the two contracts:
 *   1. An organiser edits title + meeting point and the change persists, while
 *      the event's attendee + result rows stay intact (no delete-recreate).
 *   2. Switching an event that already has results to a non-athletic category
 *      warns first (ConfirmDialog); confirming applies the change and the
 *      orphaned result row is left in place (not silently destroyed).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — organiser event edit', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort cleanup */
			}
			eventId = null;
		}
	});

	test('organiser edits title + meeting point; the change persists and attendees/results survive', async ({
		page
	}) => {
		const title = `e2e-event-edit ${Date.now()}`;
		const startsAt = new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
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
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		await page.getByTestId('edit-event').click();
		const modal = page.locator('.modal', { hasText: 'Edit event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const newTitle = `${title} (edited)`;
		const titleInput = modal.getByPlaceholder('Sunday long run');
		await titleInput.fill(newTitle);
		await modal.getByPlaceholder('e.g. North Gate, Central Park').fill('Tan track, boathouse end');
		await modal.getByRole('button', { name: 'Save changes' }).click();

		// Heading reflects the edit (page reloaded on save).
		await expect(page.getByRole('heading', { level: 1, name: newTitle })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText('Tan track, boathouse end')).toBeVisible({ timeout: 5_000 });

		// The row was UPDATEd, not delete-and-recreated: same id, new fields.
		const { data: row } = await admin
			.from('events')
			.select('title, meet_label')
			.eq('id', eventId)
			.single();
		expect(row?.title).toBe(newTitle);
		expect(row?.meet_label).toBe('Tan track, boathouse end');

		// Attendee + result rows survive the edit (the whole point of #335).
		const { data: attRows } = await admin
			.from('event_attendees')
			.select('event_id')
			.eq('event_id', eventId);
		expect(attRows?.length ?? 0).toBe(1);
		const { data: resRows } = await admin
			.from('event_results')
			.select('event_id')
			.eq('event_id', eventId);
		expect(resRows?.length ?? 0).toBe(1);
	});

	test('switching an event with results to a non-athletic category warns first, then applies on confirm', async ({
		page
	}) => {
		const title = `e2e-event-edit-warn ${Date.now()}`;
		const startsAt = new Date(Date.now() + 6 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt
		});

		const admin = getAdminClient();
		const { error: resErr } = await admin.from('event_results').insert({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			finisher_status: 'finished'
		});
		if (resErr) throw resErr;

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		await page.getByTestId('edit-event').click();
		const modal = page.locator('.modal', { hasText: 'Edit event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// Switch run -> class, then save: the category-change guard fires.
		await modal.getByRole('radio', { name: 'Class' }).click();
		await modal.getByRole('button', { name: 'Save changes' }).click();

		// The ConfirmDialog renders nested inside the edit modal's subtree, so
		// scope by the dialog's accessible name rather than a substring match.
		const warn = page.getByRole('dialog', { name: 'Change event type?' });
		await expect(warn).toBeVisible({ timeout: 5_000 });
		await warn.getByRole('button', { name: 'Change type' }).click();

		// Confirming hides the warning synchronously and only then kicks off the
		// save, so the editor closing — which `onsaved` does after the update
		// resolves — is the signal the write has actually landed. Reading the
		// row off the warning's disappearance races the request.
		await expect(warn).toBeHidden({ timeout: 5_000 });
		await expect(modal).toBeHidden({ timeout: 10_000 });
		const { data: row } = await admin
			.from('events')
			.select('category')
			.eq('id', eventId)
			.single();
		expect(row?.category).toBe('class');

		// The result row is orphaned, not destroyed — the warning was about
		// hiding it, and the edit path must never silently delete it.
		const { data: resRows } = await admin
			.from('event_results')
			.select('event_id')
			.eq('event_id', eventId);
		expect(resRows?.length ?? 0).toBe(1);
	});
});
