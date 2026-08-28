import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import { readRow } from '../fixtures/db-read';

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
			author_id: USER_A.id,
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
		const exc = await readRow(
			'event_exceptions by event_id',
			admin
				.from('event_exceptions')
				.select('reason, cancelled_by')
				.eq('event_id', eventId)
				.single()
		);
		expect(exc.reason).toBe('Marshal shortage');
		expect(exc.cancelled_by).toBe(USER_A.id);

		// The list stays expanded across the reload, so the cancelled
		// occurrence simply drops out: one fewer chip, and the cancelled
		// date is gone. (toHaveCount auto-retries while load() settles.)
		await expect(chips).toHaveCount(beforeCount - 1);
		await expect(
			page.locator('.instance-chip', { hasText: firstChipText })
		).toHaveCount(0);
	});

	test('the club events tab advances to the next live occurrence', async ({ page }) => {
		// Whole seconds: `expandInstances` stamps each occurrence with the
		// start's h/m/s and a zero millisecond, so a sub-second `starts_at`
		// drops its own first occurrence out of the expansion.
		const startsAt = new Date(Math.floor((Date.now() + 7 * 24 * 3600 * 1000) / 1000) * 1000);
		const title = `e2e-cancel-listing ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt.toISOString(),
			recurrence_freq: 'weekly'
		});

		// Before the cancellation the listing names the first occurrence.
		await page.goto('/clubs/richmond-run-club?tab=events');
		const row = page.locator('.event-row', { hasText: title }).first();
		await expect(row).toBeVisible({ timeout: 10_000 });
		// The browser runs in UTC (playwright.config.ts), so read the date in
		// UTC too — the runner's own zone is irrelevant to what is rendered.
		await expect(row.locator('.event-date')).toContainText(String(startsAt.getUTCDate()));
		const beforeDateText = (await row.locator('.event-date').textContent())?.trim() ?? '';

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: 'Cancel this occurrence' }).click();
		await page
			.getByRole('dialog')
			.getByRole('button', { name: 'Cancel this occurrence' })
			.click();
		await expect(page.getByTestId('cancelled-occurrences')).toBeVisible({ timeout: 10_000 });

		// The listing now names the second occurrence — a week on, so its
		// day-of-month always differs from the cancelled one's.
		const second = new Date(startsAt.getTime() + 7 * 24 * 3600 * 1000);
		await page.goto('/clubs/richmond-run-club?tab=events');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row.locator('.event-date')).toContainText(String(second.getUTCDate()));
		expect((await row.locator('.event-date').textContent())?.trim()).not.toBe(beforeDateText);
	});

	test('an organiser can reinstate an occurrence beyond the next one', async ({ page }) => {
		const admin = getAdminClient();
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-reinstate-later ${Date.now()}`,
			starts_at: new Date(
				Math.floor((Date.now() + 7 * 24 * 3600 * 1000) / 1000) * 1000
			).toISOString(),
			recurrence_freq: 'weekly'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		// Cancel the SECOND occurrence. The picker hides it afterwards, so
		// before the cancelled-occurrences list existed this was irreversible.
		const chips = page.locator('.instance-chip');
		await expect(chips.nth(1)).toBeVisible();
		const secondChipText = (await chips.nth(1).textContent())?.trim() ?? '';
		await chips.nth(1).click();
		await page.getByRole('button', { name: 'Cancel this occurrence' }).click();
		await page
			.getByRole('dialog')
			.getByRole('button', { name: 'Cancel this occurrence' })
			.click();

		const cancelledList = page.getByTestId('cancelled-occurrences');
		await expect(cancelledList).toBeVisible({ timeout: 10_000 });
		await expect(cancelledList).toContainText(secondChipText);

		await cancelledList.getByRole('button', { name: 'Reinstate this occurrence' }).click();
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('event_exceptions')
						.select('instance_start')
						.eq('event_id', eventId);
					return data?.length ?? 0;
				},
				{ timeout: 10_000 }
			)
			.toBe(0);
		await expect(page.locator('.instance-chip', { hasText: secondChipText })).toHaveCount(1);
	});

	test('the dashboard next-RSVP card drops a cancelled occurrence', async ({ page }) => {
		const admin = getAdminClient();
		// Inside the card's 48 h window, and whole seconds so the instant the
		// exception names is byte-identical to the RSVP's.
		const startsAt = new Date(Math.floor((Date.now() + 2 * 3600 * 1000) / 1000) * 1000);
		const title = `e2e-dash-rsvp ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt.toISOString()
		});
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_A.id,
			instance_start: startsAt.toISOString(),
			status: 'going'
		});

		await page.goto('/dashboard');
		await expect(page.getByTestId('dash-total-runs')).toBeVisible({ timeout: 15_000 });
		await expect(page.locator('.event-card', { hasText: title })).toBeVisible({
			timeout: 15_000
		});

		// The RSVP row deliberately survives the cancellation (the organiser can
		// reinstate), so only the exception can tell the card the run is off.
		await admin.from('event_exceptions').insert({
			event_id: eventId,
			instance_start: startsAt.toISOString(),
			cancelled_by: USER_A.id,
			reason: 'Marshal shortage'
		});

		await page.goto('/dashboard');
		// Wait for the dashboard to have actually rendered before asserting an
		// absence, or the assertion passes on an empty page.
		await expect(page.getByTestId('dash-total-runs')).toBeVisible({ timeout: 15_000 });
		await expect(page.locator('.event-card', { hasText: title })).toHaveCount(0);
	});
});
