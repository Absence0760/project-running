import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /messages — DM permission boundaries + unread plumbing (#55).
 *
 * `dm.spec.ts` covers the happy-path send (A↔B follow each other) + the
 * anon prompt. This file pins the gates the RLS contract enforces and the
 * inbox plumbing the happy path glosses over:
 *
 *   (a) the follow-graph send gate — USER_B and USER_C_PRO have NO follow
 *       edge in the seed (A→B, A→C, B→A), so B sending to C is rejected with
 *       the friendly "you can only message people you follow" error, never a
 *       silent no-op or an uncaught throw. No row lands.
 *   (b) a block overrides an existing follow edge — A follows B and B follows
 *       A, but if A blocks B, B can no longer message A (fail-closed).
 *   (c) the recipient's unread badge: a message from A to B shows an unread
 *       count on B's thread list, and opening the conversation clears it
 *       (markDmThreadRead).
 *
 * Each test cleans up the messages (and any block) it plants so the seed
 * follow/block shape downstream specs rely on stays intact.
 */

test.describe('/messages — permission boundaries', () => {
	test.afterEach(async () => {
		const admin = getAdminClient();
		// Wipe every test message between the three seeded users in both
		// directions, plus any block we planted.
		const ids = [USER_A.id, USER_B.id, USER_C_PRO.id];
		await admin.from('direct_messages').delete().in('sender_id', ids).in('recipient_id', ids);
		await admin.from('user_blocks').delete().eq('blocker_id', USER_A.id).eq('blocked_id', USER_B.id);
	});

	test('USER_B cannot DM USER_C: no follow edge → friendly error, no row lands', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/messages/${USER_C_PRO.id}`);

			const composer = page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(`e2e-should-fail ${Date.now()}`);
			await page.getByRole('button', { name: 'Send' }).click();

			// The send-failure surfaces in the role="alert" banner — never a
			// silent swallow, never the message bubble appearing as if it sent.
			const alert = page.locator('.send-error[role="alert"]');
			await expect(alert).toBeVisible({ timeout: 10_000 });
			await expect(alert).toContainText(/can only message people you follow/i);

			// Fail-closed: nothing was written.
			const { data } = await getAdminClient()
				.from('direct_messages')
				.select('id')
				.eq('sender_id', USER_B.id)
				.eq('recipient_id', USER_C_PRO.id);
			expect(data?.length ?? 0).toBe(0);
		} finally {
			await ctx.close();
		}
	});

	test('a block overrides an existing follow edge: blocked sender is rejected', async ({
		browser
	}) => {
		// A follows B and B follows A in the seed, so absent a block B→A would
		// be allowed. Plant a block (A blocks B) and assert B can no longer
		// reach A — the gate is fail-closed on a block even with a live follow.
		await getAdminClient()
			.from('user_blocks')
			.insert({ blocker_id: USER_A.id, blocked_id: USER_B.id });

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/messages/${USER_A.id}`);
			const composer = page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill(`e2e-blocked ${Date.now()}`);
			await page.getByRole('button', { name: 'Send' }).click();

			await expect(page.locator('.send-error[role="alert"]')).toBeVisible({ timeout: 10_000 });

			const { data } = await getAdminClient()
				.from('direct_messages')
				.select('id')
				.eq('sender_id', USER_B.id)
				.eq('recipient_id', USER_A.id);
			expect(data?.length ?? 0).toBe(0);
		} finally {
			await ctx.close();
		}
	});

	test('recipient sees an unread badge that clears when the conversation is opened', async ({
		browser
	}) => {
		const body = `e2e-unread ${Date.now()}`;
		// A sends B a message directly (A→B is a valid follow edge) so B has a
		// genuine unread to render.
		await getAdminClient()
			.from('direct_messages')
			.insert({ sender_id: USER_A.id, recipient_id: USER_B.id, body });

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		const page = await ctx.newPage();
		try {
			// Thread list (no id in the URL) shows the conversation with an
			// unread badge for the message B hasn't read yet.
			await page.goto('/messages');
			const thread = page.locator('.thread', { hasText: body });
			await expect(thread).toBeVisible({ timeout: 10_000 });
			await expect(thread.locator('.badge')).toBeVisible();

			// Opening the conversation marks it read; the badge clears.
			await thread.click();
			await expect(page.getByText(body)).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.thread', { hasText: body }).locator('.badge')).toHaveCount(0, {
				timeout: 10_000
			});

			// read_at is persisted on the row.
			await expect
				.poll(
					async () => {
						const { data } = await getAdminClient()
							.from('direct_messages')
							.select('read_at')
							.eq('sender_id', USER_A.id)
							.eq('recipient_id', USER_B.id)
							.eq('body', body)
							.single();
						return data?.read_at;
					},
					{ timeout: 10_000 }
				)
				.not.toBeNull();
		} finally {
			await ctx.close();
		}
	});
});
