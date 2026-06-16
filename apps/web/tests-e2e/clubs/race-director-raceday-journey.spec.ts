import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import {
	deleteEvent,
	insertCheckpoint,
	insertCrossing,
	insertEvent,
	insertRacePings
} from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Race-director race-day operations — the full stitched journey
 * (race_director_ops.md P1→P4), not the isolated slices that
 * checkpoint-board.spec.ts and event-results-export-approve.spec.ts
 * already pin.
 *
 * One arc, walked across the real director surfaces:
 *   1. The organiser builds the course on the event page: three
 *      checkpoints, the middle one a cutoff, the last the finish — and
 *      the cutoff checkpoint flags `requires_weigh_in` (the Art 9 gate).
 *   2. The organiser ARMS then STARTS the race through the Race-control
 *      card (handleArm / handleStart) — the server stamps `started_at`,
 *      flipping the panel armed → running.
 *   3. Two saga runners' live positions flow in as `race_pings` while
 *      the race runs (the spectator-side feed; the board itself reads
 *      crossings, the pings are the live-tracking input that proves the
 *      running session accepts them).
 *   4. Aid-station crossings are logged. The board (`/board?instance=`)
 *      projects each runner against the per-checkpoint cutoffs: one
 *      runner reaches the finish inside cutoff (Finished + Safe), one
 *      blows the cutoff (DNF). A weigh-in crossing (body weight +
 *      medical hold) is recorded through the gated organiser RPC and
 *      read back via the organiser-only crossings fetch.
 *   5. The organiser marks a third runner DNF from the board, then ENDS
 *      the race and the result is published + approved on the leaderboard
 *      (auto-approve session) and surfaced on the public results page.
 *
 * Director = USER_A (owns Richmond Run Club → club admin ⇒ race_director
 * + event organiser). Runners = ephemeral saga users so this spec owns
 * and wipes every identity it plants; the event delete cascades the
 * checkpoints / crossings / race_session / pings, and the saga teardown
 * removes the users + their event_results.
 *
 * GPS points are planted in Melbourne's Docklands (well clear of the
 * seed's 200 m privacy zones around the Sydney/Melbourne CBDs the
 * insertRacePings comment warns about), so the `race_pings_drop_in_zone`
 * BEFORE-INSERT trigger doesn't silently swallow them.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

// Docklands, Melbourne — outside the seeded privacy zones.
const PING_BASE = { lat: -37.8155, lng: 144.945 };

test.describe('saga: race director runs a race day end-to-end', () => {
	test.describe.configure({ timeout: 120_000 });

	// One-off event whose start is in the recent past so the running
	// elapsed clock is positive and crossings land inside / outside the
	// cutoff deterministically. next_instance_start for a non-recurring
	// event === new Date(starts_at).toISOString(), so activeInstance (what
	// the Arm/Start writes + the board URL carries) equals this string.
	const startsAt = new Date(Date.now() - 90 * 60 * 1000).toISOString();
	const startMs = new Date(startsAt).getTime();

	let eventId: string | null = null;
	let runners: SagaUser[] = [];

	test.beforeAll(async () => {
		runners = await createSagaUsers(2, {
			displayNames: ['Ada Finisher', 'Boyd Cutoff']
		});
	});

	test.afterAll(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch {
				/* cascade best-effort */
			}
			eventId = null;
		}
		// Saga teardown wipes any event_results rows the runners own via the
		// auth.users CASCADE; clear the bib-only finisher we planted too.
		try {
			await getAdminClient()
				.from('event_results')
				.delete()
				.eq('bib', '777');
		} catch {
			/* best-effort */
		}
		if (runners.length) await deleteSagaUsers(runners);
	});

	test('build course → arm → start → pings in → crossings + cutoffs + weigh-in → DNF → end → published results', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const director = await ctx.newPage();

		const [ada, boyd] = runners;
		let cpStart = '';
		let cpAid = '';
		let cpFinish = '';

		try {
			eventId = await insertEvent({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title: `e2e raceday journey ${Date.now()}`,
				starts_at: startsAt,
				distance_m: 21000,
				category: 'run'
			});
			// Stable instance the whole journey keys on.
			const instance = new Date(startsAt).toISOString();

			await test.step('organiser builds the course (3 checkpoints, cutoff + weigh-in)', async () => {
				cpStart = await insertCheckpoint({
					event_id: eventId!,
					created_by: USER_A.id,
					name: 'Aid 1',
					ordinal: 1,
					position_m: 7000,
					cutoff_elapsed_s: 3600 // 60 min
				});
				// Cutoff aid station that also collects a weigh-in (Art 9 gate).
				cpAid = await insertCheckpoint({
					event_id: eventId!,
					created_by: USER_A.id,
					name: 'Aid 2 (cutoff)',
					ordinal: 2,
					position_m: 14000,
					cutoff_elapsed_s: 4500, // 75 min
					requires_weigh_in: true
				});
				cpFinish = await insertCheckpoint({
					event_id: eventId!,
					created_by: USER_A.id,
					name: 'Finish',
					ordinal: 3,
					position_m: 21000,
					cutoff_elapsed_s: 9000 // 150 min
				});

				await director.goto(`/clubs/richmond-run-club/events/${eventId}`);
				// The checkpoint manager + race-control card only render for a
				// race director on an athletic event — confirms USER_A is one.
				await expect(director.getByTestId('checkpoint-manager')).toBeVisible({
					timeout: 15_000
				});
				const manager = director.getByTestId('checkpoint-manager');
				await expect(manager.getByText('Aid 2 (cutoff)')).toBeVisible();
				await expect(director.getByTestId('checkpoint-row')).toHaveCount(3);
			});

			await test.step('arm the race through the Race-control card', async () => {
				// raceArmHint is the pre-arm copy; armRace is the button.
				await expect(director.getByText('Arm the race when everyone is ready')).toBeVisible();
				await director.getByRole('button', { name: 'Arm race' }).click();
				// Panel flips to the armed state (armedLabel + GO button).
				await expect(director.getByText('Armed', { exact: true })).toBeVisible({
					timeout: 10_000
				});
				await expect(director.getByRole('button', { name: 'GO' })).toBeVisible();

				const { data } = await getAdminClient()
					.from('race_sessions')
					.select('status, is_auto_approve')
					.eq('event_id', eventId!)
					.eq('instance_start', instance)
					.single();
				expect(data?.status).toBe('armed');
				// Default "Auto-approve submitted results" stays checked.
				expect(data?.is_auto_approve).toBe(true);
			});

			await test.step('start the race — server stamps started_at, panel goes running', async () => {
				await director.getByRole('button', { name: 'GO' }).click();
				await expect(director.getByText('Running', { exact: true })).toBeVisible({
					timeout: 10_000
				});
				await expect(director.getByRole('button', { name: 'End race' })).toBeVisible();

				const { data } = await getAdminClient()
					.from('race_sessions')
					.select('status, started_at, started_by')
					.eq('event_id', eventId!)
					.eq('instance_start', instance)
					.single();
				expect(data?.status).toBe('running');
				expect(data?.started_at).not.toBeNull();
				expect(data?.started_by).toBe(USER_A.id);

				// The board derives each runner's elapsed-since-start from
				// race_sessions.started_at. handleStart stamps it at ~now, but
				// this journey's crossings are anchored 90 min in the past (so a
				// blown cutoff is deterministic, the same trick checkpoint-board
				// uses with a 2h-ago start). Back-date started_at to the event's
				// nominal start so the cutoff projection reads the way a race that
				// actually began 90 min ago would — without it every leg clamps to
				// elapsed 0 and nothing ever misses a cutoff.
				const { error: backdateErr } = await getAdminClient()
					.from('race_sessions')
					.update({ started_at: startsAt })
					.eq('event_id', eventId!)
					.eq('instance_start', instance);
				expect(backdateErr).toBeNull();
			});

			await test.step("runners' live positions flow in as race pings", async () => {
				// The race is `running`, so the per-runner race_pings insert RLS
				// (insert-self-while-running) is satisfied; service-role bypasses
				// the auth.uid()=user_id half but the running-state half is real,
				// so this also proves the session is genuinely running.
				await insertRacePings({
					event_id: eventId!,
					instance_start: instance,
					runners: [
						{
							user_id: ada.id,
							points: [
								{ lat: PING_BASE.lat, lng: PING_BASE.lng, distance_m: 5000, elapsed_s: 1500 },
								{
									lat: PING_BASE.lat + 0.004,
									lng: PING_BASE.lng + 0.004,
									distance_m: 9000,
									elapsed_s: 2700
								}
							]
						},
						{
							user_id: boyd.id,
							points: [
								{ lat: PING_BASE.lat + 0.001, lng: PING_BASE.lng, distance_m: 4000, elapsed_s: 1800 }
							]
						}
					]
				});
				const { count } = await getAdminClient()
					.from('race_pings')
					.select('id', { count: 'exact', head: true })
					.eq('event_id', eventId!)
					.eq('instance_start', instance);
				expect(count).toBe(3);
			});

			await test.step('aid-station crossings are logged (account + bib runners)', async () => {
				// Ada (account): reaches all three checkpoints inside cutoff.
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpStart,
					instance_start: instance,
					user_id: ada.id,
					runner_name: ada.displayName,
					in_time: new Date(startMs + 30 * 60 * 1000).toISOString()
				});
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpAid,
					instance_start: instance,
					user_id: ada.id,
					runner_name: ada.displayName,
					in_time: new Date(startMs + 60 * 60 * 1000).toISOString()
				});
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpFinish,
					instance_start: instance,
					user_id: ada.id,
					runner_name: ada.displayName,
					in_time: new Date(startMs + 120 * 60 * 1000).toISOString()
				});
				// Boyd (account): blows the 75-min Aid 2 cutoff (reaches it at
				// +80 min) → projection grades it a miss ⇒ DNF.
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpStart,
					instance_start: instance,
					user_id: boyd.id,
					runner_name: boyd.displayName,
					in_time: new Date(startMs + 40 * 60 * 1000).toISOString()
				});
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpAid,
					instance_start: instance,
					user_id: boyd.id,
					runner_name: boyd.displayName,
					in_time: new Date(startMs + 80 * 60 * 1000).toISOString()
				});
				// A bib-only runner (account-optional identity) reaches Aid 1 only.
				await insertCrossing({
					event_id: eventId!,
					checkpoint_id: cpStart,
					instance_start: instance,
					bib: '777',
					runner_name: 'Pat Bibrunner',
					in_time: new Date(startMs + 35 * 60 * 1000).toISOString()
				});
			});

			await test.step('record a weigh-in through the gated organiser RPC', async () => {
				// The weigh-in UI is flag-gated off by default (PUBLIC_WEIGH_IN_ENABLED),
				// but the organiser RPC is the canonical writer. Aid 2 has
				// requires_weigh_in=true + we pass consent, so the Art 9 health
				// fields persist (decisions §150 fail-closed gate). The RPC
				// authorises on auth.uid() = an event organiser, so it must run
				// under USER_A's real JWT, not the service-role admin client
				// (whose auth.uid() is NULL → 42501).
				const director$ = await getUserClient({
					email: USER_A.email,
					password: USER_A.password
				});
				const { error } = await director$.rpc('upsert_checkpoint_crossing', {
					p_event_id: eventId,
					p_checkpoint_id: cpAid,
					p_instance_start: instance,
					p_user_id: ada.id,
					p_runner_name: ada.displayName,
					p_health_consent: true,
					p_body_weight_kg: 64.5,
					p_medical_hold: false
				});
				expect(error).toBeNull();

				// Read it back through the organiser-only fetch RPC (also
				// organiser-gated) and confirm the column-locked health field
				// came through.
				const { data } = await director$.rpc(
					'fetch_checkpoint_crossings_for_organiser',
					{ p_event_id: eventId, p_instance_start: instance }
				);
				const adaAid = (data as Array<Record<string, unknown>>).find(
					(c) => c.user_id === ada.id && c.checkpoint_id === cpAid
				);
				expect(adaAid?.body_weight_kg).not.toBeNull();
				expect(Number(adaAid?.body_weight_kg)).toBeCloseTo(64.5, 1);
			});

			await test.step('board projects per-runner progress + cutoff verdicts', async () => {
				// Click the real board link from the event page (carries the
				// correct ?instance=) rather than constructing the URL.
				await director.getByTestId('open-board').click();
				await director.waitForURL(/\/board\?instance=/, { timeout: 10_000 });

				const table = director.getByTestId('board-table');
				await expect(table).toBeVisible({ timeout: 15_000 });
				// Three identities: Ada (account), Boyd (account), Pat (bib).
				await expect(director.getByTestId('board-row')).toHaveCount(3);
				await expect(table.getByText('Ada Finisher')).toBeVisible();
				await expect(table.getByText('Boyd Cutoff')).toBeVisible();
				await expect(table.getByText('Pat Bibrunner')).toBeVisible();

				// Ada reached the finish inside every cutoff → Finished + Safe.
				const adaRow = director.getByTestId('board-row').filter({ hasText: 'Ada Finisher' });
				await expect(adaRow.getByText('Finished')).toBeVisible();
				await expect(adaRow.getByText('Safe').first()).toBeVisible();

				// Boyd blew the Aid 2 cutoff → DNF + a Missed verdict chip.
				const boydRow = director.getByTestId('board-row').filter({ hasText: 'Boyd Cutoff' });
				await expect(boydRow.getByText('DNF')).toBeVisible();
				await expect(boydRow.getByText('Missed').first()).toBeVisible();
			});

			await test.step('organiser marks the bib runner DNF from the board', async () => {
				const patRow = director.getByTestId('board-row').filter({ hasText: 'Pat Bibrunner' });
				await patRow.getByTestId('mark-dnf').click();
				// ConfirmDialog → confirm with the Mark DNF action.
				await director.getByRole('button', { name: 'Mark DNF' }).last().click();

				// The organiser DNF lands as a bib-keyed event_results row.
				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('event_results')
								.select('finisher_status')
								.eq('event_id', eventId!)
								.eq('instance_start', instance)
								.eq('bib', '777')
								.maybeSingle();
							return data?.finisher_status ?? null;
						},
						{ timeout: 10_000 }
					)
					.toBe('dnf');
			});

			await test.step('publish Ada as a finisher + end the race', async () => {
				// An auto-approve session publishes a submitted finisher as
				// approved on insert (event_results_set_approval_default). Plant
				// Ada's finish so the leaderboard + public results have a finisher.
				const { error } = await getAdminClient().from('event_results').insert({
					event_id: eventId,
					instance_start: instance,
					user_id: ada.id,
					finisher_name: ada.displayName,
					duration_s: 120 * 60,
					distance_m: 21000,
					finisher_status: 'finished'
				});
				expect(error).toBeNull();

				// End the race from the running panel (handleEnd('finished')).
				await director.goto(`/clubs/richmond-run-club/events/${eventId}`);
				await expect(director.getByRole('button', { name: 'End race' })).toBeVisible({
					timeout: 15_000
				});
				await director.getByRole('button', { name: 'End race' }).click();
				// The end-race ConfirmDialog confirms with the End race action.
				await director.getByRole('button', { name: 'End race' }).last().click();

				await expect
					.poll(
						async () => {
							const { data } = await getAdminClient()
								.from('race_sessions')
								.select('status')
								.eq('event_id', eventId!)
								.eq('instance_start', instance)
								.single();
							return data?.status ?? null;
						},
						{ timeout: 10_000 }
					)
					.toBe('finished');
			});

			await test.step('leaderboard shows the approved finisher (auto-approve, no PENDING)', async () => {
				await director.goto(`/clubs/richmond-run-club/events/${eventId}`);
				const adaResult = director.locator('li.result', { hasText: 'Ada Finisher' });
				await expect(adaResult).toBeVisible({ timeout: 15_000 });
				// Auto-approve session ⇒ no PENDING tag on the published finisher.
				await expect(adaResult.getByText('PENDING')).toHaveCount(0);

				// DB cross-check: the finisher row is organiser_approved.
				const { data } = await getAdminClient()
					.from('event_results')
					.select('organiser_approved, finisher_status')
					.eq('event_id', eventId!)
					.eq('instance_start', instance)
					.eq('user_id', ada.id)
					.single();
				expect(data?.organiser_approved).toBe(true);
				expect(data?.finisher_status).toBe('finished');
			});

			await test.step('public results page lists finishers + checkpoint splits', async () => {
				await director.goto(
					`/share/event/${eventId}/results?instance=${encodeURIComponent(instance)}`
				);
				const results = director.getByTestId('public-results');
				await expect(results).toBeVisible({ timeout: 15_000 });
				// Three crossing identities surface on the public splits board.
				await expect(director.getByTestId('public-results-row')).toHaveCount(3);
				await expect(results.getByText('Ada Finisher')).toBeVisible();
				// Ada finished inside cutoff; Boyd blew it → DNF on the public board.
				const adaPub = director
					.getByTestId('public-results-row')
					.filter({ hasText: 'Ada Finisher' });
				await expect(adaPub.getByText('Finished')).toBeVisible();
				const boydPub = director
					.getByTestId('public-results-row')
					.filter({ hasText: 'Boyd Cutoff' });
				await expect(boydPub.getByText('DNF')).toBeVisible();
			});
		} finally {
			await ctx.close();
		}
	});
});
