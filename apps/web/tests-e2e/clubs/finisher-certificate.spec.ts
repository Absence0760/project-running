import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — finisher certificate (#44).
 *
 * Creates a one-off event, seeds an approved + finished event_results
 * row for the owner, then drives the Certificate button on the
 * leaderboard and captures the PNG download. afterEach deletes the
 * event (results cascade) so the seed shape is intact.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — finisher certificate', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	let instanceStart: string | null = null;

	test.beforeEach(async () => {
		// Zero the milliseconds: the event page derives the active instance via
		// expandInstances, which stamps each occurrence with setHours(h,m,s,0)
		// (ms=0). Production results are keyed on that ms=0 instant, so a seed
		// with non-zero ms would never match fetchEventResults' instance_start
		// filter and the result (+ its Certificate button) would never render.
		const seed = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		seed.setMilliseconds(0);
		instanceStart = seed.toISOString();
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-cert ${Date.now()}`,
			starts_at: instanceStart,
			recurrence_freq: 'weekly'
		});
		await getAdminClient()
			.from('event_results')
			.upsert(
				{
					event_id: eventId,
					instance_start: instanceStart,
					user_id: USER_A.id,
					duration_s: 2705,
					distance_m: 10000,
					rank: 1,
					finisher_status: 'finished',
					organiser_approved: true
				},
				{ onConflict: 'event_id,instance_start,user_id' }
			);
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

	test('downloads a finisher certificate PNG from an approved result', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const certBtn = page.getByRole('button', { name: 'Certificate' }).first();
		await expect(certBtn).toBeVisible({ timeout: 10_000 });

		const downloadPromise = page.waitForEvent('download', { timeout: 10_000 });
		await certBtn.click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toMatch(/^threkir-certificate-.*\.png$/);
	});

	test('surfaces an error toast when rasterization fails', async ({ page }) => {
		// Force canvas.toBlob to yield null, the exact branch svg_raster.ts
		// rejects on. Before the fix the rejection was swallowed and the user
		// saw nothing; persona round-5 runner-event-organizer (#44).
		await page.addInitScript(() => {
			HTMLCanvasElement.prototype.toBlob = function (callback: BlobCallback) {
				callback(null);
			};
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const certBtn = page.getByRole('button', { name: 'Certificate' }).first();
		await expect(certBtn).toBeVisible({ timeout: 10_000 });
		await certBtn.click();

		await expect(page.getByText('Could not generate the certificate. Please try again.')).toBeVisible({
			timeout: 10_000
		});
	});

	test('no certificate button while the result is unapproved', async ({ page }) => {
		await getAdminClient()
			.from('event_results')
			.update({ organiser_approved: false })
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.eq('instance_start', instanceStart);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Certificate' })).toHaveCount(0);
	});
});
