import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * /messages — the send throttle refuses comprehensibly (migration
 * 20270608_001).
 *
 * The two send buckets are asserted server-side in
 * `direct_message_rate_limit_test.sql`; what only a browser can prove is
 * the rest of the chain — that the trigger's P0001 survives PostgREST,
 * reaches `sendDm`, is recognised by the shared `rateLimitErrorMessage`
 * parser rather than re-thrown raw, and lands in the composer's
 * role="alert" line instead of being swallowed. Before this wiring the
 * sender would have read `rate limit exceeded for
 * send_direct_message_burst, retry in 41s`.
 *
 * The bucket is pre-loaded to its ceiling through the admin client rather
 * than by sending 30 messages: this is a spec about the refusal, and 30
 * real sends would be thirty round trips and thirty rows to clean up.
 */

const BURST_BUCKET = 'send_direct_message_burst';
const BURST_MAX = 30;
const BURST_WINDOW_S = 60;

/// The window keys `check_rate_limit` could compute for this send — the
/// same floor-to-window arithmetic, or the pre-loaded row lands in a bucket
/// the trigger never looks at and the send goes through. BOTH the current
/// window and the next one are loaded: a fixed window that rolls between the
/// insert and the click would otherwise let the send succeed once a minute.
function windowStartsToLoad(windowSeconds: number): string[] {
	const epoch = Math.floor(Date.now() / 1000);
	const start = Math.floor(epoch / windowSeconds) * windowSeconds;
	return [start, start + windowSeconds].map((s) => new Date(s * 1000).toISOString());
}

test.describe('/messages — send throttle', () => {
	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin.from('rate_limits').delete().eq('user_id', USER_A.id).eq('bucket', BURST_BUCKET);
		await admin
			.from('direct_messages')
			.delete()
			.eq('sender_id', USER_A.id)
			.eq('recipient_id', USER_B.id);
	});

	test('a sender past the burst cap reads a wait-and-retry line, not a postgres exception', async ({
		browser
	}) => {
		// Upsert, not insert: an earlier spec in the same run may already have
		// spent part of USER_A's window, and a duplicate-key rejection here
		// would silently leave the cap unloaded and the send allowed.
		const { error: preload } = await getAdminClient()
			.from('rate_limits')
			.upsert(
				windowStartsToLoad(BURST_WINDOW_S).map((window_start) => ({
					user_id: USER_A.id,
					bucket: BURST_BUCKET,
					window_start,
					count: BURST_MAX
				})),
				{ onConflict: 'user_id,bucket,window_start' }
			);
		expect(preload).toBeNull();

		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/messages/${USER_B.id}`);

			const composer = page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			const body = `e2e-throttled ${Date.now()}`;
			await composer.fill(body);
			await page.getByRole('button', { name: 'Send' }).click();

			const alert = page.locator('.send-error[role="alert"]');
			await expect(alert).toBeVisible({ timeout: 10_000 });
			await expect(alert).toContainText(/too quickly/i);
			await expect(alert).toContainText(/try again/i);
			// The parser's job is to keep the raw exception out of the UI.
			await expect(alert).not.toContainText(/rate limit exceeded for/i);

			// The draft survives a refusal — a rejected send that also ate the
			// typed message would make the throttle look like data loss.
			await expect(composer).toHaveValue(body);

			// Fail-closed: nothing was written.
			const rows = await readRows(
				'direct_messages by sender_id+recipient_id',
				getAdminClient()
					.from('direct_messages')
					.select('id')
					.eq('sender_id', USER_A.id)
					.eq('recipient_id', USER_B.id)
			);
			expect(rows.length).toBe(0);
		} finally {
			await ctx.close();
		}
	});
});
