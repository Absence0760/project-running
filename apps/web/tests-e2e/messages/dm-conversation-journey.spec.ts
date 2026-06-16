import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * DM-conversation journey — the full life of a two-user direct-message
 * thread, walked across the surfaces it touches plus a permission
 * boundary, in TWO browser contexts. Heavier than messages/dm.spec.ts's
 * single happy-path send and messages/dm-permissions.spec.ts's per-rule
 * assertions because it threads ONE conversation through profile
 * entry-point → send → cross-user unread badge → reply → owner-side
 * verification → mark-read, exercising the seams between those surfaces
 * rather than any single screen.
 *
 * User pair: USER_A (runner@test.com) ↔ USER_C_PRO (morgan@test.com),
 * who MUTUALLY FOLLOW in the seed. The DM insert RLS (migration
 * 20261026_001) gates on a follow edge in EITHER direction plus no
 * block, so A↔C is a permitted conversation. USER_B (alex@test.com) has
 * NO follow edge with USER_C_PRO (the seed edges are A↔B and A↔C only),
 * so B is used purely for the permission-boundary half — B sending to C
 * must be rejected, matching dm-permissions.spec's follow-graph rule.
 *
 *   1. USER_A opens USER_C_PRO's profile (/u/[id]) and clicks the
 *      Message button (a.btn-message → /messages/[id]) — the real
 *      entry point a user takes to start a conversation.
 *   2. USER_A sends the opening message; it renders as an own bubble
 *      (.bubble.mine) and the conversation persists (backend row check).
 *   3. In a SECOND browser context USER_C_PRO opens /messages: the
 *      thread shows with an unread .badge (the message C hasn't read).
 *   4. USER_C_PRO opens the thread (clears the badge via
 *      markDmThreadRead), sees USER_A's message, and replies.
 *   5. Back as USER_A, BEFORE opening the thread: loading /messages
 *      (list) shows C's reply with an unread .badge, and C's reply row
 *      is still unread (read_at null) on the backend. This ordering is
 *      load-bearing — visiting /messages/[C] fires the page's
 *      onMount→openThread $effect, which calls markDmThreadRead and
 *      would clear the badge before it could be asserted.
 *   6. USER_A then opens /messages/[C]: C's reply shows in send order
 *      (A's own bubble before C's other bubble), and opening the thread
 *      marks it read — the badge clears in place, a fresh /messages
 *      keeps it gone, and read_at is persisted on C's row (backend poll,
 *      null → set).
 *   7. Permission boundary: USER_B (no follow edge with C) cannot DM C —
 *      the send surfaces the friendly role="alert" error and no row
 *      lands (fail-closed).
 *
 * Teardown deletes every message planted between the three users in both
 * directions via the admin client, so the seed conversation shape stays
 * intact for downstream specs.
 */

test.describe('DM conversation journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		const ids = [USER_A.id, USER_B.id, USER_C_PRO.id];
		await admin
			.from('direct_messages')
			.delete()
			.in('sender_id', ids)
			.in('recipient_id', ids);
	});

	test('profile entry → send → recipient unread → reply → owner sees thread → mark-read → permission boundary', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const openingBody = `e2e-dm-journey-open ${stamp}`;
		const replyBody = `e2e-dm-journey-reply ${stamp}`;

		// ── 1. USER_A starts the conversation from USER_C_PRO's profile ──
		await test.step('USER_A opens the conversation from the recipient profile', async () => {
			await page.goto(`/u/${USER_C_PRO.id}`);
			// The profile Message button (a.btn-message) links to the DM
			// thread — the real start-a-conversation entry point.
			const messageLink = page.locator('a.btn-message');
			await expect(messageLink).toBeVisible({ timeout: 10_000 });
			await messageLink.click();
			await page.waitForURL(`**/messages/${USER_C_PRO.id}`, {
				timeout: 10_000
			});
		});

		// ── 2. USER_A sends the opening message ─────────────────────────
		await test.step('USER_A sends the opening message', async () => {
			const composer = page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(openingBody);
			await page.getByRole('button', { name: 'Send' }).click();

			// Renders as an OWN bubble (.bubble.mine) — A is the sender.
			const ownBubble = page.locator('.bubble.mine', { hasText: openingBody });
			await expect(ownBubble).toBeVisible({ timeout: 10_000 });
			// The composer clears on a successful round-trip.
			await expect(composer).toHaveValue('');
			// No send-error banner appeared (a permitted send).
			await expect(page.locator('.send-error[role="alert"]')).toHaveCount(0);

			// Backend: exactly one A→C row with the opening body, unread.
			const { data: rows } = await admin
				.from('direct_messages')
				.select('sender_id, recipient_id, read_at')
				.eq('sender_id', USER_A.id)
				.eq('recipient_id', USER_C_PRO.id)
				.eq('body', openingBody);
			expect(rows?.length ?? 0).toBe(1);
			expect(rows?.[0]?.read_at ?? null).toBeNull();
		});

		// ── 3-4. USER_C_PRO: unread badge → open → reply ────────────────
		await test.step('USER_C_PRO sees the unread badge, opens the thread, and replies', async () => {
			const ctx = await browser.newContext({
				storageState: USER_C_PRO.storageStatePath
			});
			const guestPage = await ctx.newPage();
			try {
				// Thread list (no id): the conversation shows with an unread
				// badge for the message C hasn't read yet.
				await guestPage.goto('/messages');
				const thread = guestPage.locator('.thread', { hasText: openingBody });
				await expect(thread).toBeVisible({ timeout: 10_000 });
				await expect(thread.locator('.badge')).toBeVisible();

				// Opening the thread marks it read (markDmThreadRead) and the
				// badge clears in place.
				await thread.click();
				await guestPage.waitForURL(`**/messages/${USER_A.id}`, {
					timeout: 10_000
				});
				// A's message is an OTHER bubble for C (not .mine).
				await expect(
					guestPage.locator('.bubble:not(.mine)', { hasText: openingBody })
				).toBeVisible({ timeout: 10_000 });
				await expect(
					guestPage
						.locator('.thread', { hasText: openingBody })
						.locator('.badge')
				).toHaveCount(0, { timeout: 10_000 });

				// C replies; it renders as C's own bubble + clears the composer.
				const composer = guestPage.getByPlaceholder('Message…');
				await composer.fill(replyBody);
				await guestPage.getByRole('button', { name: 'Send' }).click();
				await expect(
					guestPage.locator('.bubble.mine', { hasText: replyBody })
				).toBeVisible({ timeout: 10_000 });
				await expect(composer).toHaveValue('');

				// Backend: A's opening message is now read; C's reply landed.
				await expect
					.poll(
						async () => {
							const { data } = await admin
								.from('direct_messages')
								.select('read_at')
								.eq('sender_id', USER_A.id)
								.eq('recipient_id', USER_C_PRO.id)
								.eq('body', openingBody)
								.single();
							return data?.read_at;
						},
						{ timeout: 10_000 }
					)
					.not.toBeNull();
				const { data: replyRows } = await admin
					.from('direct_messages')
					.select('id, read_at')
					.eq('sender_id', USER_C_PRO.id)
					.eq('recipient_id', USER_A.id)
					.eq('body', replyBody);
				expect(replyRows?.length ?? 0).toBe(1);
				expect(replyRows?.[0]?.read_at ?? null).toBeNull();
			} finally {
				await ctx.close();
			}
		});

		// ── 5. USER_A sees the unread badge for C's reply on the list ───
		// This MUST come before A opens the thread: visiting /messages/[C]
		// fires the page's onMount→openThread $effect, which calls
		// markDmThreadRead and clears C's reply as unread. So the honest
		// sequence is list-with-badge → open → badge-gone, not the reverse.
		await test.step("USER_A's thread list shows the unread badge for C's reply", async () => {
			await page.goto('/messages');
			const thread = page.locator('.thread', { hasText: replyBody });
			await expect(thread).toBeVisible({ timeout: 10_000 });
			await expect(thread.locator('.badge')).toBeVisible();

			// Backend: C's reply is still unread before A opens the thread.
			const { data: preOpen } = await admin
				.from('direct_messages')
				.select('read_at')
				.eq('sender_id', USER_C_PRO.id)
				.eq('recipient_id', USER_A.id)
				.eq('body', replyBody)
				.single();
			expect(preOpen?.read_at ?? null).toBeNull();
		});

		// ── 6. USER_A opens the thread: it reads in order + badge clears ─
		await test.step('USER_A opens the thread — it reads in order and the badge clears', async () => {
			await page.goto(`/messages/${USER_C_PRO.id}`);
			// A's opening is an own bubble; C's reply is an other bubble.
			await expect(
				page.locator('.bubble.mine', { hasText: openingBody })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.locator('.bubble:not(.mine)', { hasText: replyBody })
			).toBeVisible({ timeout: 10_000 });

			// Send order: the opening bubble precedes the reply bubble.
			const bubbleTexts = await page.locator('.bubble .text').allInnerTexts();
			const openIdx = bubbleTexts.findIndex((t) => t.includes(openingBody));
			const replyIdx = bubbleTexts.findIndex((t) => t.includes(replyBody));
			expect(openIdx).toBeGreaterThanOrEqual(0);
			expect(replyIdx).toBeGreaterThan(openIdx);

			// Opening the conversation marked C's reply read; the badge clears.
			await expect(
				page.locator('.thread', { hasText: replyBody }).locator('.badge')
			).toHaveCount(0, { timeout: 10_000 });

			// A fresh /messages load confirms the badge stays gone, and the
			// read_at cross-check (null → set) holds on C's reply row.
			await page.goto('/messages');
			await expect(
				page.locator('.thread', { hasText: replyBody }).locator('.badge')
			).toHaveCount(0, { timeout: 10_000 });
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('direct_messages')
							.select('read_at')
							.eq('sender_id', USER_C_PRO.id)
							.eq('recipient_id', USER_A.id)
							.eq('body', replyBody)
							.single();
						return data?.read_at;
					},
					{ timeout: 10_000 }
				)
				.not.toBeNull();
		});

		// ── 7. Permission boundary: USER_B cannot DM USER_C ─────────────
		await test.step('USER_B (no follow edge with USER_C) is rejected — no row lands', async () => {
			const ctx = await browser.newContext({
				storageState: USER_B.storageStatePath
			});
			const guestPage = await ctx.newPage();
			try {
				await guestPage.goto(`/messages/${USER_C_PRO.id}`);
				const composer = guestPage.getByPlaceholder('Message…');
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill(`e2e-dm-journey-blocked ${stamp}`);
				await guestPage.getByRole('button', { name: 'Send' }).click();

				// The send-failure surfaces in the role="alert" banner — never a
				// silent swallow, never the bubble appearing as if it sent.
				const alert = guestPage.locator('.send-error[role="alert"]');
				await expect(alert).toBeVisible({ timeout: 10_000 });
				await expect(alert).toContainText(
					/can only message people you follow/i
				);

				// Fail-closed: nothing was written B→C.
				const { data } = await admin
					.from('direct_messages')
					.select('id')
					.eq('sender_id', USER_B.id)
					.eq('recipient_id', USER_C_PRO.id);
				expect(data?.length ?? 0).toBe(0);
			} finally {
				await ctx.close();
			}
		});
	});
});
