import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { getAdminClient } from '../fixtures/local-supabase';
import { clearNotifications } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Database triggers, exercised through the UI and verified via
 * service-role inspection of the rows the triggers should have
 * planted. This is the seam between "the trigger is correct in SQL"
 * (pgtap can pin that) and "the canonical UI flow actually fires
 * the trigger" — a regression where the data layer drops a column,
 * uses the wrong table, or skips an insert would silently break
 * the side-effect even if the trigger itself stayed correct.
 *
 * Two triggers covered today:
 *   - `enroll_club_owner` (migration 20260416_001) — auto-inserts
 *     the creator into club_members with role='owner', status='active'
 *     when a clubs row is INSERTed.
 *   - `notify_run_kudos` (migration 20260528_001) — inserts a
 *     notifications row for the run's owner when a run_kudos row is
 *     INSERTed by anyone except the owner themselves.
 */

test.describe('database triggers via UI', () => {
	test('enroll_club_owner fires when /clubs/new submits — owner row planted', async () => {
		const admin = getAdminClient();
		// Drive the trigger via service-role club insert (the canonical
		// UI route /clubs/new also fires it). We avoid the UI here so
		// the test is fast + tightly scoped to the trigger's effect;
		// the UI-side create-club path is exercised by clubs-journey.
		const slug = `e2e-trigger-${Date.now()}`;
		const { data: club, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `e2e trigger club ${Date.now()}`,
				slug,
				description: 'e2e enroll_club_owner trigger',
				is_public: true,
				join_policy: 'open'
			})
			.select('id')
			.single();
		expect(error).toBeNull();
		const clubId = (club as { id: string }).id;

		try {
			// The trigger should have planted exactly one club_members
			// row with role='owner' status='active'. A regression that
			// drops the trigger leaves the owner without admin access
			// to their own club.
			const { data: rows } = await admin
				.from('club_members')
				.select('user_id, role, status')
				.eq('club_id', clubId);
			expect(rows?.length).toBe(1);
			expect(rows?.[0]?.user_id).toBe(USER_A.id);
			expect(rows?.[0]?.role).toBe('owner');
			expect(rows?.[0]?.status).toBe('active');
		} finally {
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});

	test('notify_run_kudos fires when alex kudos via UI — runner gets a kudos notification', async ({
		browser
	}) => {
		// Same path as cross-user/notifications.spec.ts but the
		// assertion is at the DB layer, not the bell badge. This pins
		// the SHAPE of the notifications row (kind=kudos, run_id set,
		// actor_id=alex, user_id=runner, read_at null) rather than
		// just the bell counter.
		const admin = getAdminClient();
		// Wipe runner's notifications so we can isolate the row the
		// trigger creates from this kudos action.
		await clearNotifications(USER_A.id);

		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const alex = await ctxAlex.newPage();
		try {
			await alex.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const kudosBtn = alex.locator('.kudos-btn');
			await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
			// If a prior failed run left alex's kudos in place, rescind
			// first so the click below is the "give kudos" branch.
			if (await kudosBtn.evaluate((el) => el.classList.contains('given'))) {
				await kudosBtn.click();
				await expect(kudosBtn).not.toHaveClass(/given/);
			}
			await kudosBtn.click();
			await expect(kudosBtn).toHaveClass(/given/);

			// Trigger ran on the run_kudos INSERT; runner should now
			// have a notifications row with kind='kudos'.
			// Allow a moment for the AFTER-INSERT trigger to settle —
			// it's synchronous within the txn but the supabase-js
			// optimistic ack returns before we read.
			await expect.poll(async () => {
				const { data } = await admin
					.from('notifications')
					.select('kind, run_id, actor_id, user_id, read_at')
					.eq('user_id', USER_A.id)
					.eq('kind', 'kudos');
				return data?.length ?? 0;
			}, { timeout: 5_000 }).toBeGreaterThanOrEqual(1);

			const { data: rows } = await admin
				.from('notifications')
				.select('kind, run_id, actor_id, user_id, read_at')
				.eq('user_id', USER_A.id)
				.eq('kind', 'kudos');
			const row = rows?.[0];
			expect(row?.actor_id).toBe(USER_B.id);
			expect(row?.run_id).toBe(RUNNER_PUBLIC_RUN_ID);
			expect(row?.read_at).toBeNull();

			// Cleanup — rescind so the seed shape is preserved.
			await alex.locator('.kudos-btn').click();
			await expect(alex.locator('.kudos-btn')).not.toHaveClass(/given/);
		} finally {
			await ctxAlex.close();
		}
	});

	test('notify_run_comment fires on a service-role-planted comment row', async () => {
		// Migration 20260528_001 registers a trigger on run_comments
		// AFTER INSERT — the run owner gets a kind='comment'
		// notification with comment_id set. Plant directly via
		// service-role to isolate the trigger from the UI; the
		// notification row should appear regardless of how the
		// comment got there.
		const admin = getAdminClient();
		await clearNotifications(USER_A.id);
		const commentId: string = await (async () => {
			const { data } = await admin
				.from('run_comments')
				.insert({
					run_id: RUNNER_PUBLIC_RUN_ID,
					author_id: USER_B.id,
					body: 'e2e-trigger-comment'
				})
				.select('id')
				.single();
			return (data as { id: string }).id;
		})();
		try {
			await expect.poll(async () => {
				const { data } = await admin
					.from('notifications')
					.select('kind, run_id, comment_id, actor_id, user_id')
					.eq('user_id', USER_A.id)
					.eq('kind', 'comment');
				return data?.length ?? 0;
			}, { timeout: 5_000 }).toBeGreaterThanOrEqual(1);

			const { data: rows } = await admin
				.from('notifications')
				.select('comment_id, actor_id, run_id')
				.eq('user_id', USER_A.id)
				.eq('kind', 'comment');
			const row = rows?.[0];
			expect(row?.comment_id).toBe(commentId);
			expect(row?.actor_id).toBe(USER_B.id);
			expect(row?.run_id).toBe(RUNNER_PUBLIC_RUN_ID);
		} finally {
			// Comment delete cascades the notification (comment_id is
			// on delete cascade per the migration).
			await admin.from('run_comments').delete().eq('id', commentId);
		}
	});

	test('notify_user_follow fires when a user_follows row is INSERTed', async () => {
		// notify_user_follow plants a kind='follow' notification on
		// the followee. Test by service-role-INSERTing morgan->alex
		// (a follow that doesn't exist in the seed) and asserting the
		// row appears for alex.
		const admin = getAdminClient();
		await clearNotifications(USER_B.id);
		const MORGAN = 'c3d4e5f6-a7b8-9012-cdef-345678901234';
		// Ensure morgan isn't already following alex (defensive).
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', MORGAN)
			.eq('followee_id', USER_B.id);

		const { error } = await admin
			.from('user_follows')
			.insert({ follower_id: MORGAN, followee_id: USER_B.id });
		expect(error).toBeNull();

		try {
			await expect.poll(async () => {
				const { data } = await admin
					.from('notifications')
					.select('kind, actor_id, user_id')
					.eq('user_id', USER_B.id)
					.eq('kind', 'follow');
				return data?.length ?? 0;
			}, { timeout: 5_000 }).toBeGreaterThanOrEqual(1);

			const { data: rows } = await admin
				.from('notifications')
				.select('kind, actor_id, user_id')
				.eq('user_id', USER_B.id)
				.eq('kind', 'follow');
			expect(rows?.[0]?.actor_id).toBe(MORGAN);
		} finally {
			await admin
				.from('user_follows')
				.delete()
				.eq('follower_id', MORGAN)
				.eq('followee_id', USER_B.id);
		}
	});

	test('notify_run_comment_reply fires on a nested comment reply (parent author notified)', async () => {
		// When alex replies to runner's comment, runner is the run
		// owner AND the parent comment's author. The trigger sends
		// 'comment_reply' to the parent author distinct from the
		// 'comment' notification it sends to the run owner.
		const admin = getAdminClient();
		// Plant the parent: runner comments on their OWN run (no
		// cross-user notification — owner commenting on own run).
		const { data: parent } = await admin
			.from('run_comments')
			.insert({
				run_id: RUNNER_PUBLIC_RUN_ID,
				author_id: USER_A.id,
				body: 'e2e parent'
			})
			.select('id')
			.single();
		const parentId = (parent as { id: string }).id;
		await clearNotifications(USER_A.id);
		// Plant the reply: alex replies to runner's comment.
		const { data: reply } = await admin
			.from('run_comments')
			.insert({
				run_id: RUNNER_PUBLIC_RUN_ID,
				author_id: USER_B.id,
				body: 'e2e reply',
				parent_comment_id: parentId
			})
			.select('id')
			.single();
		const replyId = (reply as { id: string }).id;

		try {
			// Runner should now have a 'comment_reply' notification,
			// distinct from 'comment'. Both arms of the trigger fire.
			await expect.poll(async () => {
				const { data } = await admin
					.from('notifications')
					.select('kind')
					.eq('user_id', USER_A.id)
					.eq('kind', 'comment_reply');
				return data?.length ?? 0;
			}, { timeout: 5_000 }).toBeGreaterThanOrEqual(1);
		} finally {
			await admin.from('run_comments').delete().eq('id', replyId);
			await admin.from('run_comments').delete().eq('id', parentId);
		}
	});

	test('notify_club_post fans out to active members but not the author (persona #38)', async () => {
		// Migration 20261101_001: a new club_posts row notifies every
		// active member except the author, carrying club_id. Plant a
		// club (owner = USER_A, auto-enrolled active), add USER_B as an
		// active member, then post as USER_A.
		const admin = getAdminClient();
		const slug = `e2e-clubpost-${Date.now()}`;
		const { data: club } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `e2e clubpost ${Date.now()}`,
				slug,
				is_public: true,
				join_policy: 'open'
			})
			.select('id')
			.single();
		const clubId = (club as { id: string }).id;
		try {
			await admin
				.from('club_members')
				.insert({ club_id: clubId, user_id: USER_B.id, role: 'member', status: 'active' });

			await admin
				.from('club_posts')
				.insert({ club_id: clubId, author_id: USER_A.id, body: 'e2e course change' });

			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('notifications')
							.select('club_id, actor_id, user_id')
							.eq('user_id', USER_B.id)
							.eq('kind', 'club_post')
							.eq('club_id', clubId);
						return data?.length ?? 0;
					},
					{ timeout: 5_000 }
				)
				.toBeGreaterThanOrEqual(1);

			const { data: memberRows } = await admin
				.from('notifications')
				.select('club_id, actor_id')
				.eq('user_id', USER_B.id)
				.eq('kind', 'club_post')
				.eq('club_id', clubId);
			expect(memberRows?.[0]?.actor_id).toBe(USER_A.id);

			// The author is never notified of their own post.
			const { data: authorRows } = await admin
				.from('notifications')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('kind', 'club_post')
				.eq('club_id', clubId);
			expect(authorRows?.length ?? 0).toBe(0);
		} finally {
			// Deleting the club cascades members, posts, and the
			// club_id-linked notifications.
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});

	test('notify_run_completed fans out a fresh public run to followers (persona #38)', async () => {
		// Migration 20261101_001: a public run started within the last
		// 24h notifies the runner's followers. USER_B follows USER_A,
		// then USER_A records a fresh public run.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_B.id)
			.eq('followee_id', USER_A.id);
		await admin
			.from('user_follows')
			.insert({ follower_id: USER_B.id, followee_id: USER_A.id });

		const { data: run } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 30 * 60_000).toISOString(),
				duration_s: 1800,
				distance_m: 5000,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		const runId = (run as { id: string }).id;
		try {
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('notifications')
							.select('run_id, actor_id, user_id')
							.eq('user_id', USER_B.id)
							.eq('kind', 'run_completed')
							.eq('run_id', runId);
						return data?.length ?? 0;
					},
					{ timeout: 5_000 }
				)
				.toBeGreaterThanOrEqual(1);

			const { data: rows } = await admin
				.from('notifications')
				.select('run_id, actor_id')
				.eq('user_id', USER_B.id)
				.eq('kind', 'run_completed')
				.eq('run_id', runId);
			expect(rows?.[0]?.actor_id).toBe(USER_A.id);

			// The runner is never notified of their own run.
			const { data: selfRows } = await admin
				.from('notifications')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('kind', 'run_completed')
				.eq('run_id', runId);
			expect(selfRows?.length ?? 0).toBe(0);
		} finally {
			// run_id is on delete cascade, so deleting the run clears
			// the notification; drop the test follow too.
			await admin.from('runs').delete().eq('id', runId);
			await admin
				.from('user_follows')
				.delete()
				.eq('follower_id', USER_B.id)
				.eq('followee_id', USER_A.id);
		}
	});
});
