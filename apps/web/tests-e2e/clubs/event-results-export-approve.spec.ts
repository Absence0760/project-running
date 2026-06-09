import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — organiser results CSV export + bib-only approval
 * (persona round-5 parkrun-owner / event-organizer).
 *
 * USER_A owns richmond-run-club, so they are a race_director / event-organiser.
 * Each test seeds a one-off event (instance_start == starts_at) with a single
 * bib-only finisher (user_id NULL) so:
 *   - finding 2: "Download results CSV" serialises the leaderboard, and
 *   - finding 3: an un-approved bib-only row CAN be approved by the organiser
 *     (the user-id-keyed RPC could never reach a NULL-user row).
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — results export', () => {
	test.use({ storageState: USER_A.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 12 * 24 * 3600 * 1000).toISOString();

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-export ${Date.now()}`,
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

	test('Download results CSV emits a file with the bib-only finisher', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByText('Alice Anon')).toBeVisible({ timeout: 10_000 });

		const downloadPromise = page.waitForEvent('download');
		await page.getByRole('button', { name: 'Download results CSV' }).click();
		const download = await downloadPromise;
		expect(download.suggestedFilename()).toMatch(/^threkir-results-.*\.csv$/);

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const c of stream) chunks.push(Buffer.from(c));
		const csv = Buffer.concat(chunks).toString('utf-8');
		expect(csv.split(/\r?\n/)[0]).toBe('rank,bib,name,time,distance m,status');
		expect(csv).toContain('101');
		expect(csv).toContain('Alice Anon');
		expect(csv).toContain('40:00');
	});
});

test.describe('/clubs/[slug]/events/[id] — bib-only approval', () => {
	test.use({ storageState: USER_A.storageStatePath });
	let eventId: string | null = null;
	const instanceStart = new Date(Date.now() + 13 * 24 * 3600 * 1000).toISOString();
	const resultId = '43dd0000-0000-4000-8000-00000000d101';

	test.beforeEach(async () => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-approve-bib ${Date.now()}`,
			starts_at: instanceStart,
			distance_m: 10000
		});
		// Manual-approval mode for this instance: the
		// event_results_set_approval_default BEFORE-INSERT trigger
		// (20260425_001) auto-approves imported results UNLESS a race_session
		// for the (event, instance) has is_auto_approve=false. Without this row
		// the trigger would flip organiser_approved back to true and the
		// PENDING tag / Approve button would never appear.
		await getAdminClient()
			.from('race_sessions')
			.insert({ event_id: eventId, instance_start: instanceStart, is_auto_approve: false });
		await getAdminClient().from('event_results').insert({
			id: resultId,
			event_id: eventId,
			instance_start: instanceStart,
			user_id: null,
			bib: '101',
			finisher_name: 'Alice Anon',
			duration_s: 2400,
			distance_m: 10000,
			finisher_status: 'finished',
			organiser_approved: false
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

	test('organiser approves an un-matched bib-only result', async ({ page }) => {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByText('Alice Anon')).toBeVisible({ timeout: 10_000 });

		const row = page.locator('li.result', { hasText: 'Alice Anon' });
		await expect(row.getByText('PENDING')).toBeVisible();
		await row.getByRole('button', { name: 'Approve' }).click();

		await expect(row.getByText('PENDING')).toHaveCount(0, { timeout: 10_000 });

		const { data } = await getAdminClient()
			.from('event_results')
			.select('organiser_approved, organiser_approved_by')
			.eq('id', resultId)
			.single();
		expect(data?.organiser_approved).toBe(true);
		expect(data?.organiser_approved_by).toBe(USER_A.id);
	});
});
