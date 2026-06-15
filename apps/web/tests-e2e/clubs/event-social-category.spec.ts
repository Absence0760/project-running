import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Typed events — the `social` category + the data-layer athletic guard.
 *
 * `event-category-typed.spec.ts` covers run (athletic) vs class (attendance +
 * discipline). `social` is the second attendance-only category and behaves
 * subtly differently from class: it hides the same athletic surface, but —
 * having no instructor discipline — shows NO discipline chip either. This is
 * an untested branch of the self-hiding contract.
 *
 * It also pins the defense-in-depth the UI gate sits on top of (migration
 * 20261227_001): a non-athletic event is un-result-able and un-race-able even
 * via a direct authenticated API call, so a client that ignores
 * `isAthleticCategory` still cannot write a result/race row. We assert that
 * through a REAL user JWT (not the service-role admin, which bypasses both RLS
 * and would mask whether the trigger fires) so the trigger is genuinely
 * exercised.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — social category + athletic guard', () => {
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

	test('Social event: detail hides athletic surface AND shows no discipline chip', async ({
		page
	}) => {
		const title = `e2e-social ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'social',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		// Attendance-only: no race panel, no leaderboard, no athletic stats.
		await expect(page.getByText('Submit my time')).toHaveCount(0);
		await expect(page.getByRole('heading', { name: /^Results/ })).toHaveCount(0);
		await expect(page.getByRole('heading', { name: 'Race control' })).toHaveCount(0);
		await expect(page.getByText('Target pace')).toHaveCount(0);
		// No athletic metric labels in the hero metric grid.
		await expect(page.locator('.metric .label', { hasText: 'Distance' })).toHaveCount(0);

		// Unlike a class, a social event carries no discipline → no chip.
		await expect(page.locator('.discipline-chip')).toHaveCount(0);

		// RSVP still applies to every category.
		await expect(page.getByRole('group', { name: /RSVP/i })).toBeVisible();
	});

	test('data-layer guard: a result/race-session insert is rejected on a non-athletic event', async ({}) => {
		// A class event (non-athletic). The category is what the trigger gates on.
		eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-guard ${Date.now()}`,
			category: 'class',
			discipline: 'Reformer pilates',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		const instanceStart = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

		// Authenticated as a REAL user (USER_A owns the club, so RLS would let an
		// athletic event through) — the trigger, not RLS, must be what blocks it.
		const user = await getUserClient({ email: USER_A.email, password: USER_A.password });

		const { error: resultErr } = await user.from('event_results').insert({
			event_id: eventId,
			instance_start: instanceStart,
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			finisher_status: 'finished'
		});
		expect(resultErr).not.toBeNull();
		expect(resultErr?.message).toMatch(/only allowed on run\/cycle events|not athletic/i);

		const { error: raceErr } = await user.from('race_sessions').insert({
			event_id: eventId,
			instance_start: instanceStart,
			status: 'armed'
		});
		expect(raceErr).not.toBeNull();
		expect(raceErr?.message).toMatch(/only allowed on run\/cycle events|not athletic/i);

		// And confirm nothing was written (service-role read — the rows must
		// genuinely not exist, not merely be RLS-invisible).
		const admin = getAdminClient();
		const { data: results } = await admin
			.from('event_results')
			.select('event_id')
			.eq('event_id', eventId);
		expect(results?.length ?? 0).toBe(0);
		const { data: races } = await admin
			.from('race_sessions')
			.select('event_id')
			.eq('event_id', eventId);
		expect(races?.length ?? 0).toBe(0);
	});
});
