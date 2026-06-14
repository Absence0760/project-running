import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Class-event lifecycle, depth tier — the corners the existing club specs
 * don't reach. The shipped specs already cover: generic capacity + waitlist
 * promote (event-capacity), attended + read-only (event-attendance), the
 * class-hides-athletic-fields editor (event-category-typed), the class->gym
 * seam (event_class_gym_seam), per-instance RSVP (event-rsvp), and discipline
 * + category + weekday + time + proximity discovery (social/discover). This
 * file pins, instructor- and attendee-side:
 *
 *  (1) Per-instance capacity on a RECURRING class: capacity is keyed on
 *      (event_id, instance_start), so the SAME user who is waitlisted on a
 *      full instance is 'going' on a different, empty instance.
 *  (2) Attendance NO-SHOW via the host's "Mark no-show" control, and the
 *      data-layer invariant that the mark_attendance RPC is the SOLE write
 *      path — a non-organiser's direct UPDATE on the attendance column is
 *      rejected (the revoked column grant, asserted with a real user JWT).
 *  (3) Defense-in-depth: a 'class' event has no race-control / Submit-my-time
 *      surface in the UI AND the DB triggers reject a race_sessions /
 *      event_results insert whose parent event is non-athletic — so the gate
 *      is the data layer, not just a hidden button.
 *  (4) Discover a class by CADENCE (weekly) + weekday over search_public_events
 *      — the cadence filter the discover spec leaves untested.
 *
 * Richmond Run Club (seed, USER_A owner) is public, so its events are both
 * organiser-controllable by USER_A and discoverable.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';

test.describe('/clubs/[slug]/events/[id] — recurring class, per-instance capacity', () => {
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

	test('capacity=1 weekly class: a second RSVP on the SAME instance waitlists, the SAME user is going on a DIFFERENT instance', async ({
		page
	}) => {
		const admin = getAdminClient();
		// A weekly class starting two days out, recurring every weekday so the
		// picker shows several future instances. capacity=1 makes each instance
		// hold exactly one 'going' seat.
		const startAt = new Date(Date.now() + 2 * 24 * 3600 * 1000);
		startAt.setUTCHours(7, 0, 0, 0);
		const untilAt = new Date(startAt.getTime() + 28 * 24 * 3600 * 1000);
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-class-cap ${Date.now()}`,
			category: 'class',
			discipline: 'Reformer Pilates',
			capacity: 1,
			starts_at: startAt.toISOString(),
			recurrence_freq: 'weekly',
			recurrence_byday: ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'],
			recurrence_until: untilAt.toISOString()
		});

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-class-cap/ })).toBeVisible({
			timeout: 10_000
		});

		const chips = page.locator('.instance-chip');
		await expect(chips.first()).toBeVisible({ timeout: 10_000 });
		expect(await chips.count()).toBeGreaterThanOrEqual(3);

		// Rather than re-derive instance_start client-side (the page's
		// expandInstances stamps in the EVENT's wall-clock — local-zone for a
		// row with no timezone — so a hand-computed UTC value would not match),
		// learn the real instance_start values by driving the UI: RSVP 'going'
		// on chip 0 and chip 1 as USER_A, then read the two rows back.
		await chips.nth(0).click();
		await expect(chips.nth(0)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});

		await chips.nth(1).click();
		await expect(chips.nth(1)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Going', exact: true })).toBeVisible({
			timeout: 10_000
		});

		// Two distinct instance_start rows for USER_A, both 'going' — capacity=1
		// did NOT collapse them, because each instance has its own seat.
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('event_attendees')
					.select('instance_start, status')
					.eq('event_id', eventId!)
					.eq('user_id', USER_A.id)
					.order('instance_start', { ascending: true });
				return (data ?? []).map((r) => r.status);
			}, { timeout: 10_000 })
			.toEqual(['going', 'going']);

		const { data: mine } = await admin
			.from('event_attendees')
			.select('instance_start')
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.order('instance_start', { ascending: true });
		const firstInstance = mine![0].instance_start as string;
		const secondInstance = mine![1].instance_start as string;

		// Hand the FIRST instance's seat to USER_B so it is full for USER_A:
		// move USER_A off instance 1 (frees the seat → no waitlist to promote
		// since none exists), seat USER_B there, then have USER_A re-RSVP on
		// instance 1 through the UI — now full, the capacity trigger demotes
		// USER_A to waitlisted. Instance 2 stays USER_A 'going' and untouched.
		await admin
			.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id)
			.eq('instance_start', firstInstance);
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: firstInstance
		});

		await page.reload();
		await expect(chips.first()).toBeVisible({ timeout: 10_000 });
		await chips.nth(0).click();
		await expect(chips.nth(0)).toHaveClass(/active/, { timeout: 5_000 });
		await page.getByRole('button', { name: "I'm in" }).click();
		await expect(page.getByRole('button', { name: 'Waitlisted' })).toBeVisible({
			timeout: 10_000
		});

		// The crux: USER_A is WAITLISTED on the full instance 1, yet still GOING
		// on the empty instance 2 — capacity is per (event_id, instance_start).
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('event_attendees')
					.select('instance_start, status')
					.eq('event_id', eventId!)
					.eq('user_id', USER_A.id);
				return new Map(
					(data ?? []).map((r) => [r.instance_start as string, r.status as string])
				);
			}, { timeout: 10_000 })
			.toEqual(
				new Map([
					[firstInstance, 'waitlisted'],
					[secondInstance, 'going']
				])
			);

		await admin
			.from('event_attendees')
			.delete()
			.eq('event_id', eventId)
			.eq('user_id', USER_A.id);
	});
});

test.describe('/clubs/[slug]/events/[id] — attendance no-show + sole write path', () => {
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

	test('host marks an attendee no_show; it persists and the RSVP status is untouched', async ({
		page
	}) => {
		const admin = getAdminClient();
		const instance = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-noshow ${Date.now()}`,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: instance
		});

		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_B.id,
			status: 'going',
			instance_start: instance
		});

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-noshow/ })).toBeVisible({
			timeout: 10_000
		});

		const noShowBtn = page.getByRole('button', { name: 'Mark no-show' });
		await expect(noShowBtn).toBeVisible({ timeout: 10_000 });
		await noShowBtn.click();
		await expect(noShowBtn).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });

		// Persisted: attendance='no_show', RSVP status untouched.
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('event_attendees')
					.select('attendance, status')
					.eq('event_id', eventId!)
					.eq('user_id', USER_B.id)
					.eq('instance_start', instance)
					.single();
				return data;
			}, { timeout: 10_000 })
			.toEqual({ attendance: 'no_show', status: 'going' });
	});

	test('mark_attendance RPC is the sole write path: a non-organiser direct UPDATE on the attendance column is rejected', async () => {
		const admin = getAdminClient();
		const instance = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-att-grant ${Date.now()}`,
			category: 'class',
			discipline: 'Vinyasa yoga',
			starts_at: instance
		});

		// USER_C_PRO is an attendee but NOT an organiser of Richmond.
		await admin.from('event_attendees').insert({
			event_id: eventId,
			user_id: USER_C_PRO.id,
			status: 'going',
			instance_start: instance
		});

		// As a REAL user JWT (RLS + column grants apply, unlike the admin
		// client), attempt the direct attendance write that the column-level
		// revoke (migration 20270102_001) is meant to block. It must error —
		// the SECURITY DEFINER RPC is the only path that may touch this column.
		const userClient = await getUserClient({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});
		const { error: directErr } = await userClient
			.from('event_attendees')
			.update({ attendance: 'attended' })
			.eq('event_id', eventId)
			.eq('user_id', USER_C_PRO.id)
			.eq('instance_start', instance);
		expect(directErr).not.toBeNull();

		// And calling the RPC as the same non-organiser is rejected too — only
		// the event organiser may mark attendance.
		const { error: rpcErr } = await userClient.rpc('mark_attendance', {
			p_event_id: eventId,
			p_user_id: USER_C_PRO.id,
			p_attendance: 'attended'
		});
		expect(rpcErr).not.toBeNull();

		// Nothing landed: the column stays NULL.
		const { data: after } = await admin
			.from('event_attendees')
			.select('attendance')
			.eq('event_id', eventId)
			.eq('user_id', USER_C_PRO.id)
			.eq('instance_start', instance)
			.single();
		expect(after?.attendance).toBeNull();
	});
});

test.describe('/clubs/[slug]/events/[id] — class has no athletic write path (defense-in-depth)', () => {
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

	test('a class exposes no race-control / Submit-my-time UI AND the DB rejects a race_sessions + event_results insert', async ({
		page
	}) => {
		const admin = getAdminClient();
		const instance = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-class-norace ${Date.now()}`,
			category: 'class',
			discipline: 'Spin',
			starts_at: instance
		});

		// USER_A is the Richmond owner → would be a race director on an athletic
		// event. On a class the whole athletic branch is gated off, so even the
		// owner sees no race control + no Submit-my-time.
		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${eventId}`);
		await expect(page.getByRole('heading', { name: /e2e-class-norace/ })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: 'Race control' })).toHaveCount(0);
		await expect(page.getByText('Submit my time')).toHaveCount(0);
		await expect(page.getByRole('heading', { name: /^Results/ })).toHaveCount(0);
		// The attendance-only marker is shown instead.
		await expect(page.getByText(/Attendance-only event/)).toBeVisible();

		// Data layer: the category gate is enforced by triggers
		// (event_is_athletic, migration 20261227_001), so a direct service-role
		// insert of a race session or a result for this class is rejected with
		// check_violation — the gate is the schema, not just the hidden button.
		const { error: raceErr } = await admin.from('race_sessions').insert({
			event_id: eventId,
			instance_start: instance,
			status: 'armed'
		});
		expect(raceErr).not.toBeNull();
		expect(raceErr?.code).toBe('23514');

		const { error: resultErr } = await admin.from('event_results').insert({
			event_id: eventId,
			instance_start: instance,
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			finisher_status: 'finished'
		});
		expect(resultErr).not.toBeNull();
		expect(resultErr?.code).toBe('23514');
	});
});

test.describe('/social — discover a class by cadence + weekday', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	const discipline = `E2E Spin Cadence ${Date.now()}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('events')
			.insert({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title: 'E2E Cadence Class',
				category: 'class',
				discipline,
				starts_at: '2026-07-06T18:00:00.000Z',
				recurrence_freq: 'weekly',
				recurrence_byday: ['MO']
			})
			.select('id')
			.single();
		eventId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (eventId) await admin.from('events').delete().eq('id', eventId);
	});

	test('cadence=weekly keeps the weekly class; cadence=one_off + weekday=TU hide it', async ({
		page
	}) => {
		await page.goto('/social?tab=discover');

		// Narrow to the seeded class by its unique discipline so other public
		// events near the fix can't interfere with the visibility assertions.
		await page.getByTestId('discover-search').fill(discipline);
		const results = page.getByTestId('discover-results');
		const row = results.getByRole('link', { name: new RegExp(discipline) });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row).toHaveAttribute(
			'href',
			new RegExp(`/clubs/${RICHMOND_SLUG}/events/${eventId}`)
		);

		// Cadence weekly keeps the recurring class; one_off drops it (it has a
		// recurrence_freq).
		await page.getByTestId('discover-cadence').selectOption('weekly');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-cadence').selectOption('one_off');
		await expect(row).toBeHidden({ timeout: 10_000 });

		// Back to weekly, then narrow by weekday: Monday keeps it, Tuesday drops
		// it (recurrence_byday is ['MO']).
		await page.getByTestId('discover-cadence').selectOption('weekly');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-day').selectOption('MO');
		await expect(row).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('discover-day').selectOption('TU');
		await expect(row).toBeHidden({ timeout: 10_000 });
	});
});
