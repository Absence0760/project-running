import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Roster-wide attendance on a class (instructor_business.md M6). The single-
 * attendee path is covered by event-attendance.spec; this drives a roster of
 * THREE attendees on one occurrence: the host marks each row independently
 * (attended / no_show / left unmarked), the per-row pills reflect each state,
 * and a non-organiser attendee sees the same roster read-only.
 *
 * USER_A owns Richmond (the host/organiser). Attendees are Alex (USER_B),
 * Morgan (USER_C_PRO) and Jared (USER_A) — seeded 'going' on the one instance.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const INSTANCE = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

test.describe('/clubs/[slug]/events/[id] — roster-wide attendance', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* event_attendees cascade on delete */
			}
			eventId = null;
		}
	});

	async function seedRoster(title: string): Promise<string> {
		const admin = getAdminClient();
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: INSTANCE
		});
		await admin.from('event_attendees').insert([
			{ event_id: id, user_id: USER_B.id, status: 'going', instance_start: INSTANCE },
			{ event_id: id, user_id: USER_C_PRO.id, status: 'going', instance_start: INSTANCE },
			{ event_id: id, user_id: USER_A.id, status: 'going', instance_start: INSTANCE }
		]);
		return id;
	}

	test('host marks a roster to three independent states; each pill reflects it', async ({
		page
	}) => {
		eventId = await seedRoster(`e2e-roster ${Date.now()}`);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-roster/ })).toBeVisible({ timeout: 10_000 });

		const alexRow = page.locator('.attendee', { hasText: 'Alex Chen' });
		const morganRow = page.locator('.attendee', { hasText: 'Morgan Lee' });
		const jaredRow = page.locator('.attendee', { hasText: 'Jared Howard' });

		// Mark Alex attended and Morgan no_show; leave Jared unmarked.
		const alexAttended = alexRow.getByRole('button', { name: 'Mark attended' });
		await alexAttended.click();
		await expect(alexAttended).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });

		const morganNoShow = morganRow.getByRole('button', { name: 'Mark no-show' });
		await morganNoShow.click();
		await expect(morganNoShow).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });

		// Jared's row stays unmarked — neither pill pressed.
		await expect(jaredRow.getByRole('button', { name: 'Mark attended' })).toHaveAttribute(
			'aria-pressed',
			'false'
		);
		await expect(jaredRow.getByRole('button', { name: 'Mark no-show' })).toHaveAttribute(
			'aria-pressed',
			'false'
		);

		// Persisted: three independent states on the one instance.
		const admin = getAdminClient();
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('event_attendees')
						.select('user_id, attendance')
						.eq('event_id', eventId!)
						.eq('instance_start', INSTANCE);
					return Object.fromEntries((data ?? []).map((r) => [r.user_id, r.attendance]));
				},
				{ timeout: 10_000 }
			)
			.toEqual({
				[USER_B.id]: 'attended',
				[USER_C_PRO.id]: 'no_show',
				[USER_A.id]: null
			});
	});

	test('a non-organiser attendee sees the marked roster read-only', async ({ browser }) => {
		const admin = getAdminClient();
		eventId = await seedRoster(`e2e-roster-ro ${Date.now()}`);
		// Pre-mark Alex attended + Morgan no_show directly (same end state a host
		// produces) so the read-only viewer has something to render.
		await admin
			.from('event_attendees')
			.update({ attendance: 'attended' })
			.eq('event_id', eventId)
			.eq('user_id', USER_B.id)
			.eq('instance_start', INSTANCE);
		await admin
			.from('event_attendees')
			.update({ attendance: 'no_show' })
			.eq('event_id', eventId)
			.eq('user_id', USER_C_PRO.id)
			.eq('instance_start', INSTANCE);

		// USER_B (Alex) is an attendee + plain member, not an organiser.
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		const ro = await ctx.newPage();
		await ro.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(ro.getByRole('heading', { name: /e2e-roster-ro/ })).toBeVisible({ timeout: 10_000 });

		// Read-only badges present, no marking controls anywhere on the roster.
		await expect(ro.locator('.attendees .attendance-badge.attended').first()).toBeVisible({
			timeout: 10_000
		});
		await expect(ro.locator('.attendees .attendance-badge.no_show').first()).toBeVisible();
		await expect(ro.getByRole('button', { name: 'Mark attended' })).toHaveCount(0);
		await expect(ro.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);

		await ctx.close();
	});
});
