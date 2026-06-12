import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Attendance, distinct from RSVP (instructor_business.md M6). A class host
 * marks who actually showed up — paid/RSVP'd != attended. The mark flows
 * through the mark_attendance organiser-only SECURITY DEFINER RPC; the
 * attendee's own RSVP status is left untouched (orthogonal).
 *
 * (a) USER_A (Richmond owner = organiser) marks USER_B attended on a class
 *     event; the attendance column round-trips and the RSVP status is
 *     unchanged.
 * (b) USER_C_PRO (not an organiser) sees the resulting state read-only and is
 *     offered no marking controls.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const INSTANCE = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

test.describe('/clubs/[slug]/events/[id] — attendance', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort; event_attendees cascade on event delete */
			}
			eventId = null;
		}
	});

	test('host marks an attendee attended; RSVP status stays orthogonal', async ({ page }) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-attendance ${Date.now()}`,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: INSTANCE
		});

		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: INSTANCE
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-attendance/ })).toBeVisible({
			timeout: 10_000
		});

		// Host sees the marking controls; mark attended.
		const attendedBtn = page.getByRole('button', { name: 'Mark attended' });
		await expect(attendedBtn).toBeVisible({ timeout: 10_000 });
		await attendedBtn.click();
		await expect(attendedBtn).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });

		// Persisted: attendance set, RSVP status untouched.
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('event_attendees')
					.select('attendance, status')
					.eq('event_id', eventId!)
					.eq('user_id', USER_B.id)
					.eq('instance_start', INSTANCE)
					.single();
				return data;
			}, { timeout: 10_000 })
			.toEqual({ attendance: 'attended', status: 'going' });
	});

	test('host gating: a non-organiser sees attendance read-only, no controls', async ({
		browser
	}) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-attendance-ro ${Date.now()}`,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: INSTANCE
		});

		// USER_B is the attendee, pre-marked attended by seeding the column
		// directly (admin bypasses RLS — same end state a host mark produces).
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: INSTANCE,
			attendance: 'attended'
		});

		// USER_C_PRO is not an organiser of the club.
		const ctx = await browser.newContext({ storageState: USER_C_PRO.storageStatePath });
		const page = await ctx.newPage();
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-attendance-ro/ })).toBeVisible({
			timeout: 10_000
		});

		// Read-only badge present, marking controls absent.
		await expect(page.getByText('Attended', { exact: true })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Mark attended' })).toHaveCount(0);
		await expect(page.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);

		await ctx.close();
	});
});
