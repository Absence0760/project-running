import { expect, test } from '@playwright/test';

import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — "Add to calendar" downloads a valid RFC 5545
 * .ics for the (chosen) occurrence. Pure builder is unit-tested in
 * event_ics.test.ts; this pins the button → download → VEVENT wiring.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — add to calendar', () => {
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

	test('upcoming event: download yields a one-VEVENT .ics with the title as SUMMARY', async ({
		page
	}) => {
		const title = `e2e calendar ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			duration_min: 90,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const btn = page.getByTestId('add-to-calendar');
		await expect(btn).toBeVisible();

		const downloadPromise = page.waitForEvent('download');
		await btn.click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toMatch(/\.ics$/);

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) chunks.push(Buffer.from(chunk));
		const ics = Buffer.concat(chunks).toString('utf8');

		expect(ics).toContain('BEGIN:VCALENDAR');
		expect(ics).toContain('END:VCALENDAR');
		expect((ics.match(/BEGIN:VEVENT/g) ?? []).length).toBe(1);
		expect(ics).toContain(`SUMMARY:${title}`);
		expect(ics).toMatch(/DTSTART:\d{8}T\d{6}Z/);
		expect(ics).toMatch(/DTEND:\d{8}T\d{6}Z/);
		expect(ics).toContain(`UID:event-${eventId}-`);
	});

	test('past event: the add-to-calendar button is not offered', async ({ page }) => {
		const title = `e2e calendar past ${Date.now()}`;
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

		await expect(page.getByTestId('add-to-calendar')).toHaveCount(0);
	});
});
