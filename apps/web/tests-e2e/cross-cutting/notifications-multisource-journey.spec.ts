import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import {
	clearNotifications,
	deleteEvent,
	deleteRun,
	insertComment,
	insertEvent,
	insertKudos,
	insertRun
} from '../fixtures/simulate';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Multi-source notifications inbox lifecycle — the STITCHED journey the
 * single-source specs don't cover. The existing specs each pin ONE
 * trigger end to end (cross-cutting/notifications-journey.spec.ts drives
 * kudos+comment+follow from ONE writer through the bell; the
 * cross-user/sagas/{kudos,comment,event-rsvp}-notification specs each
 * isolate a single source). None exercise FOUR distinct trigger sources,
 * from FOUR distinct actors, fanning into ONE recipient's inbox at once
 * and walking the read/dismiss arc over that mixed set.
 *
 * The arc, generate-from-many-sources → bell → inbox → read/dismiss:
 *
 *   1. A recipient saga user owns a fresh PUBLIC run. Four distinct actor
 *      saga users each fire ONE trigger source against the recipient:
 *        - actorKudos   → insertKudos        → notify_run_kudos    → kind 'kudos'
 *        - actorComment → insertComment      → notify_run_comment  → kind 'comment'
 *        - actorFollow  → user_follows insert → notify_user_follow → kind 'follow'
 *        - actorRsvp    → event_attendees    → notify_event_rsvp   → kind 'event_rsvp'
 *      (triggers: 20260528000001_notifications.sql kudos/comment/follow;
 *       20260903_001_notify_event_rsvp.sql + the 20261217_001 f17 rewrite
 *       that reads events.author_id.) Each is a SECURITY DEFINER trigger
 *       that writes one unread row for the recipient — so four sources →
 *       four unread rows, all read_at = null on creation.
 *   2. clearNotifications(recipient) in setup makes the count exact: the
 *      bell badge must read '4' (NotificationBell.svelte renders the
 *      .badge from notificationStore.unreadCount; >9 → '9+').
 *   3. The full inbox (/u/[recipient]?tab=notifications → NotificationsList,
 *      gated to isSelf on +page.svelte) lists all four rows, each rendered
 *      by verbFor() with the right verb copy (en.ts notificationsList.*).
 *   4. All vs Unread tabs both show 4 (every row arrived unread); a
 *      single-row dismiss (the .dismiss button → deleteNotification) drops
 *      that row and the DELETE persists (the inbox count falls to 3 AND a
 *      reload still shows 3 — proving it wasn't just a client filter).
 *   5. Mark-all-read clears the remaining unread: the Unread tab empties to
 *      "You're all caught up", every surviving row loses the .unread class,
 *      and the sidebar bell badge unmounts (unreadCount → 0).
 *
 * Why saga users (not the seeded trio): four distinct actors + one
 * recipient = five users, more than seed.sql pins, and the recipient's
 * inbox must be wiped clean for the exact-count assertion. The seeded
 * Richmond Run Club hosts the event (its club_id is required for the RSVP
 * trigger's club lookup); the event's author_id is the RECIPIENT, so the
 * trigger notifies them as the creator. The whole multi-user run is
 * generated via service-role simulate helpers (no UI on the write side)
 * so it's deterministic — the UI is driven only on the recipient's READ
 * side (bell + inbox + dismiss + mark-all-read), which is the surface
 * under test.
 *
 * How the badge reaches '4' without flaky realtime: cross-context realtime
 * delivery is not deterministic headless, so the recipient navigates AFTER
 * the four rows have landed server-side — the auth-ready refresh in
 * notifications.svelte.ts re-reads the authoritative count via
 * fetchUnreadNotificationCount. No sleeps; every assertion auto-waits, and
 * the count is exact because clearNotifications zeroed the baseline.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('notifications multi-source journey — four triggers → one inbox', () => {
	test.describe.configure({ timeout: 120_000 });

	let users: SagaUser[] = [];
	let runId: string | null = null;
	let commentId: string | null = null;
	let eventId: string | null = null;

	test.afterEach(async () => {
		const admin = getAdminClient();
		// Order: child rows first, then the run/event, then the recipient's
		// remaining notifications, then the saga users (whose CASCADE sweeps
		// follows/kudos/comments still hanging off them).
		if (eventId) {
			try {
				await admin.from('event_attendees').delete().eq('event_id', eventId);
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
		if (runId) {
			try {
				await deleteRun(runId);
			} catch {
				/* best-effort */
			}
			runId = null;
		}
		commentId = null;
		if (users.length > 0) {
			// Wipe the recipient's inbox before the user delete so a
			// downstream bell-count spec isn't polluted by a stray row.
			try {
				await clearNotifications(users[0].id);
			} catch {
				/* best-effort */
			}
			await deleteSagaUsers(users);
			users = [];
		}
	});

	test('kudos + comment + follow + event-RSVP from four actors → badge 4, inbox verbs, dismiss persists, mark-all-read clears', async ({
		browser
	}) => {
		users = await createSagaUsers(5, {
			displayNames: [
				'Rory Recipient',
				'Kai Kudos',
				'Cam Comment',
				'Fenn Follow',
				'Remy RSVP'
			]
		});
		const [recipient, actorKudos, actorComment, actorFollow, actorRsvp] = users;
		const admin = getAdminClient();

		// Deterministic baseline: the recipient's inbox starts empty so the
		// badge can read an exact '4', not '9+'.
		await clearNotifications(recipient.id);

		const ctx = await browser.newContext({ storageState: recipient.storageStatePath });
		// Pre-accept the cookie banner so the fixed dialog can't intercept
		// pointer events on the bell, filter tabs, dismiss, or mark-all-read.
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			await test.step('recipient owns a fresh public run', async () => {
				// Keep this run UNDER the 5 km single-run distance-badge threshold
				// (achievements migration 20270208_001 → bronze distance_single =
				// 5000 m). An 8 km run awards the recipient a bronze distance badge
				// on insert, and notify_achievement_earned then lands a FIFTH
				// 'achievement' row in their inbox — breaking the exact-four-kinds
				// assertion below. The distance is irrelevant to the four social
				// triggers under test, so a sub-5 km run keeps the inbox to exactly
				// the kudos/comment/follow/event_rsvp set.
				runId = await insertRun({
					user_id: recipient.id,
					started_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
					distance_m: 4_000,
					duration_s: 1_200,
					is_public: true,
					metadata: { activity_type: 'run', title: `E2E multisource ${Date.now()}` }
				});
			});

			await test.step('four distinct actors each fire one trigger source', async () => {
				// kudos → notify_run_kudos → run owner
				await insertKudos(runId!, actorKudos.id);
				// top-level comment → notify_run_comment → run owner
				commentId = await insertComment({
					run_id: runId!,
					author_id: actorComment.id,
					body: `e2e multisource comment ${Date.now()}`
				});
				// follow → notify_user_follow → followee (the recipient)
				const { error: followErr } = await admin
					.from('user_follows')
					.insert({ follower_id: actorFollow.id, followee_id: recipient.id });
				if (followErr) throw new Error(`follow insert failed: ${followErr.message}`);
				// event RSVP → notify_event_rsvp → event author (the recipient).
				// The event lives in the seeded Richmond Run Club (the trigger
				// requires a non-null club_id) but its author_id is the
				// recipient, so the creator-recipient branch of the trigger
				// notifies them.
				eventId = await insertEvent({
					club_id: RICHMOND_RUN_CLUB_ID,
					author_id: recipient.id,
					title: `E2E multisource event ${Date.now()}`
				});
				// event_attendees is keyed per instance — instance_start is
				// NOT NULL. For a one-off event the only instance is its
				// starts_at; read it back and RSVP against that instance.
				const { data: evRow, error: evErr } = await admin
					.from('events')
					.select('starts_at')
					.eq('id', eventId)
					.single();
				if (evErr || !evRow) throw new Error(`event read failed: ${evErr?.message ?? 'no row'}`);
				const { error: rsvpErr } = await admin.from('event_attendees').insert({
					event_id: eventId,
					user_id: actorRsvp.id,
					instance_start: evRow.starts_at,
					status: 'going'
				});
				if (rsvpErr) throw new Error(`event_attendees insert failed: ${rsvpErr.message}`);
			});

			await test.step('exactly four unread rows landed server-side, one per kind', async () => {
				// Confirm the fan-in before reading the UI so a UI-timing flake
				// can't be confused with a missing trigger. Asserts the exact
				// set of kinds so a duplicate/missing source is caught here.
				await expect(async () => {
					const { data } = await admin
						.from('notifications')
						.select('kind, read_at')
						.eq('user_id', recipient.id);
					const rows = data ?? [];
					expect(rows).toHaveLength(4);
					expect(rows.every((r) => r.read_at == null)).toBe(true);
					expect([...rows.map((r) => r.kind as string)].sort()).toEqual([
						'comment',
						'event_rsvp',
						'follow',
						'kudos'
					]);
				}).toPass({ timeout: 10_000 });
			});

			await test.step('sidebar bell badge shows the unread count 4', async () => {
				// Navigate (not sleep) so the auth-ready refresh re-reads the
				// authoritative count via fetchUnreadNotificationCount.
				await page.goto('/dashboard');
				await expect(page.locator('.bell-wrap .bell-btn')).toBeVisible({ timeout: 10_000 });
				const badge = page.locator('.bell-wrap .badge');
				await expect(badge).toBeVisible({ timeout: 10_000 });
				await expect(badge).toHaveText('4', { timeout: 10_000 });
			});

			await test.step('inbox lists all four rows with the right verbs', async () => {
				await page.goto(`/u/${recipient.id}?tab=notifications`);
				await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
					timeout: 10_000
				});

				const items = page.locator('.item-wrap');
				await expect(items.first()).toBeVisible({ timeout: 10_000 });
				await expect(items).toHaveCount(4);
				// All four arrived unread.
				await expect(page.locator('.item-wrap.unread')).toHaveCount(4);

				// verbFor() composes each actor's display name into its row.
				// km/mi-agnostic match on the distance-bearing verbs so the
				// test survives the recipient's unit preference.
				// Each verb must appear on EXACTLY ONE row — scope with a
				// hasText filter so the assertion isn't a strict-mode violation
				// against the 4-element .item-wrap locator.
				const rowWith = (re: RegExp) => page.locator('.item-wrap').filter({ hasText: re });
				await expect(rowWith(/Kai Kudos gave kudos to your/i)).toHaveCount(1);
				await expect(rowWith(/Cam Comment commented on your/i)).toHaveCount(1);
				await expect(rowWith(/Fenn Follow started following you/i)).toHaveCount(1);
				await expect(rowWith(/Remy RSVP RSVP'd Going to your event/i)).toHaveCount(1);
			});

			await test.step('All vs Unread tabs both show all four', async () => {
				await page.getByRole('button', { name: /Unread/ }).click();
				await expect(page.locator('.item-wrap')).toHaveCount(4);
				await page.getByRole('button', { name: 'All', exact: true }).click();
				await expect(page.locator('.item-wrap')).toHaveCount(4);
			});

			await test.step('dismissing the kudos row drops it and the delete persists', async () => {
				const kudosRow = page
					.locator('.item-wrap')
					.filter({ hasText: /Kai Kudos gave kudos/i });
				await expect(kudosRow).toHaveCount(1);
				await kudosRow.getByRole('button', { name: 'Dismiss' }).click();

				// The row leaves the list immediately and the others remain.
				await expect(page.locator('.item-wrap')).toHaveCount(3);
				// The dismissed kudos row is gone — assert zero rows match it
				// (a .not.toContainText against the 3-element locator would be a
				// strict-mode violation).
				await expect(
					page.locator('.item-wrap').filter({ hasText: /Kai Kudos gave kudos/i })
				).toHaveCount(0);

				// Persistence check: the DELETE actually hit the DB, not just a
				// client filter. A reload re-fetches and must still show 3 — and
				// the badge falls to 3 (dismiss of an unread row decrements).
				await expect(async () => {
					const { count } = await admin
						.from('notifications')
						.select('*', { count: 'exact', head: true })
						.eq('user_id', recipient.id);
					expect(count).toBe(3);
				}).toPass({ timeout: 10_000 });

				await page.reload();
				await expect(page.locator('.item-wrap').first()).toBeVisible({ timeout: 10_000 });
				await expect(page.locator('.item-wrap')).toHaveCount(3);
				await expect(page.locator('.bell-wrap .badge')).toHaveText('3', { timeout: 10_000 });
			});

			await test.step('mark-all-read empties Unread and clears the bell badge', async () => {
				// On All so the Mark-all-read button (gated on an unread item
				// existing) is present.
				await page.getByRole('button', { name: 'All', exact: true }).click();
				await page.getByRole('button', { name: 'Mark all read' }).click();

				// Unread tab → the "all caught up" empty state.
				await page.getByRole('button', { name: /Unread/ }).click();
				await expect(
					page.locator('.empty', { hasText: "You're all caught up" })
				).toBeVisible({ timeout: 5_000 });

				// The three surviving rows stay under All but lose the unread class.
				await page.getByRole('button', { name: 'All', exact: true }).click();
				await expect(page.locator('.item-wrap')).toHaveCount(3);
				await expect(page.locator('.item-wrap.unread')).toHaveCount(0);

				// The sidebar bell badge has cleared (unreadCount === 0 → the
				// .badge element unmounts). markAllNotificationsRead +
				// notificationStore.clear() drove this without a reload.
				await expect(page.locator('.bell-wrap .badge')).toHaveCount(0, { timeout: 5_000 });
			});
		} finally {
			await ctx.close();
		}
	});
});
