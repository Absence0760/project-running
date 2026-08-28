import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRow, readRows } from '../fixtures/db-read';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Typed route attachment on the DM rail (route_direct_share.md v2,
 * migration `20270619_001`, decisions § 772).
 *
 * v1 put the public `/share/route/[id]` URL in the message body, and the
 * thread rendered `{m.body}` as escaped text with no linkification — so what
 * the recipient received was an unclickable string. v2 adds `route_id` and
 * renders the card; the body keeps the URL, because it is the forwardable
 * artifact the send dialog promises and the only thing the inbox preview line
 * and the Art 20 export read.
 *
 * The privacy question this pins is the recipient's: a card in a thread is a
 * non-owner surface showing someone else's polyline, so it resolves through
 * `fetchRouteById` (public_routes view + clip_route_for_viewer), and a route
 * the recipient may not see says so rather than degrading to the dead URL.
 */

const SHARE_PATH = `/share/route/${RUNNER_PUBLIC_ROUTE_ID}`;
const PRIVATE_ROUTE_ID = 'dddd0772-0000-4000-8000-00000000ab01';

async function clearDms() {
	const ids = [USER_A.id, USER_B.id, USER_C_PRO.id];
	await getAdminClient().from('direct_messages').delete().in('sender_id', ids).in('recipient_id', ids);
}

test.describe('DM route attachment', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await getAdminClient()
			.from('routes')
			.update({ is_public: true })
			.eq('id', RUNNER_PUBLIC_ROUTE_ID);
		await clearDms();
	});

	test.afterEach(async () => {
		await clearDms();
		await getAdminClient().from('routes').delete().eq('id', PRIVATE_ROUTE_ID);
	});

	test('the send stores a typed route_id and the recipient sees a card, not a URL', async ({
		page,
		browser
	}) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: /Alex Chen/ }).click();
		await expect(page.getByTestId('send-route-sent')).toContainText('Alex Chen');

		// The row carries BOTH: the typed attachment the card draws, and the
		// share URL the inbox preview and the export still read.
		const rows = await readRows(
			'direct_messages sent by USER_A',
			getAdminClient()
				.from('direct_messages')
				.select('body, route_id, recipient_id')
				.eq('sender_id', USER_A.id)
		);
		expect(rows).toHaveLength(1);
		const sent = rows[0] as { body: string; route_id: string | null; recipient_id: string };
		expect(sent.recipient_id).toBe(USER_B.id);
		expect(sent.route_id).toBe(RUNNER_PUBLIC_ROUTE_ID);
		expect(sent.body).toContain(SHARE_PATH);

		const recipient = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const recipientPage = await recipient.newPage();
			await recipientPage.goto(`/messages/${USER_A.id}`);

			const card = recipientPage.getByTestId('dm-route-attachment');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(card).toHaveAttribute('href', `/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
			await expect(card).toContainText('E2E demo public route');

			// The URL the card replaced is gone from the BUBBLE — that is the
			// whole point of v2 — while still sitting in the inbox preview, which
			// reads `dm_threads()`'s `last_body` and resolves no attachment. Both
			// halves are asserted: a page-wide count would fail on the preview and
			// read as the suppression being broken.
			await expect(recipientPage.locator('.bubble .text')).toHaveCount(0);
			await expect(
				recipientPage.locator('.bubble').getByText(SHARE_PATH, { exact: false })
			).toHaveCount(0);
			await expect(
				recipientPage.locator('.preview').getByText(SHARE_PATH, { exact: false })
			).toHaveCount(1);

			// And the card is the way through to the route.
			await card.click();
			await recipientPage.waitForURL(`**/routes/${RUNNER_PUBLIC_ROUTE_ID}`, { timeout: 15_000 });
		} finally {
			await recipient.close();
		}
	});

	test('a route the recipient cannot see says so instead of showing a dead link', async ({
		browser
	}) => {
		// Planted service-side: the INSERT policy refuses an attachment the
		// SENDER cannot see, so a route invisible to the RECIPIENT and visible
		// to nobody else has to be inserted around RLS to reach the render at
		// all. This is the state a route reaches when its owner flips it back
		// to private after sending it.
		const admin = getAdminClient();
		await admin.from('routes').insert({
			id: PRIVATE_ROUTE_ID,
			user_id: USER_C_PRO.id,
			name: 'Private after the fact',
			waypoints: [
				{ lat: -37.82, lng: 144.97 },
				{ lat: -37.81, lng: 144.98 }
			],
			distance_m: 4200,
			is_public: false
		});
		await admin.from('direct_messages').insert({
			sender_id: USER_A.id,
			recipient_id: USER_B.id,
			body: `http://localhost:8888/share/route/${PRIVATE_ROUTE_ID}`,
			route_id: PRIVATE_ROUTE_ID
		});

		const recipient = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const recipientPage = await recipient.newPage();
			await recipientPage.goto(`/messages/${USER_A.id}`);

			await expect(recipientPage.getByTestId('dm-route-attachment-unavailable')).toBeVisible({
				timeout: 15_000
			});
			await expect(recipientPage.getByTestId('dm-route-attachment')).toHaveCount(0);
			// It must not fall back to the body: a URL that 404s for this reader
			// is indistinguishable from a link someone typed. Scoped to the bubble
			// for the same reason as above — the inbox preview still carries it.
			await expect(
				recipientPage.locator('.bubble').getByText(PRIVATE_ROUTE_ID, { exact: false })
			).toHaveCount(0);
		} finally {
			await recipient.close();
		}
	});

	test('deleting the route keeps the message and drops only the attachment', async () => {
		const admin = getAdminClient();
		await admin.from('routes').insert({
			id: PRIVATE_ROUTE_ID,
			user_id: USER_A.id,
			name: 'Deleted later',
			waypoints: [
				{ lat: -37.82, lng: 144.97 },
				{ lat: -37.81, lng: 144.98 }
			],
			distance_m: 4200,
			is_public: true
		});
		await admin.from('direct_messages').insert({
			id: 'cccc0772-0000-4000-8000-00000000ab02',
			sender_id: USER_A.id,
			recipient_id: USER_B.id,
			body: 'see you there',
			route_id: PRIVATE_ROUTE_ID
		});

		await admin.from('routes').delete().eq('id', PRIVATE_ROUTE_ID);

		// ON DELETE SET NULL: a third party tidying their routes must not
		// delete someone's private correspondence.
		const row = await readRow(
			'the message that referenced the deleted route',
			admin
				.from('direct_messages')
				.select('body, route_id')
				.eq('id', 'cccc0772-0000-4000-8000-00000000ab02')
				.single()
		);
		expect((row as { route_id: string | null }).route_id).toBeNull();
		expect((row as { body: string }).body).toBe('see you there');
	});
});
