import { test } from '@playwright/test';

import { expectReflows } from '../fixtures/reflow';
import { getAdminClient } from '../fixtures/local-supabase';
import {
	deleteEvent,
	deleteRoute,
	deleteRun,
	insertEvent,
	insertLivePings,
	insertRacePings,
	insertRaceSession,
	insertRoute,
	insertRouteMarker,
	insertRun
} from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * WCAG 1.4.10 reflow over the routes the static sweep could not reach.
 *
 * `reflow-narrow-viewport.spec.ts` walks the list surfaces, which render from
 * the seed. Five families do not: `/live/[id]`, `/live/event/[id]/[instance]`,
 * `/fundraisers/[id]`, `/segments/[id]` and a POPULATED `/messages/[[id]]`.
 * They were previously recorded as "measured" at 0 elements under `main`, and
 * that figure was attributed to missing seed data. Two of the five had a
 * different cause: the whole `/live/` tree rendered no `<main>` at all (the
 * shell-less layout branch gives none and neither page owned one), so the
 * measurement had no anchor regardless of what was in the database. That is
 * fixed separately; this spec is what proves these pages are measured with real
 * content in them.
 *
 * Fixtures are built at RUNTIME through the service-role client and torn down
 * in `finally`, matching every other spec in this suite. The alternative —
 * growing `seed.sql` — would have needed a `supabase db reset` to take effect,
 * which wipes a stack several sessions share, and would leave data whose
 * live/stale/finished meaning decays with the wall clock.
 *
 * Every route here asserts a populated locator (§ 534), because a spinner, a
 * not-found card, or an empty state fits any viewport trivially and would
 * report a false pass.
 */

// Each test navigates three viewports and waits for `networkidle` at each, on
// top of building its own fixtures — 15 navigations across the file. On a cold
// CI stack the first one pays the dev server's route compile: the segment case
// blew the default 30 s budget on its first attempt and then passed on retry in
// 8.5 s. Nothing here asserts a duration, so the budget is a cost of the
// measurement, not part of what is being measured.
test.describe.configure({ timeout: 90_000 });

const MELBOURNE_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

// Clear of the seeded 200 m privacy zone at (-37.8136, 144.9631) — the
// live-ping triggers coarsen or drop points inside it, which would take the
// trace (and the cards that read it) away from the measurement.
const COURSE = [
	{ lat: -37.82, lng: 144.97, elevation_m: 20 },
	{ lat: -37.818, lng: 144.972, elevation_m: 30 },
	{ lat: -37.816, lng: 144.974, elevation_m: 45 },
	{ lat: -37.814, lng: 144.976, elevation_m: 35 },
	{ lat: -37.812, lng: 144.978, elevation_m: 50 },
	{ lat: -37.81, lng: 144.98, elevation_m: 40 }
];

test.describe('no horizontal document scroll on the seeded dynamic routes', () => {
	test('a live run with a ping backlog, a course, and cut-offs', async ({ page }) => {
		const routeId = await insertRoute({
			user_id: USER_A.id,
			name: `e2e reflow course ${Date.now()}`,
			waypoints: COURSE,
			distance_m: 12000,
			elevation_m: 300,
			is_public: true
		});
		// `isFinishedStale` is checked before the backlog is hydrated and
		// returns early, so the row's projected end has to stay in the future
		// or the page resolves to Finished and the live cards never mount.
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
			duration_s: 86_400,
			distance_m: 4200,
			is_public: true,
			route_id: routeId
		});
		try {
			await insertRouteMarker({
				route_id: routeId,
				user_id: USER_A.id,
				kind: 'aid_station',
				label: 'Aid 1 — Riverside',
				lat: -37.818,
				lng: 144.972,
				meta: { services: ['water', 'food'] }
			});
			await insertRouteMarker({
				route_id: routeId,
				user_id: USER_A.id,
				kind: 'cutoff',
				label: 'Cut-off — halfway gate',
				lat: -37.814,
				lng: 144.976,
				meta: { cutoff_elapsed_s: 3600 }
			});
			// Two consecutive points carrying BOTH distance_m and elapsed_s is
			// what the recent-pace card needs; without it the card self-hides
			// and the widest row on the page never renders.
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ lat: -37.82, lng: 144.97, distance_m: 700, elapsed_s: 180 },
					{ lat: -37.818, lng: 144.972, distance_m: 1400, elapsed_s: 360 },
					{ lat: -37.816, lng: 144.974, distance_m: 2100, elapsed_s: 540 },
					{ lat: -37.814, lng: 144.976, distance_m: 2800, elapsed_s: 720 },
					{ lat: -37.812, lng: 144.978, distance_m: 3600, elapsed_s: 960 },
					{ lat: -37.81, lng: 144.98, distance_m: 4200, elapsed_s: 1200 }
				]
			});

			await expectReflows(page, `/live/${runId}`, {
				locator: '[data-testid="course-progress"]'
			});
		} finally {
			await deleteRun(runId);
			await deleteRoute(routeId);
		}
	});

	test('a running race session with a three-runner leaderboard', async ({ page }) => {
		const startsAt = new Date(Date.now() - 35 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: MELBOURNE_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e reflow race ${Date.now()}`,
			starts_at: startsAt
		});
		try {
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'running',
				started_at: startsAt,
				started_by: USER_A.id
			});
			await insertRacePings({
				event_id: eventId,
				instance_start: startsAt,
				runners: [
					{
						user_id: USER_A.id,
						points: [
							{ lat: -37.818, lng: 144.972, distance_m: 5200, elapsed_s: 1380 },
							{ lat: -37.814, lng: 144.976, distance_m: 7900, elapsed_s: 2060 }
						]
					},
					{
						user_id: USER_B.id,
						points: [
							{ lat: -37.8176, lng: 144.9714, distance_m: 4800, elapsed_s: 1440 },
							{ lat: -37.815, lng: 144.9745, distance_m: 7100, elapsed_s: 2065 }
						]
					},
					{
						user_id: USER_C_PRO.id,
						points: [
							{ lat: -37.8172, lng: 144.9708, distance_m: 4300, elapsed_s: 1500 },
							{ lat: -37.8158, lng: 144.9738, distance_m: 6500, elapsed_s: 2070 }
						]
					}
				]
			});

			await expectReflows(
				page,
				`/live/event/${eventId}/${encodeURIComponent(startsAt)}`,
				{ locator: 'li.runner', min: 3 }
			);
		} finally {
			await deleteEvent(eventId);
		}
	});

	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test.beforeEach(async ({ context }) => {
			await context.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
		});

		test('a populated direct-message thread list', async ({ page }) => {
			const admin = getAdminClient();
			const ids: string[] = [];
			const send = async (from: string, to: string, body: string, minutesAgo: number) => {
				const { data, error } = await admin
					.from('direct_messages')
					.insert({
						sender_id: from,
						recipient_id: to,
						body,
						created_at: new Date(Date.now() - minutesAgo * 60 * 1000).toISOString()
					})
					.select('id')
					.single();
				if (error || !data) {
					throw new Error(`dm insert failed: ${error?.message ?? 'no row'}`);
				}
				ids.push(data.id as string);
			};
			try {
				// A long body on purpose: a thread preview that does not wrap is
				// one of the ways this pane has overflowed before.
				await send(USER_B.id, USER_A.id, 'Are you running the Thursday shakeout this week?', 400);
				await send(
					USER_A.id,
					USER_B.id,
					'Planning to, yes — easy pace though, my calves are still wrecked from Sunday.',
					396
				);
				await send(USER_B.id, USER_A.id, 'Easy works. I will bring the long way home.', 120);
				await send(
					USER_C_PRO.id,
					USER_A.id,
					'Nice work on the long run — that elevation profile looks brutal.',
					30
				);

				// A thread row is an `<a class="thread" href="/messages/{id}">`, not a
				// button — the first spelling of this locator matched nothing, and the
				// § 534 population assertion is what refused to measure rather than
				// reporting a trivially-fitting empty pane as a pass.
				await expectReflows(page, '/messages', { locator: 'a.thread', min: 2 });
			} finally {
				if (ids.length > 0) {
					await admin.from('direct_messages').delete().in('id', ids);
				}
			}
		});

		test('a global segment with a populated leaderboard', async ({ page }) => {
			const admin = getAdminClient();
			// The catalogue is curator-owned and seeded with generated ids, so
			// the segment is READ rather than created — an effort has to hang
			// off a row the leaderboard RPC will actually return.
			const { data: seg, error: segErr } = await admin
				.from('global_segments')
				.select('id')
				.limit(1)
				.single();
			if (segErr || !seg) {
				throw new Error(`no global_segments row to measure: ${segErr?.message ?? 'none'}`);
			}
			const segmentId = seg.id as string;
			const runId = await insertRun({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString(),
				duration_s: 2400,
				distance_m: 8000,
				is_public: true
			});
			try {
				// The leaderboard gates each row on is_run_visible_to(run_id,
				// caller), so the effort must reference a run the viewer can see.
				const { error } = await admin.from('global_segment_efforts').insert({
					global_segment_id: segmentId,
					run_id: runId,
					user_id: USER_A.id,
					time_seconds: 612.4,
					started_at: new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString()
				});
				if (error) throw new Error(`segment effort insert failed: ${error.message}`);

				await expectReflows(page, `/segments/${segmentId}`, { locator: 'a.athlete' });
			} finally {
				await admin
					.from('global_segment_efforts')
					.delete()
					.eq('global_segment_id', segmentId)
					.eq('run_id', runId);
				await deleteRun(runId);
			}
		});

		test('an open fundraiser with a donation feed', async ({ page }) => {
			const admin = getAdminClient();
			// `fundraisers` carries a BEFORE INSERT trigger that raises unless
			// host_can_take_payment(owner) holds, which needs a payout account
			// with charges_enabled. Seeding the account is the honest way past
			// it; flipping session_replication_role would also skip the
			// derivation triggers elsewhere. Local stack only — prod charges
			// stay gated on live keys plus owner + CISO + counsel sign-off.
			const { error: acctErr } = await admin.from('instructor_payout_accounts').upsert(
				{
					user_id: USER_A.id,
					stripe_connect_account_id: 'acct_e2e_local_only',
					charges_enabled: true,
					payouts_enabled: true,
					details_submitted: true,
					country: 'US',
					default_currency: 'usd'
				},
				{ onConflict: 'user_id' }
			);
			if (acctErr) throw new Error(`payout account upsert failed: ${acctErr.message}`);

			// `fundraisers_anchor_check` is `(run_id IS NOT NULL) <> (event_id IS
			// NOT NULL)` — exactly one anchor, never neither. The first draft set
			// neither and the insert was rejected deterministically.
			const anchorRunId = await insertRun({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString(),
				duration_s: 3600,
				distance_m: 10_000,
				is_public: true
			});
			const { data: fr, error: frErr } = await admin
				.from('fundraisers')
				.insert({
					owner_user_id: USER_A.id,
					run_id: anchorRunId,
					charity_name: 'Girls on the Run',
					charity_url: 'https://www.girlsontherun.org',
					title: 'Running my next marathon for Girls on the Run',
					story:
						'Every donation funds a season of coaching for one girl. A deliberately ' +
						'long story field, because an unwrapped paragraph is one of the ways ' +
						'this page has overflowed before.',
					goal_cents: 500_000,
					currency: 'usd',
					status: 'open'
				})
				.select('id')
				.single();
			if (frErr || !fr) {
				throw new Error(`fundraiser insert failed: ${frErr?.message ?? 'no row'}`);
			}
			const fundraiserId = fr.id as string;
			try {
				// Both the feed and the totals filter status='paid', so a pending
				// row would render an empty feed under a non-zero thermometer.
				const { error } = await admin.from('donations').insert([
					{
						fundraiser_id: fundraiserId,
						donor_user_id: USER_B.id,
						owner_user_id: USER_A.id,
						display_name: 'Alex Chen',
						message: 'Go get it. See you at the finish.',
						amount_cents: 5000,
						currency: 'usd',
						status: 'paid',
						is_anonymous: false,
						paid_at: new Date(Date.now() - 6 * 24 * 3600 * 1000).toISOString()
					},
					{
						fundraiser_id: fundraiserId,
						donor_user_id: USER_C_PRO.id,
						owner_user_id: USER_A.id,
						display_name: 'Morgan Lee',
						message: 'For the girls on the run.',
						amount_cents: 12_500,
						currency: 'usd',
						status: 'paid',
						is_anonymous: false,
						paid_at: new Date(Date.now() - 4 * 24 * 3600 * 1000).toISOString()
					},
					{
						fundraiser_id: fundraiserId,
						donor_user_id: null,
						owner_user_id: USER_A.id,
						display_name: null,
						message: 'Anonymous but enthusiastic.',
						amount_cents: 2500,
						currency: 'usd',
						status: 'paid',
						is_anonymous: true,
						paid_at: new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString()
					}
				]);
				if (error) throw new Error(`donation insert failed: ${error.message}`);

				await expectReflows(page, `/fundraisers/${fundraiserId}`, {
					locator: '.donation-feed .row',
					min: 3
				});
			} finally {
				await admin.from('donations').delete().eq('fundraiser_id', fundraiserId);
				await admin.from('fundraisers').delete().eq('id', fundraiserId);
				// After the fundraiser: the anchor is an FK, so the run cannot go first.
				await deleteRun(anchorRunId);
			}
		});
	});
});
