import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — event detail + per-instance RSVP +
 * results + admin per-event posts.
 *
 * Per-instance RSVP coverage uses a 4-week weekly recurrence so the
 * detail page exposes 4 instance chips; the test RSVPs Going / Maybe
 * / Declined to three different instances and asserts each lands as
 * a separate row in event_attendees with the right instance_start
 * pkey component.
 *
 * Submit-my-time pins the picker → run-selection → leaderboard row
 * path documented in docs/features/clubs.md.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — RSVP', () => {
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

	test('I\'m in → Going round-trip on a freshly-planted event', async ({
		page
	}) => {
		const title = `e2e RSVP ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Events/ }).click();

		await page.locator(`a[href$="/events/${eventId}"]`).click();
		await expect(page).toHaveURL(new RegExp(`/events/${eventId}$`));

		await expect(
			page.getByRole('heading', { name: title })
		).toBeVisible({ timeout: 10_000 });

		const primary = page.getByRole('button', { name: "I'm in" });
		await expect(primary).toBeVisible();

		await primary.click();
		await expect(
			page.getByRole('button', { name: 'Going', exact: true })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(
			page.getByRole('button', { name: "I'm in" })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Maybe' }).click();
	});

	test('rsvpEvent UPSERT contract: status changes overwrite the same row, never duplicate', async ({
		page
	}) => {
		const title = `e2e RSVP upsert ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title }))
			.toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true }))
			.toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Maybe' }).click();
		await expect(page.getByRole('button', { name: "I'm in" }))
			.toBeVisible({ timeout: 10_000 });

		const declineBtn = page.getByRole('button', { name: "Can't make it" });
		await declineBtn.click();
		await expect(declineBtn).toHaveClass(/active/, { timeout: 10_000 });

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('event_attendees')
			.select('status, instance_start')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
		expect(rows?.length).toBe(1);
		expect(rows?.[0]?.status).toBe('declined');

		await admin.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});

	test('per-instance RSVP on a weekly recurring event: three statuses land on three distinct instance_start rows', async ({
		page
	}) => {
		const title = `e2e per-instance RSVP ${Date.now()}`;
		const startAt = new Date(Date.now() + 2 * 24 * 3600 * 1000);
		startAt.setUTCHours(7, 0, 0, 0);
		const untilAt = new Date(startAt.getTime() + 28 * 24 * 3600 * 1000);
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startAt.toISOString(),
			recurrence_freq: 'weekly',
			recurrence_byday: ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'],
			recurrence_until: untilAt.toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const chips = page.locator('.instance-chip');
		await expect(chips.first()).toBeVisible({ timeout: 10_000 });
		const chipCount = await chips.count();
		expect(chipCount).toBeGreaterThanOrEqual(3);

		await chips.nth(0).click();
		await expect(chips.nth(0)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(
			page.getByRole('button', { name: 'Going', exact: true })
		).toBeVisible({ timeout: 10_000 });

		await chips.nth(1).click();
		await expect(chips.nth(1)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: 'Maybe' }).click();

		await chips.nth(2).click();
		await expect(chips.nth(2)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: "Can't make it" }).click();

		await expect.poll(async () => {
			const admin = getAdminClient();
			const { data } = await admin
				.from('event_attendees')
				.select('status, instance_start')
				.eq('event_id', eventId)
				.eq('user_id', USER_A.id);
			return data?.length ?? 0;
		}, { timeout: 10_000 }).toBe(3);

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('event_attendees')
			.select('status, instance_start')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.order('instance_start', { ascending: true });
		expect(rows?.map((r) => r.status)).toEqual(['going', 'maybe', 'declined']);
		const distinctInstances = new Set(rows?.map((r) => r.instance_start));
		expect(distinctInstances.size).toBe(3);

		await page.reload();
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		await chips.nth(0).click();
		await expect(chips.nth(0)).toHaveClass(/active/, { timeout: 5_000 });
		await expect(
			page.getByRole('button', { name: 'Going', exact: true })
		).toBeVisible({ timeout: 10_000 });

		await chips.nth(1).click();
		await expect(chips.nth(1)).toHaveClass(/active/, { timeout: 5_000 });
		await expect(
			page.getByRole('button', { name: 'Maybe' })
		).toHaveClass(/active/, { timeout: 10_000 });

		await chips.nth(2).click();
		await expect(chips.nth(2)).toHaveClass(/active/, { timeout: 5_000 });
		await expect(
			page.getByRole('button', { name: "Can't make it" })
		).toHaveClass(/active/, { timeout: 10_000 });

		await admin
			.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});

	test('Submit my time: picker shows recent runs + DNF/DNS, attaching a run lands as a leaderboard row', async ({
		page
	}) => {
		const title = `e2e submit time ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: /Submit my time/ }).click();

		const picker = page.locator('.picker');
		await expect(picker).toBeVisible({ timeout: 10_000 });
		await expect(picker.getByRole('heading', { name: 'Attach a run' })).toBeVisible();
		await expect(picker.getByRole('button', { name: 'Record DNF' })).toBeVisible();
		await expect(picker.getByRole('button', { name: 'Record DNS' })).toBeVisible();

		const runOptions = picker.locator('button.run-option');
		await expect(runOptions.first()).toBeVisible({ timeout: 10_000 });
		const firstRunOption = runOptions.first();
		await firstRunOption.click();

		await expect(page.locator('.result.me')).toBeVisible({ timeout: 10_000 });

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('event_results')
			.select('user_id, finisher_status, run_id, duration_s, distance_m')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
		expect(rows?.length).toBe(1);
		expect(rows?.[0]?.finisher_status).toBe('finished');
		expect(rows?.[0]?.run_id).not.toBeNull();
		expect(rows?.[0]?.duration_s).toBeGreaterThan(0);

		await admin
			.from('event_results')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});

	test('Submit my time: Record DNF lands as dnf row with zero duration', async ({
		page
	}) => {
		const title = `e2e DNF ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('button', { name: /Submit my time/ }).click();
		const picker = page.locator('.picker');
		await expect(picker).toBeVisible({ timeout: 10_000 });
		await picker.getByRole('button', { name: 'Record DNF' }).click();

		await expect(page.locator('.dnf-tag', { hasText: 'DNF' })).toBeVisible({
			timeout: 10_000
		});

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('event_results')
			.select('finisher_status, duration_s, distance_m, run_id')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
		expect(rows?.length).toBe(1);
		expect(rows?.[0]?.finisher_status).toBe('dnf');
		expect(rows?.[0]?.duration_s).toBe(0);

		await admin
			.from('event_results')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});

	test('admin per-event update: composer posts an update tagged to the event, post renders with author + timestamp', async ({
		page
	}) => {
		const title = `e2e per-event update ${Date.now()}`;
		const body = `e2e-event-post ${Date.now()}`;
		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const composer = page.locator('.post-form textarea');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(body);
		await page.getByRole('button', { name: 'Post update' }).click();

		const post = page.locator('article.post', { hasText: body });
		await expect(post).toBeVisible({ timeout: 10_000 });
		await expect(post.locator('strong').first()).toBeVisible();
		await expect(post.locator('.when')).toBeVisible();

		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('club_posts')
			.select('body, event_id, author_id')
			.eq('event_id', eventId)
			.eq('body', body);
		expect(rows?.length).toBe(1);
		expect(rows?.[0]?.author_id).toBe(USER_A.id);

		await admin.from('club_posts').delete().eq('event_id', eventId);
	});

	test('anon visitor: can read the public-club event page but RSVP buttons are gated', async ({
		browser
	}) => {
		const title = `e2e anon view ${Date.now()}`;
		const localEventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString()
		});

		const anonCtx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		try {
			await anonCtx.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
			const anon = await anonCtx.newPage();
			await anon.goto(`/clubs/richmond-run-club/events/${localEventId}`);
			await expect(
				anon.getByRole('heading', { name: title })
			).toBeVisible({ timeout: 10_000 });

			await expect(anon.locator('.rsvp-tri')).toHaveCount(0);

			await expect(anon.locator('.post-form')).toHaveCount(0);
		} finally {
			await anonCtx.close();
			await deleteEvent(localEventId);
		}
	});
});
