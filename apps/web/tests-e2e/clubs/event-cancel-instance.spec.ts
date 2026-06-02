import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Per-instance cancellation web flow (parkrun / social-group persona #39,
 * migration 20261019_001). RLS + the notify fan-out are unit-pinned in
 * apps/backend/supabase/tests/event_instance_cancellation_test.sql; this spec
 * pins the organiser UI: cancelling one occurrence drops it from the live
 * picker and writes the audit row, leaving the rest of the series intact.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — cancel one occurrence', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;

	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* exceptions cascade on event delete */
			}
			eventId = null;
		}
	});

	test('organiser cancels an occurrence: dropped from picker + audit row written', async ({
		page
	}) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e-cancel-instance ${Date.now()}`,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
			recurrence_freq: 'weekly'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		// Expand to the full list and capture the live count + the next chip.
		await page.getByRole('button', { name: /Show all \d+ upcoming/ }).click();
		const chips = page.locator('.instance-chip');
		const beforeCount = await chips.count();
		expect(beforeCount).toBeGreaterThanOrEqual(40);
		const firstChipText = (await chips.first().textContent())?.trim() ?? '';
		expect(firstChipText.length).toBeGreaterThan(0);

		// Cancel the next occurrence (the active instance) with a reason.
		await page.getByRole('button', { name: 'Cancel this occurrence' }).click();
		await page.getByPlaceholder(/Course flooded/).fill('Marshal shortage');
		// The confirm button inside the modal shares the trigger's label
		// ("Cancel this occurrence"), so scope to the open dialog to pick the
		// modal's confirm rather than the now-background trigger.
		await page
			.getByRole('dialog')
			.getByRole('button', { name: 'Cancel this occurrence' })
			.click();

		// Audit row written with the reason + actor.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('event_exceptions')
						.select('reason, cancelled_by')
						.eq('event_id', eventId);
					return data?.length ?? 0;
				},
				{ timeout: 10_000 }
			)
			.toBe(1);
		const { data: exc } = await admin
			.from('event_exceptions')
			.select('reason, cancelled_by')
			.eq('event_id', eventId)
			.single();
		expect(exc?.reason).toBe('Marshal shortage');
		expect(exc?.cancelled_by).toBe(USER_A.id);

		// The list stays expanded across the reload, so the cancelled
		// occurrence simply drops out: one fewer chip, and the cancelled
		// date is gone. (toHaveCount auto-retries while load() settles.)
		await expect(chips).toHaveCount(beforeCount - 1);
		await expect(
			page.locator('.instance-chip', { hasText: firstChipText })
		).toHaveCount(0);
	});
});
