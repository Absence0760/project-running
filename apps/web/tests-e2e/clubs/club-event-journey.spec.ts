import { expect, test } from '@playwright/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { deleteClub, insertRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Club-event journey — the full lifecycle of a brand-new club EVENT,
 * walked end-to-end across every surface a one-off run event appears
 * on, and across TWO users in one continuous chain. Distinct from the
 * focused event-* specs (event-create / event-rsvp / event-result-claim
 * / event-attendance), each of which pins ONE slice in isolation; this
 * one strings the slices together so the seams between them are
 * exercised too:
 *
 *   1. USER_A creates a fresh open/public club via /clubs/new and lands
 *      on /clubs/[slug] (slug is generated server-side, captured here).
 *   2. USER_A creates a dated one-off run event via the standalone
 *      /clubs/[slug]/events/new route (EventEditor → goto the new event
 *      detail page on save). Future date so the RSVP tri-state renders.
 *   3. A SECOND user (USER_C_PRO, a separate browser context) opens the
 *      same event on the PUBLIC club — no membership needed, the event
 *      is SELECT-visible — and RSVPs "Going". The going-count + their own
 *      row reflect it; the DB confirms a single `going` attendee row.
 *   4. USER_C_PRO submits their own time via the "Submit my time" run
 *      picker (a recent run is planted for them as setup), which lands
 *      as a `.result.me` leaderboard row.
 *   5. Back as USER_A (the organiser), the event detail shows the
 *      attendee AND the result in the leaderboard.
 *   6. USER_A deletes the event (→ back to /clubs/[slug], event gone),
 *      then deletes the club (→ back to /clubs, club gone).
 *
 * The club + its event + the planted run are all swept in afterEach for
 * safety even though the in-journey delete steps cover the happy path.
 *
 * Selectors are reused verbatim from the focused specs:
 *   - club create + delete: cross-cutting/clubs-journey.spec.ts
 *   - event create (standalone route): event-organiser-create.spec.ts
 *     + the EventEditor field selectors from event-create.spec.ts
 *   - RSVP tri-state ("I'm in" → "Going"): event-rsvp.spec.ts
 *   - submit-time picker (.result.me / button.run-option): event-rsvp.spec.ts
 *   - event delete (.modal "Delete event" → "Delete"): event-delete.spec.ts
 */

const uniqueName = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

// Anchors a /clubs/[slug] URL on a digit so the regex can't match
// /clubs/new still in flight (matches clubs-journey.spec.ts).
const SLUG_URL = /\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/;

test.describe('club-event journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let clubId: string | null = null;
	let userCRunId: string | null = null;

	test.beforeEach(async () => {
		// 5 clubs/hour cap (migration 20260907_001) is shared across every
		// spec that creates clubs as USER_A in this shard — reset the bucket
		// so this test always lands at count=1.
		await resetRateLimit(USER_A.id, 'create_club');
	});

	test.afterEach(async () => {
		// The in-journey steps delete the event (cascading attendees +
		// results) and the club; this is the safety net if a step failed
		// partway. Deleting the club cascades its events.
		if (clubId) {
			try {
				await deleteClub(clubId);
			} catch (_) {
				/* best-effort */
			}
			clubId = null;
		}
		if (userCRunId) {
			try {
				const admin = getAdminClient();
				await admin.from('runs').delete().eq('id', userCRunId);
			} catch (_) {
				/* best-effort */
			}
			userCRunId = null;
		}
	});

	test('create club → create event → cross-user RSVP + result → organiser verifies → teardown', async ({
		page,
		browser
	}, testInfo) => {
		const clubName = uniqueName('e2e-event-journey');
		const eventTitle = uniqueName('e2e-event-journey-event');
		// A future date so the RSVP tri-state renders (gated on !isPast).
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		let slug = '';
		let eventId = '';

		// ── 1. Create the club (open/public by default) ───────────────
		await test.step('USER_A creates a club via /clubs/new', async () => {
			await page.goto('/clubs/new');
			await page.locator('input[type="text"]').first().fill(clubName);
			await page.getByRole('button', { name: 'Create club' }).click();
			await page.waitForURL(SLUG_URL, { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { level: 1, name: clubName })
			).toBeVisible({ timeout: 10_000 });

			slug = new URL(page.url()).pathname.split('/').pop()!;
			const admin = getAdminClient();
			const { data: clubRow } = await admin
				.from('clubs')
				.select('id, is_public')
				.eq('slug', slug)
				.single();
			clubId = clubRow!.id as string;
			// The journey relies on the default open/public club so USER_C_PRO
			// can SELECT (and therefore RSVP to) the event without joining.
			expect(clubRow!.is_public).toBe(true);
		});

		// ── 2. Create a dated one-off run event ───────────────────────
		await test.step('USER_A creates a one-off run event via /events/new', async () => {
			await page.goto(`/clubs/${slug}/events/new`);
			await expect(
				page.getByRole('heading', { level: 1, name: 'New event' })
			).toBeVisible({ timeout: 10_000 });

			// "Group run" (an athletic category) is the default — title + date
			// + time are the required fields; defaults cover the rest.
			await page.getByPlaceholder('Sunday long run').fill(eventTitle);
			await page.locator('input[type="date"]').first().fill(dayIso);
			await page.locator('input[type="time"]').first().fill('07:30');

			await page.getByRole('button', { name: /Create event/ }).click();

			// The standalone route navigates to the event detail on save.
			await page.waitForURL(new RegExp(`/clubs/${slug}/events/[0-9a-f-]+$`), {
				timeout: 10_000
			});
			await expect(
				page.getByRole('heading', { name: eventTitle })
			).toBeVisible({ timeout: 10_000 });
			eventId = new URL(page.url()).pathname.match(/\/events\/([0-9a-f-]+)$/)![1];
		});

		// Plant a recent run for USER_C_PRO so the submit-time picker has a
		// run to attach in step 4 (the seed gives morgan no guaranteed runs).
		userCRunId = await insertRun({
			user_id: USER_C_PRO.id,
			duration_s: 1800,
			distance_m: 5000
		});

		// ── 3. Second user RSVPs "Going" ──────────────────────────────
		const ctxC = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath,
			baseURL: testInfo.project.use.baseURL
		});
		try {
			const pageC = await ctxC.newPage();

			await test.step('USER_C_PRO RSVPs Going on the public-club event', async () => {
				await pageC.goto(`/clubs/${slug}/events/${eventId}`);
				await expect(
					pageC.getByRole('heading', { name: eventTitle })
				).toBeVisible({ timeout: 10_000 });

				const imIn = pageC.getByRole('button', { name: "I'm in" });
				await expect(imIn).toBeVisible({ timeout: 10_000 });
				await imIn.click();

				// The going button flips to its "Going" state — the count it
				// carries is now this single RSVP.
				await expect(
					pageC.getByRole('button', { name: 'Going', exact: true })
				).toBeVisible({ timeout: 10_000 });

				// DB confirms exactly one `going` attendee row for USER_C_PRO.
				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('event_attendees')
								.select('status')
								.eq('event_id', eventId)
								.eq('user_id', USER_C_PRO.id);
							return data?.map((r) => r.status) ?? [];
						},
						{ timeout: 10_000 }
					)
					.toEqual(['going']);

				// The going-count chip on the RSVP button reflects the one RSVP.
				await expect(
					pageC.locator('.rsvp-going .rsvp-count')
				).toHaveText('1', { timeout: 10_000 });
			});

			// ── 4. Same user submits their own time as a result ───────
			await test.step('USER_C_PRO submits their time via the run picker', async () => {
				await pageC.getByRole('button', { name: /Submit my time/ }).click();

				const picker = pageC.locator('.picker');
				await expect(picker).toBeVisible({ timeout: 10_000 });
				await expect(
					picker.getByRole('heading', { name: 'Attach a run' })
				).toBeVisible();

				const runOption = picker.locator('button.run-option').first();
				await expect(runOption).toBeVisible({ timeout: 10_000 });
				await runOption.click();

				// The submitter's own result lands as a `.result.me` row.
				await expect(pageC.locator('.result.me')).toBeVisible({
					timeout: 10_000
				});

				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('event_results')
								.select('finisher_status, run_id')
								.eq('event_id', eventId)
								.eq('user_id', USER_C_PRO.id);
							return data ?? [];
						},
						{ timeout: 10_000 }
					)
					.toMatchObject([{ finisher_status: 'finished' }]);
			});
		} finally {
			await ctxC.close();
		}

		// ── 5. Organiser verifies the attendee + result ───────────────
		await test.step('USER_A (organiser) sees the attendee and the result', async () => {
			await page.goto(`/clubs/${slug}/events/${eventId}`);
			await expect(
				page.getByRole('heading', { name: eventTitle })
			).toBeVisible({ timeout: 10_000 });

			// Attendee list carries USER_C_PRO (Morgan Lee, seed.sql).
			await expect(
				page.locator('.attendee', { hasText: 'Morgan Lee' })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByRole('heading', { name: 'Attendees (1)' })
			).toBeVisible({ timeout: 10_000 });

			// Result leaderboard carries the submitted finish.
			await expect(page.locator('ol.results li.result')).toHaveCount(1, {
				timeout: 10_000
			});
		});

		// ── 6. Teardown — delete event, then club ─────────────────────
		await test.step('USER_A deletes the event', async () => {
			await page.getByRole('button', { name: 'Delete event' }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete event' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

			await page.waitForURL(new RegExp(`/clubs/${slug}$`), { timeout: 10_000 });
			await page.getByRole('tab', { name: /^Events/ }).click();
			await expect(
				page.locator('a[href*="/events/"]', { hasText: eventTitle })
			).toHaveCount(0, { timeout: 10_000 });
		});

		await test.step('USER_A deletes the club', async () => {
			await page.getByRole('button', { name: 'Delete club' }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete club' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await page.waitForURL(/\/clubs(\?.*)?$/, { timeout: 10_000 });

			await expect(
				page.getByRole('heading', { name: clubName, exact: true })
			).toHaveCount(0);
			clubId = null;
		});
	});
});
