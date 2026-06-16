import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertEvent, deleteEvent, deleteClub } from '../fixtures/simulate';

/**
 * Social cross-surface journey — EVENT discovery via the /social Discover
 * tab, walked filter -> find -> open -> engage end-to-end.
 *
 * This is the sibling of discover-follow-journey.spec.ts, which covers
 * PEOPLE discovery (the People tab — search a stranger by name, follow,
 * pull their run into the feed). This one is the distinct EVENT-discovery
 * arc: a user who belongs to NONE of the hosting clubs finds a public
 * club's typed event through the cross-club search_public_events RPC,
 * narrows it down with the category / cadence / weekday / time / paid
 * filters, opens the event, and engages by RSVPing — a path a non-member
 * of a public club is allowed to walk (the event RLS only requires the
 * event be SELECTable, which a public-club public event is, and the
 * event_attendees self-RSVP INSERT policy gates on that same visibility,
 * migration 20260629_001).
 *
 * The discovering actor is an EPHEMERAL saga user with no club membership
 * — that's the whole point of discovery (you find things outside your own
 * clubs). The planted event lives on a freshly-minted PUBLIC club owned by
 * a SECOND saga user, so the discoverer is provably not a member. Both
 * saga users + the club + the event are torn down in afterAll.
 *
 * The planted event is a WEEKLY recurring `class` event so the journey can
 * exercise the recurrence-aware filters (cadence=weekly, weekday byday,
 * time-of-day bucket). Its discipline string is unique so the text query
 * narrows to exactly this row. The club carries a geocoded location_point
 * so the journey can also assert the proximity semantics the docs pin
 * (decisions §147 + migration 20270112_001): search_public_events derives
 * "near" distance from the CLUB's geocoded location_point, NEVER the
 * event's revoked precise meet point — verified by a direct RPC call (the
 * UI proximity path is a MapTiler-geocode round-trip out of scope here).
 *
 * NB: the Discover panel runs a 250ms-debounced reactive search over a
 * Supabase RPC — rely on auto-waiting assertions against the results list,
 * never waitForLoadState('networkidle'). The cookie banner (role="dialog")
 * floats over the page and intercepts pointer events on the filter chips,
 * so the discoverer's context pre-accepts consent via an init script.
 */

const RICHMOND = { lng: -77.436, lat: 37.5407 }; // club's geocoded point
const FAR_AWAY = { lng: 139.6917, lat: 35.6895 }; // Tokyo — ~9,500 km off

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('social journey — non-member discovers a public-club event + RSVPs', () => {
	// Filter -> find -> open -> RSVP across two surfaces, plus a saga
	// sign-in beforeAll — past the 30s default.
	test.describe.configure({ timeout: 90_000 });

	let discoverer: SagaUser;
	let host: SagaUser;
	let clubId: string | null = null;
	let clubSlug: string;
	let eventId: string | null = null;
	let discipline: string;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const stamp = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;

		// Two ephemeral users: the discoverer (acts in the browser) and the
		// host (owns the planted public club). Distinct so the discoverer is
		// provably outside the hosting club's membership.
		[discoverer, host] = await createSagaUsers(2, {
			displayNames: [`EventDiscoverer ${stamp}`, `EventHost ${stamp}`]
		});

		// A PUBLIC club owned by the host, with a geocoded location_point so
		// the proximity semantics are testable. is_public=true is what makes
		// the RPC's `join clubs c ... and c.is_public = true` surface it.
		clubSlug = `discover-events-${stamp}`;
		const { data: club, error: clubErr } = await admin
			.from('clubs')
			.insert({
				owner_id: host.id,
				name: `Discover Events Club ${stamp}`,
				slug: clubSlug,
				description: 'event-discovery e2e seed',
				location_label: 'Richmond, VA',
				location_point: `SRID=4326;POINT(${RICHMOND.lng} ${RICHMOND.lat})`,
				is_public: true,
				join_policy: 'open'
			})
			.select('id')
			.single();
		if (clubErr || !club) {
			throw new Error(`event-discovery: club insert failed: ${clubErr?.message ?? 'no row'}`);
		}
		clubId = club.id as string;

		// The enroll_club_owner_trigger (AFTER INSERT ON clubs, migration
		// 20260416_001) already seated the host as an 'owner' club_members row
		// — it fires for the service-role insert too (triggers aren't bypassed
		// by the service role, only RLS is), with the default status 'active'.
		// No manual enrol (which would dup-key the trigger's row). The
		// DISCOVERER is intentionally left un-enrolled.

		// A WEEKLY recurring `class` event. Unique discipline → the text query
		// narrows to exactly this row. starts_at fixed at 08:00 UTC → the RPC's
		// morning bucket (timezone left null → coalesce(...,'UTC')); recurring,
		// so it passes the `recurrence_freq is not null` upcoming gate
		// regardless of the date. recurrence_byday=['MO'] → the weekday filter
		// matches MO (the recurring branch checks the byday array, not the
		// starts_at weekday).
		discipline = `Sunrise Vinyasa ${stamp}`;
		const startsAt = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		startsAt.setUTCHours(8, 0, 0, 0);
		eventId = await insertEvent({
			club_id: clubId,
			author_id: host.id,
			title: `Discover Class ${stamp}`,
			discipline,
			category: 'class',
			starts_at: startsAt.toISOString(),
			duration_min: 60,
			recurrence_freq: 'weekly',
			recurrence_byday: ['MO']
		});
	});

	test.afterAll(async () => {
		// Order matters: the event row first (it FKs the club), then the club
		// (its delete cascades club_members + any attendee rows the RSVP step
		// planted), then the saga users + their storage-state files.
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (e) {
				console.warn(`event-discovery: failed to delete event ${eventId}:`, e);
			}
		}
		if (clubId) {
			try {
				await deleteClub(clubId);
			} catch (e) {
				console.warn(`event-discovery: failed to delete club ${clubId}:`, e);
			}
		}
		try {
			await deleteSagaUsers([discoverer, host].filter(Boolean));
		} catch (e) {
			console.warn('event-discovery: failed to delete saga users:', e);
		}
	});

	test('a non-member filters cross-club events, opens the planted class, and RSVPs', async ({
		browser
	}) => {
		const admin = getAdminClient();

		// ── precondition: the discoverer is NOT a member of the host club ──
		await test.step('precondition: discoverer is outside the hosting club', async () => {
			const { data } = await admin
				.from('club_members')
				.select('user_id')
				.eq('club_id', clubId!)
				.eq('user_id', discoverer.id)
				.maybeSingle();
			expect(data).toBeNull();
		});

		const ctx = await browser.newContext({ storageState: discoverer.storageStatePath });
		// Pre-accept consent BEFORE the first navigation — the banner dialog
		// otherwise floats over the filter chips and eats their clicks.
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			// ── 1. Land on the Discover tab ──────────────────────────────
			await test.step('discoverer opens the Discover tab', async () => {
				await page.goto('/social?tab=discover');
				await expect(page.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
					timeout: 10_000
				});
				// The Discover panel mounts its filter bar; the search field is
				// the stable anchor (testid pinned on the component).
				await expect(page.getByTestId('discover-search')).toBeVisible({ timeout: 10_000 });
			});

			// ── 2. Narrow to the planted event with the filters ──────────
			// Walk the full filter set: a category chip + the cadence/weekday/
			// time selects + the free price chip, then the discipline text
			// query. Each filter is a real RPC param (SocialDiscover.run()).
			await test.step('apply category + cadence + weekday + time + price filters', async () => {
				await page.getByTestId('discover-cat-class').click();
				await expect(page.getByTestId('discover-cat-class')).toHaveAttribute(
					'aria-pressed',
					'true'
				);

				await page.getByTestId('discover-cadence').selectOption('weekly');
				await page.getByTestId('discover-day').selectOption('MO');
				await page.getByTestId('discover-time').selectOption('morning');

				// Price chips live in a chip-row; "Free" is the second one. The
				// event has no event_pricing rows, so the RPC's free branch
				// (`pr.price_cents is null`) keeps it.
				await page.getByRole('button', { name: 'Free', exact: true }).click();
			});

			await test.step('text-search the unique discipline + find the result', async () => {
				await page.getByTestId('discover-search').fill(discipline);

				const results = page.getByTestId('discover-results');
				// The card title renders `discipline || title`; our event has a
				// discipline, so the discipline string is the visible title.
				const card = results.locator('a.result', { hasText: discipline });
				await expect(card).toBeVisible({ timeout: 10_000 });
				// It carries the hosting club's name + links to the club-scoped
				// event detail URL (built from club_slug + event id).
				await expect(card).toContainText('Discover Events Club');
				await expect(card).toHaveAttribute(
					'href',
					`/clubs/${clubSlug}/events/${eventId}`
				);
			});

			// A bogus query must yield the empty state — proves the result
			// above was filter-driven, not an unfiltered dump.
			await test.step('a non-matching query shows the empty state', async () => {
				await page.getByTestId('discover-search').fill(`no-such-event-${Date.now()}`);
				await expect(page.getByTestId('discover-empty')).toBeVisible({ timeout: 10_000 });
				// Restore the matching query for the open step.
				await page.getByTestId('discover-search').fill(discipline);
				await expect(
					page.getByTestId('discover-results').locator('a.result', { hasText: discipline })
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 3. Open the event from its discovery card ────────────────
			await test.step('open the event detail from the Discover card', async () => {
				await page
					.getByTestId('discover-results')
					.locator('a.result', { hasText: discipline })
					.click();
				await expect(page).toHaveURL(new RegExp(`/clubs/${clubSlug}/events/${eventId}`));
				await expect(page.getByRole('heading', { name: `Discover Class`, exact: false })).toBeVisible({
					timeout: 10_000
				});
			});

			// ── 4. Engage: RSVP "I'm in" on the discovered event ─────────
			// The free-event RSVP tri shows for any signed-in user (no
			// membership gate in the UI), and a non-member's self-RSVP is
			// permitted by the event_attendees INSERT policy (it only requires
			// the event be SELECTable). The "I'm in" button flips to "Going".
			await test.step('RSVP going on the discovered event', async () => {
				const going = page.locator('button.rsvp-going');
				await expect(going).toBeVisible({ timeout: 10_000 });
				await expect(going).toContainText("I'm in");
				await going.click();
				await expect(going).toContainText('Going', { timeout: 10_000 });

				// The RSVP must land server-side as a `going` attendee row for
				// the discoverer on this event.
				await expect(async () => {
					const { data } = await admin
						.from('event_attendees')
						.select('status')
						.eq('event_id', eventId!)
						.eq('user_id', discoverer.id)
						.maybeSingle();
					expect(data?.status).toBe('going');
				}).toPass({ timeout: 10_000 });
			});

			// ── 5. Proximity semantics (decisions §147) ───────────────────
			// search_public_events derives "near" distance from the CLUB's
			// geocoded location_point, NOT the event's meet point. Asserted via
			// a direct RPC call (the UI proximity path is a MapTiler geocode
			// round-trip, out of scope). Near the club → returned with a
			// distance_m; far from the club with a tight radius → excluded.
			await test.step('proximity filter keys off the club location, not the event', async () => {
				// Near the club (small radius): the event is surfaced and its
				// distance_m is the club-to-center distance (≈0, well within 1km).
				const { data: near, error: nearErr } = await admin.rpc('search_public_events', {
					p_query: discipline,
					p_center_lng: RICHMOND.lng,
					p_center_lat: RICHMOND.lat,
					p_radius_m: 1_000
				});
				expect(nearErr).toBeNull();
				const hit = (near ?? []).find((r: { id: string }) => r.id === eventId);
				expect(hit, 'event surfaces when the search center is near its CLUB').toBeTruthy();
				expect(hit.distance_m).not.toBeNull();
				expect(hit.distance_m).toBeLessThan(1_000);

				// Far from the club with the same tight radius: excluded. If the
				// RPC had (wrongly) used a null/own-location-defaulting meet
				// point, this could still match — it must not.
				const { data: far, error: farErr } = await admin.rpc('search_public_events', {
					p_query: discipline,
					p_center_lng: FAR_AWAY.lng,
					p_center_lat: FAR_AWAY.lat,
					p_radius_m: 1_000
				});
				expect(farErr).toBeNull();
				expect(
					(far ?? []).some((r: { id: string }) => r.id === eventId),
					'event is excluded when the search center is far from its CLUB'
				).toBe(false);
			});
		} finally {
			await page.close();
			await ctx.close();
		}
	});
});
