import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

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
			author_id: USER_A.id,
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

		await page.locator('input[type="file"][accept*=".csv"]').setInputFiles({
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
		await page.locator('input[type="file"][accept*=".csv"]').setInputFiles({
			name: 'bad.csv',
			mimeType: 'text/csv',
			buffer: Buffer.from('bib,name\n101,Alice\n')
		});

		await expect(page.getByText(/No time column found/)).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('results ready to import.')).toHaveCount(0);
	});
});

// Re-importing a corrected sheet must not revert a row a runner has since
// claimed (user_id set by an organiser approval) back to account-less.
// One-off event so instance_start == starts_at and is predictable.
test.describe('bulk results import — re-import preserves a claimed owner', () => {
	test.use({ storageState: USER_A.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 9 * 24 * 3600 * 1000).toISOString();
	const resultId = '43dd0000-0000-4000-8000-00000000c101';

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-reimport ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 10000
		});
		// Bib 101 already claimed + approved → owned by USER_B.
		await getAdminClient().from('event_results').insert({
			id: resultId,
			event_id: eventId,
			instance_start: instanceStart,
			user_id: USER_B.id,
			bib: '101',
			finisher_name: 'Alice Anon',
			duration_s: 2400,
			distance_m: 10000,
			finisher_status: 'finished',
			organiser_approved: true
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

	test('re-importing the same bib leaves the claimed account attached', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Import results CSV' }).click();
		await page.locator('input[type="file"][accept*=".csv"]').setInputFiles({
			name: 'results.csv',
			mimeType: 'text/csv',
			buffer: Buffer.from(CSV)
		});
		await expect(page.getByText('2 results ready to import.')).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: /^Import 2 results$/ }).click();
		// Bob (bib 102) is freshly imported — wait for him to confirm the upsert ran.
		await expect(page.getByText('Bob Bibonly')).toBeVisible({ timeout: 10_000 });

		// The claimed row (bib 101) must still belong to USER_B, not revert to NULL.
		const { data } = await getAdminClient()
			.from('event_results')
			.select('user_id')
			.eq('id', resultId)
			.single();
		expect(data?.user_id).toBe(USER_B.id);
	});
});

// The import panel + organiser claims queue are organiser-only. A plain
// member must not see either affordance.
test.describe('bulk results import — non-organiser sees no organiser affordances', () => {
	test.use({ storageState: USER_B.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 10 * 24 * 3600 * 1000).toISOString();

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-noorg ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 10000
		});
		await getAdminClient().from('event_results').insert({
			id: crypto.randomUUID(),
			event_id: eventId,
			instance_start: instanceStart,
			user_id: null,
			bib: '101',
			finisher_name: 'Alice Anon',
			duration_s: 2400,
			distance_m: 10000,
			finisher_status: 'finished',
			organiser_approved: true
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

	test('member sees no import button and no claims queue', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		// The leaderboard rendered (bib finisher visible) before we assert absence.
		await expect(page.getByText('Alice Anon')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Import results CSV' })).toHaveCount(0);
		await expect(page.getByRole('heading', { name: /^Result claims/ })).toHaveCount(0);
		// But a member CAN claim the bib row.
		await expect(page.getByRole('button', { name: 'This is me' })).toBeVisible();
	});
});
