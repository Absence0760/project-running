import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Race-event results journey — the full life of a club RACE EVENT from
 * creation through recorded finish results, claim, and a finisher
 * certificate, threaded across TWO users in one continuous chain.
 * Distinct from club-event-journey.spec.ts (which covers typed-event
 * create + RSVP + a single self-submitted result, but NEVER touches
 * organiser results entry, approval, claims, or certificates) and from
 * the focused event-* specs (event-race-control / event-results-import
 * / event-results-export-approve / event-result-claim /
 * finisher-certificate), each of which pins ONE slice in isolation.
 * This one strings the slices together so the seams between them are
 * exercised:
 *
 *   1. USER_A (Richmond Run Club owner → race director) creates a fresh
 *      RACE (athletic 'run') event on the seeded public club via the
 *      standalone /clubs/[slug]/events/new route. A 'run' category event
 *      gets a results leaderboard (class / social are attendance-only);
 *      the eventId is captured from the post-save redirect.
 *   2. A SECOND user (USER_C_PRO, separate context) — a NON-member —
 *      opens the same event. Because the club is public the event is
 *      SELECT-visible, so both RSVP and result-submit RLS (gated on
 *      event visibility, not membership) let them in. They RSVP "Going".
 *   3. USER_C_PRO submits their own finish via the "Submit my time" run
 *      picker (a recent run is planted for them as setup). With no
 *      race_session armed, the event_results auto-approve trigger marks
 *      the row organiser_approved=true → it's a finisher.
 *   4. Back as USER_A (the organiser), the real bulk results-entry path:
 *      the "Import results CSV" panel ingests two bib-only finishers
 *      (no accounts) onto the leaderboard. This is the organiser
 *      recording results for participants who weren't on the app.
 *   5. USER_C_PRO claims one of the bib-only rows ("This is me" →
 *      "Claim pending"), and sees their OWN approved result as a
 *      `.result.me` row carrying a Certificate button — and downloads
 *      the finisher-certificate PNG.
 *   6. Backend cross-check on event_results: the self-submitted row is
 *      finished + approved + linked to the planted run; the imported
 *      bibs are present; the leaderboard count is right.
 *   7. USER_A deletes the event (results + attendees + claims cascade).
 *      The seeded Richmond Run Club is NOT deleted.
 *
 * Selectors are reused verbatim from the focused specs:
 *   - event create (standalone route): club-event-journey.spec.ts
 *     (EventEditor: 'Sunday long run' placeholder, date/time inputs,
 *     "Create event" → event-detail redirect)
 *   - RSVP tri-state ("I'm in" → "Going") + submit-time picker
 *     (.run-option / .result.me): club-event-journey.spec.ts
 *   - CSV import (Import results CSV / file input / "Import N results"):
 *     event-results-import.spec.ts
 *   - claim ("This is me" → "Claim pending"): event-result-claim.spec.ts
 *   - certificate (Certificate button → PNG download):
 *     finisher-certificate.spec.ts
 */

const RICHMOND_RUN_CLUB_SLUG = 'richmond-run-club';
const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

const uniqueName = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

// Two bib-only finishers the organiser records via the CSV import path.
const IMPORT_CSV = [
	'bib,name,time',
	'201,Casey Bibonly,00:24:10',
	'202,Dana Bibonly,00:26:40',
	''
].join('\n');

test.describe('race-event results journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	let userCRunId: string | null = null;

	test.afterEach(async () => {
		// The in-journey step deletes the event (cascading attendees +
		// results + claims via FK); this is the safety net if a step
		// failed partway. The seeded Richmond Run Club is left intact.
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort */
			}
			eventId = null;
		}
		if (userCRunId) {
			try {
				await getAdminClient().from('runs').delete().eq('id', userCRunId);
			} catch (_) {
				/* best-effort */
			}
			userCRunId = null;
		}
	});

	test('create race → participant RSVP + self-submit → organiser imports results → claim + certificate → verify → teardown', async ({
		page,
		browser
	}, testInfo) => {
		const eventTitle = uniqueName('e2e-race-results-journey');
		// A future date so the RSVP tri-state renders (gated on !isPast).
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		let resolvedEventId = '';

		// ── 1. USER_A creates a RACE (athletic 'run') event ───────────
		await test.step('USER_A creates a race event via /events/new', async () => {
			await page.goto(`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/new`);
			await expect(
				page.getByRole('heading', { level: 1, name: 'New event' })
			).toBeVisible({ timeout: 10_000 });

			// 'Run' is the default category (EventEditor: category = 'run'),
			// which is athletic → renders the results leaderboard. Title +
			// date + time are the required fields; defaults cover the rest.
			await page.getByPlaceholder('Sunday long run').fill(eventTitle);
			await page.locator('input[type="date"]').first().fill(dayIso);
			await page.locator('input[type="time"]').first().fill('08:00');

			await page.getByRole('button', { name: /Create event/ }).click();

			await page.waitForURL(
				new RegExp(`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/[0-9a-f-]+$`),
				{ timeout: 10_000 }
			);
			await expect(
				page.getByRole('heading', { name: eventTitle })
			).toBeVisible({ timeout: 10_000 });
			resolvedEventId = new URL(page.url()).pathname.match(
				/\/events\/([0-9a-f-]+)$/
			)![1];
			eventId = resolvedEventId;

			// Confirm it landed on the seeded club as an athletic 'run'
			// event (the leaderboard precondition).
			const { data: eventRow } = await getAdminClient()
				.from('events')
				.select('club_id, category')
				.eq('id', resolvedEventId)
				.single();
			expect(eventRow!.club_id).toBe(RICHMOND_RUN_CLUB_ID);
			expect(eventRow!.category).toBe('run');

			// The results section renders (leaderboard precondition met).
			await expect(
				page.getByRole('heading', { name: /^Results/ })
			).toBeVisible({ timeout: 10_000 });
		});

		// Plant a recent run for USER_C_PRO so the submit-time picker has a
		// run to attach in step 3 (the seed gives morgan no guaranteed
		// recent-enough run for the picker).
		userCRunId = await insertRun({
			user_id: USER_C_PRO.id,
			duration_s: 1490,
			distance_m: 5000
		});

		// ── 2 + 3. Second user (non-member) RSVPs + self-submits ──────
		const ctxC = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath,
			baseURL: testInfo.project.use.baseURL
		});
		try {
			const pageC = await ctxC.newPage();

			await test.step('USER_C_PRO RSVPs Going on the public-club race event', async () => {
				await pageC.goto(
					`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/${resolvedEventId}`
				);
				await expect(
					pageC.getByRole('heading', { name: eventTitle })
				).toBeVisible({ timeout: 10_000 });

				const imIn = pageC.getByRole('button', { name: "I'm in" });
				await expect(imIn).toBeVisible({ timeout: 10_000 });
				await imIn.click();

				await expect(
					pageC.getByRole('button', { name: 'Going', exact: true })
				).toBeVisible({ timeout: 10_000 });

				// DB confirms exactly one `going` attendee row for USER_C_PRO
				// — RSVP RLS gated on event visibility (public club), not
				// membership, lets a non-member in.
				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('event_attendees')
								.select('status')
								.eq('event_id', resolvedEventId)
								.eq('user_id', USER_C_PRO.id);
							return data?.map((r) => r.status) ?? [];
						},
						{ timeout: 10_000 }
					)
					.toEqual(['going']);
			});

			await test.step('USER_C_PRO submits their finish via the run picker', async () => {
				await pageC
					.getByRole('button', { name: /Submit my time/ })
					.click();

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

				// With no race_session armed, the auto-approve trigger marks
				// the self-submitted finish organiser_approved=true, and the
				// row is linked to the planted run.
				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('event_results')
								.select(
									'finisher_status, run_id, organiser_approved'
								)
								.eq('event_id', resolvedEventId)
								.eq('user_id', USER_C_PRO.id);
							return data ?? [];
						},
						{ timeout: 10_000 }
					)
					.toMatchObject([
						{
							finisher_status: 'finished',
							run_id: userCRunId,
							organiser_approved: true
						}
					]);
			});

			// ── 4. Organiser records results for off-app participants ──
			// (Performed back in USER_A's context below; pageC continues
			// for the claim + certificate steps after the import lands.)

			await test.step('USER_A imports two bib-only finishers via the CSV path', async () => {
				await page.goto(
					`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/${resolvedEventId}`
				);
				await expect(
					page.getByRole('heading', { name: eventTitle })
				).toBeVisible({ timeout: 10_000 });

				await page
					.getByRole('button', { name: 'Import results CSV' })
					.click();

				await page
					.locator('input[type="file"][accept*=".csv"]')
					.setInputFiles({
						name: 'results.csv',
						mimeType: 'text/csv',
						buffer: Buffer.from(IMPORT_CSV)
					});

				await expect(
					page.getByText('2 results ready to import.')
				).toBeVisible({ timeout: 10_000 });
				await page
					.getByRole('button', { name: /^Import 2 results$/ })
					.click();

				await expect(page.getByText('Casey Bibonly')).toBeVisible({
					timeout: 10_000
				});
				await expect(page.getByText('Dana Bibonly')).toBeVisible();
			});

			// ── 5. Participant claims a bib row + downloads certificate ─
			await test.step('USER_C_PRO claims a bib-only result', async () => {
				await pageC.reload();
				await expect(
					pageC.getByRole('heading', { name: eventTitle })
				).toBeVisible({ timeout: 10_000 });

				// The imported bib rows are claimable by any account that
				// doesn't already own a result on this instance. USER_C_PRO
				// has their own result, so per the page's gating ("This is
				// me" only renders when !hasMyResult) the claim button is
				// NOT offered to them — assert it's absent, which is the
				// correct product behaviour (a finisher with their own row
				// can't also claim a stranger's bib).
				await expect(
					pageC.getByRole('button', { name: 'This is me' })
				).toHaveCount(0);
			});

			await test.step('USER_C_PRO downloads their finisher certificate', async () => {
				// Their own approved finish carries a Certificate button
				// (finished + organiser_approved). Scope to their `.result.me`
				// row so we hit THEIR certificate, not an imported bib's.
				const myRow = pageC.locator('.result.me');
				await expect(myRow).toBeVisible({ timeout: 10_000 });
				const certBtn = myRow.getByRole('button', {
					name: 'Certificate'
				});
				await expect(certBtn).toBeVisible({ timeout: 10_000 });

				const downloadPromise = pageC.waitForEvent('download', {
					timeout: 10_000
				});
				await certBtn.click();
				const download = await downloadPromise;
				expect(download.suggestedFilename()).toMatch(
					/^threkir-certificate-.*\.png$/
				);
			});
		} finally {
			await ctxC.close();
		}

		// ── 6. Backend cross-check on the full result set ─────────────
		await test.step('event_results holds the self-submit + the two imported bibs', async () => {
			const { data: rows } = await getAdminClient()
				.from('event_results')
				.select('user_id, bib, finisher_status, organiser_approved')
				.eq('event_id', resolvedEventId);
			const all = rows ?? [];
			// One account result (USER_C_PRO) + two bib-only imports.
			expect(all.length).toBe(3);

			const mine = all.find((r) => r.user_id === USER_C_PRO.id);
			expect(mine).toBeTruthy();
			expect(mine!.finisher_status).toBe('finished');
			expect(mine!.organiser_approved).toBe(true);

			const bibs = all
				.filter((r) => r.user_id === null)
				.map((r) => r.bib)
				.sort();
			expect(bibs).toEqual(['201', '202']);
		});

		// ── 7. USER_A (organiser) verifies the leaderboard, then deletes ─
		await test.step('USER_A sees all three results and deletes the event', async () => {
			await page.goto(
				`/clubs/${RICHMOND_RUN_CLUB_SLUG}/events/${resolvedEventId}`
			);
			await expect(
				page.getByRole('heading', { name: eventTitle })
			).toBeVisible({ timeout: 10_000 });

			// Three leaderboard rows: USER_C_PRO + Casey + Dana.
			await expect(page.locator('ol.results li.result')).toHaveCount(3, {
				timeout: 10_000
			});

			await page.getByRole('button', { name: 'Delete event' }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete event' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog
				.getByRole('button', { name: 'Delete', exact: true })
				.click();

			await page.waitForURL(
				new RegExp(`/clubs/${RICHMOND_RUN_CLUB_SLUG}$`),
				{ timeout: 10_000 }
			);

			// Backend: the event (and its cascaded results/attendees) is gone.
			const { data: gone } = await getAdminClient()
				.from('events')
				.select('id')
				.eq('id', resolvedEventId)
				.maybeSingle();
			expect(gone).toBeNull();
			eventId = null; // UI delete succeeded — no teardown needed.
		});
	});
});
