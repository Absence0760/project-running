import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — event photo gallery on a NON-race event.
 *
 * Regression for persona round-5 runner-social-group: the "Add photo"
 * affordance used to be gated behind having a finisher result row at the
 * event (the race-only path), so a weekly social group run — where nobody
 * submits results — never showed it. Now any signed-in user can add a
 * photo by picking which of their own runs it belongs to. The result-row
 * fast path still works; this pins the picker path that unblocks group runs.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

// 1x1 transparent PNG.
const PNG_1X1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64'
);

test.describe('/clubs/[slug]/events/[id] — non-race photo gallery', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			const admin = getAdminClient();
			await admin.from('run_photos').delete().eq('event_id', eventId);
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test('Add photo is offered on a non-race event and opens a run picker', async ({
		page
	}) => {
		const title = `e2e group-run photo ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const addPhoto = page.getByRole('button', { name: 'Add photo' });
		await expect(addPhoto).toBeVisible({ timeout: 10_000 });
		await addPhoto.click();

		const picker = page.locator('.picker', {
			hasText: 'Which run is this photo from?'
		});
		await expect(picker).toBeVisible({ timeout: 10_000 });
		await expect(picker.locator('button.run-option').first()).toBeVisible({
			timeout: 10_000
		});
	});

	test('picking a run and a file lands a run_photos row tagged to the event', async ({
		page
	}) => {
		const title = `e2e group-run upload ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: 'Add photo' }).click();

		const picker = page.locator('.picker', {
			hasText: 'Which run is this photo from?'
		});
		await expect(picker).toBeVisible({ timeout: 10_000 });

		// Picking a run fires the hidden file input's .click() in JS, which
		// opens a native chooser — catch it via the filechooser event.
		const chooser = page.waitForEvent('filechooser');
		await picker.locator('button.run-option').first().click();
		await (await chooser).setFiles({
			name: 'group-run.png',
			mimeType: 'image/png',
			buffer: PNG_1X1
		});

		await expect.poll(async () => {
			const admin = getAdminClient();
			const { data } = await admin
				.from('run_photos')
				.select('id, event_id, owner_id')
				.eq('event_id', eventId)
				.eq('owner_id', USER_A.id);
			return data?.length ?? 0;
		}, { timeout: 15_000 }).toBe(1);
	});
});
