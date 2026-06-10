import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — a runner removes their own submitted
 * result. The "Remove mine" action used to delete on a single click
 * with no confirm and no error handling; it now routes through the
 * shared ConfirmDialog so a stray click can't silently destroy a
 * finish time. Two assertions: Cancel keeps the result, Confirm
 * removes it.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — remove my result', () => {
	test.use({ storageState: USER_A.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 9 * 24 * 3600 * 1000).toISOString();

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-result-remove ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 5000
		});
		await getAdminClient().from('event_results').insert({
			id: crypto.randomUUID(),
			event_id: eventId,
			instance_start: instanceStart,
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			finisher_status: 'finished'
		});
	});

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* cascade best-effort */
			}
			eventId = null;
		}
	});

	test('Remove mine asks to confirm; Cancel keeps the result, Confirm removes it', async ({
		page
	}) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('button', { name: 'Remove mine' })).toBeVisible({
			timeout: 10_000
		});

		// Cancel path: the confirm appears, dismissing it leaves the result intact.
		await page.getByRole('button', { name: 'Remove mine' }).click();
		const dialog = page.locator('.modal', { hasText: 'Remove your result?' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toBeHidden({ timeout: 5_000 });

		const { data: stillThere } = await getAdminClient()
			.from('event_results')
			.select('id')
			.eq('event_id', eventId!)
			.eq('user_id', USER_A.id);
		expect(stillThere?.length ?? 0).toBe(1);

		// Confirm path: the result row is deleted server-side.
		await page.getByRole('button', { name: 'Remove mine' }).click();
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Remove result' }).click();
		await expect(page.getByRole('button', { name: 'Remove mine' })).toBeHidden({
			timeout: 10_000
		});

		const { data: gone } = await getAdminClient()
			.from('event_results')
			.select('id')
			.eq('event_id', eventId!)
			.eq('user_id', USER_A.id);
		expect(gone?.length ?? 0).toBe(0);
	});
});
