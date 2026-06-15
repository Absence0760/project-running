import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — RSVP transition completeness.
 *
 * `event-rsvp.spec.ts` proves the UPSERT contract (status changes overwrite
 * one row) and ends on 'declined'. This file pins the parts that spec
 * leaves open:
 *
 *   (a) the full going → maybe → declined cycle keeps exactly one row and
 *       updates its status each click (never a second row, never a stale one);
 *   (b) clicking the active status again CLEARS the RSVP — the row is deleted
 *       (clearRsvp), not just flipped to a sentinel, and the headcount drops
 *       back to zero;
 *   (c) the live "going" count in the hero reflects each transition.
 *
 * One-off (non-recurring) event so activeInstance stays the single
 * starts_at and the tri-state buttons map straight to one attendee row.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — RSVP transitions', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* attendees cascade on event delete */
			}
			eventId = null;
		}
	});

	async function rsvpRows(id: string) {
		const { data } = await getAdminClient()
			.from('event_attendees')
			.select('status')
			.eq('event_id', id)
			.eq('user_id', USER_A.id);
		return data ?? [];
	}

	test('going → maybe → declined → clear keeps one row, then deletes it', async ({ page }) => {
		const title = `e2e-rsvp-cycle ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		// Going.
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect.poll(async () => rsvpRows(eventId!)).toEqual([{ status: 'going' }]);

		// Maybe.
		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(page.getByRole('button', { name: 'Maybe' })).toHaveClass(/active/, {
			timeout: 10_000
		});
		await expect.poll(async () => rsvpRows(eventId!)).toEqual([{ status: 'maybe' }]);

		// Declined.
		const declineBtn = page.getByRole('button', { name: "Can't make it" });
		await declineBtn.click();
		await expect(declineBtn).toHaveClass(/active/, { timeout: 10_000 });
		await expect.poll(async () => rsvpRows(eventId!)).toEqual([{ status: 'declined' }]);

		// Click the active "declined" again → clearRsvp deletes the row.
		await declineBtn.click();
		await expect(page.getByRole('button', { name: "Can't make it" })).not.toHaveClass(/active/, {
			timeout: 10_000
		});
		await expect.poll(async () => rsvpRows(eventId!)).toEqual([]);
	});

	test('the hero "going" count tracks the RSVP as it changes', async ({ page }) => {
		const title = `e2e-rsvp-count ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const goingMetric = page.locator('.metric', { hasText: 'Going' }).locator('.value');
		await expect(goingMetric).toHaveText('0', { timeout: 10_000 });

		// Going → count is 1.
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect(goingMetric).toHaveText('1', { timeout: 10_000 });

		// Switching to Maybe drops the going headcount back to 0 (maybe is not
		// a confirmed attendee).
		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(page.getByRole('button', { name: 'Maybe' })).toHaveClass(/active/, {
			timeout: 10_000
		});
		await expect(goingMetric).toHaveText('0', { timeout: 10_000 });
	});
});
