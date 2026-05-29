import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — organiser bulk results import (#43).
 *
 * USER_A owns richmond-run-club, so they're an event-organiser. Creates a
 * one-off event, opens the "Import results CSV" panel, uploads a
 * chip-timing CSV for two bib-only finishers (no accounts), and asserts
 * they land on the leaderboard by name. afterEach deletes the event so the
 * cascade clears the imported rows.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

const CSV = ['bib,name,time', '101,Alice Anon,00:24:00', '102,Bob Bibonly,00:27:00', ''].join('\n');

test.describe('/clubs/[slug]/events/[id] — bulk results import', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e-import ${Date.now()}`,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
			distance_m: 10000,
			recurrence_freq: 'weekly'
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

	test('imports bib-only finishers from a CSV onto the leaderboard', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Import results CSV' }).click();

		await page.locator('input[type="file"]').setInputFiles({
			name: 'results.csv',
			mimeType: 'text/csv',
			buffer: Buffer.from(CSV)
		});

		await expect(page.getByText('2 results ready to import.')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /^Import 2 results$/ }).click();

		await expect(page.getByText('Alice Anon')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('Bob Bibonly')).toBeVisible();
	});

	test('reports CSV errors and does not enable import', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Import results CSV' }).click();

		// Missing the required time column.
		await page.locator('input[type="file"]').setInputFiles({
			name: 'bad.csv',
			mimeType: 'text/csv',
			buffer: Buffer.from('bib,name\n101,Alice\n')
		});

		await expect(page.getByText(/No time column found/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('results ready to import.')).toHaveCount(0);
	});
});
