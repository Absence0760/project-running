import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

/**
 * /clubs/[slug]/events/new — recurrence editor depth.
 *
 * `event-create.spec.ts` covers the one-off create path (title +
 * date + time, recurrence=none). This file pins the recurring
 * variants: weekly with multi-day byday, monthly, until-date
 * validation, and the byday-persistence-across-recurrence-switches
 * contract that the EventEditor exposes.
 *
 * All assertions hit the events row via service-role after submit
 * so a regression that drops a column from the insert payload is
 * caught at the DB level, not just the UI.
 */

test.describe('/clubs/[slug]/events/new — recurrence', () => {
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

	test('weekly recurring event: Mon+Wed+Fri until 4 weeks out → row carries byday + until + freq, detail page expands instances', async ({
		page
	}) => {
		const title = `e2e-recurring-weekly ${Date.now()}`;
		const startDate = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		const startIso = startDate.toISOString().slice(0, 10);
		const untilDate = new Date(Date.now() + 28 * 24 * 3600 * 1000);
		const untilIso = untilDate.toISOString().slice(0, 10);

		await page.goto(`/clubs/richmond-run-club/events/new`);
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});

		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('07:30');

		await page.getByRole('radio', { name: 'Weekly' }).check();
		await page.getByRole('button', { name: 'Mon' }).click();
		await page.getByRole('button', { name: 'Wed' }).click();
		await page.getByRole('button', { name: 'Fri' }).click();

		const untilInput = page.locator('fieldset input[type="date"]');
		await untilInput.fill(untilIso);

		await page.getByRole('button', { name: /Create event/ }).click();

		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, {
			timeout: 10_000
		});
		const match = page.url().match(/\/events\/([0-9a-f-]+)$/);
		eventId = match![1];

		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('recurrence_freq, recurrence_byday, recurrence_until, title')
			.eq('id', eventId)
			.single();
		expect(row?.recurrence_freq).toBe('weekly');
		expect(row?.recurrence_byday).toEqual(expect.arrayContaining(['MO', 'WE', 'FR']));
		expect(row?.recurrence_byday).toHaveLength(3);
		expect(row?.recurrence_until).not.toBeNull();

		const recurrenceLabel = page.locator('.hero-eyebrow', {
			hasText: /every week/i
		});
		await expect(recurrenceLabel).toBeVisible({ timeout: 10_000 });

		const instanceChips = page.locator('.instance-chip');
		const chipCount = await instanceChips.count();
		expect(chipCount).toBeGreaterThanOrEqual(2);
	});

	test('weekly "end after N occurrences" persists recurrence_count (persona #41)', async ({
		page
	}) => {
		const title = `e2e-recurrence-count ${Date.now()}`;
		const startIso = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);

		await page.goto('/clubs/richmond-run-club/events/new');
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});
		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('07:30');
		await page.getByRole('radio', { name: 'Weekly' }).check();
		await page.getByPlaceholder('N occurrences').fill('6');

		await page.getByRole('button', { name: /Create event/ }).click();
		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, { timeout: 10_000 });
		eventId = page.url().match(/\/events\/([0-9a-f-]+)$/)![1];

		const { data: row } = await getAdminClient()
			.from('events')
			.select('recurrence_freq, recurrence_count')
			.eq('id', eventId)
			.single();
		expect(row?.recurrence_freq).toBe('weekly');
		expect(row?.recurrence_count).toBe(6);
	});

	test('unbounded weekly series exposes far more than the old 6-instance cap (persona #40)', async ({
		page
	}) => {
		// Regression guard: the picker used to call expandInstances(..., 6) over
		// a 120-day window, so weeks 7+ of a weekly series were unreachable.
		// An unbounded weekly series should now preview a fixed number of chips
		// and expand to the full ~52-occurrence year on demand.
		const title = `e2e-recurring-uncapped ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
			recurrence_freq: 'weekly'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		// Preview is capped at INSTANCE_PREVIEW_COUNT (8) — already > the old 6.
		const chips = page.locator('.instance-chip');
		await expect(chips).toHaveCount(8);

		// The toggle advertises the full count, which for an unbounded weekly
		// series within a year is ~52 — proving weeks 7+ are reachable.
		const toggle = page.getByRole('button', { name: /Show all \d+ upcoming/ });
		await expect(toggle).toBeVisible();
		const label = (await toggle.textContent()) ?? '';
		const total = Number(label.match(/\d+/)?.[0] ?? '0');
		expect(total).toBeGreaterThan(6);
		expect(total).toBeGreaterThanOrEqual(40);

		// Expanding reveals every occurrence, not just the preview.
		await toggle.click();
		expect(await chips.count()).toBe(total);
	});

	test('monthly recurring event: row carries freq=monthly, no byday required', async ({
		page
	}) => {
		const title = `e2e-recurring-monthly ${Date.now()}`;
		const startDate = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		const startIso = startDate.toISOString().slice(0, 10);

		await page.goto(`/clubs/richmond-run-club/events/new`);
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});

		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('08:00');

		await page.getByRole('radio', { name: 'Monthly' }).check();

		await expect(page.getByRole('button', { name: 'Mon' })).toHaveCount(0);

		await page.getByRole('button', { name: /Create event/ }).click();

		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, {
			timeout: 10_000
		});
		const match = page.url().match(/\/events\/([0-9a-f-]+)$/);
		eventId = match![1];

		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('recurrence_freq, recurrence_byday')
			.eq('id', eventId)
			.single();
		expect(row?.recurrence_freq).toBe('monthly');
		expect(row?.recurrence_byday).toBeNull();

		await expect(
			page.locator('.hero-eyebrow', { hasText: /repeats monthly/i })
		).toBeVisible({ timeout: 10_000 });
	});

	test('until-date in the past produces no instances: detail page shows Past event', async ({
		page
	}) => {
		const title = `e2e-recurring-stale-until ${Date.now()}`;
		const startDate = new Date(Date.now() - 14 * 24 * 3600 * 1000);
		const startIso = startDate.toISOString().slice(0, 10);
		const untilDate = new Date(Date.now() - 7 * 24 * 3600 * 1000);
		const untilIso = untilDate.toISOString().slice(0, 10);

		await page.goto(`/clubs/richmond-run-club/events/new`);
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});

		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('07:00');
		await page.getByRole('radio', { name: 'Weekly' }).check();
		await page.getByRole('button', { name: 'Tue' }).click();
		const untilInput = page.locator('fieldset input[type="date"]');
		await untilInput.fill(untilIso);

		await page.getByRole('button', { name: /Create event/ }).click();

		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, {
			timeout: 10_000
		});
		const match = page.url().match(/\/events\/([0-9a-f-]+)$/);
		eventId = match![1];

		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});

		await expect(page.locator('.rsvp-tri')).toHaveCount(0);
	});

	test('switching recurrence type: byday selections persist across weekly→monthly→weekly', async ({
		page
	}) => {
		const title = `e2e-recurrence-switch ${Date.now()}`;
		const startIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		await page.goto(`/clubs/richmond-run-club/events/new`);
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});

		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('07:00');

		await page.getByRole('radio', { name: 'Weekly' }).check();
		await page.getByRole('button', { name: 'Mon' }).click();
		await expect(page.getByRole('button', { name: 'Mon' })).toHaveClass(/active/);

		await page.getByRole('radio', { name: 'Monthly' }).check();
		await expect(page.getByRole('button', { name: 'Mon' })).toHaveCount(0);

		await page.getByRole('radio', { name: 'Weekly' }).check();
		await expect(page.getByRole('button', { name: 'Mon' })).toHaveClass(/active/);

		await page.getByRole('button', { name: /Create event/ }).click();
		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, {
			timeout: 10_000
		});
		const match = page.url().match(/\/events\/([0-9a-f-]+)$/);
		eventId = match![1];

		const admin = getAdminClient();
		const { data: row } = await admin
			.from('events')
			.select('recurrence_freq, recurrence_byday')
			.eq('id', eventId)
			.single();
		expect(row?.recurrence_freq).toBe('weekly');
		expect(row?.recurrence_byday).toEqual(['MO']);
	});
});
