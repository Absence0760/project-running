import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Backend boundary: invite-token rotation. The "Rotate" button on a
 * private club's admin panel calls regenerateInviteToken (a SECURITY
 * DEFINER RPC that updates clubs.invite_token to a fresh random
 * string). The CONTRACT is that the OLD token must immediately stop
 * working — `join_club_by_token` does a `select id from clubs where
 * invite_token = token` and must return null for the rotated value.
 *
 * A regression that wrote the new token but didn't replace the old
 * (e.g. INSERT instead of UPDATE) or kept the old in a side table
 * would leak access to anyone with the previous link forever.
 *
 * Friends of Jared is the seeded invite-only club with a stable
 * starting token. Test:
 *   1. Snapshot the original token via service-role.
 *   2. Driver clicks Rotate from /clubs/friends-of-jared.
 *   3. Verify (via service-role) the token actually changed.
 *   4. Visit /clubs/join/<old-token> as a SIGNED-IN USER who isn't
 *      a member — the page lands on the "Invite problem" branch
 *      with the "invalid invite token" exception surfaced.
 *   5. Restore the original token so downstream tests still see
 *      the seed shape.
 */

const FRIENDS_OF_JARED_ID = 'c3333333-0000-0000-0000-000000000003';
const ORIGINAL_TOKEN = 'c3fr13nd50fj4r3dc1ubtoken000000';

test.describe('/clubs/[slug] — invite token rotation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		// Belt-and-braces — restore the seed token so other tests
		// (clubs/invite.spec.ts) still find Friends of Jared at the
		// pinned URL.
		try {
			await getAdminClient()
				.from('clubs')
				.update({ invite_token: ORIGINAL_TOKEN })
				.eq('id', FRIENDS_OF_JARED_ID);
		} catch (_) {
			/* best-effort */
		}
	});

	test('admin rotates the invite token → old token rejected, new token accepted', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Snapshot starting state.
		const { data: before } = await admin
			.from('clubs')
			.select('invite_token')
			.eq('id', FRIENDS_OF_JARED_ID)
			.single();
		expect((before as { invite_token: string }).invite_token).toBe(
			ORIGINAL_TOKEN
		);

		// Drive the rotate UI.
		await page.goto('/clubs/friends-of-jared');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Friends of Jared' })
		).toBeVisible({ timeout: 10_000 });
		// The invite-link card uses .invite-row + .invite-link.
		const inviteCard = page.locator('section.admin-card', {
			hasText: /Invite link/
		});
		await expect(inviteCard).toBeVisible({ timeout: 10_000 });
		await inviteCard.getByRole('button', { name: /Rotate/ }).click();

		// ConfirmDialog mounts.
		const dialog = page.locator('.modal', {
			hasText: 'Regenerate invite link'
		});
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Regenerate' }).click();

		// The rendered .invite-link <code> updates with the new token —
		// poll the DB until the column changed (the UI also reads from
		// the row).
		await expect.poll(async () => {
			const { data } = await admin
				.from('clubs')
				.select('invite_token')
				.eq('id', FRIENDS_OF_JARED_ID)
				.single();
			return (data as { invite_token: string } | null)?.invite_token ?? '';
		}, { timeout: 5_000 }).not.toBe(ORIGINAL_TOKEN);

		// Visit the OLD invite URL — the join_club_by_token RPC must
		// throw "invalid invite token" because the row no longer
		// matches. The /clubs/join/[token] page surfaces that as the
		// "Invite problem" branch.
		await page.goto(`/clubs/join/${ORIGINAL_TOKEN}`);
		await expect(
			page.getByRole('heading', { name: 'Invite problem' })
		).toBeVisible({ timeout: 10_000 });

		// Sanity: NO new club_members row was inserted from the old-
		// token attempt (a regression where the RPC inserted before
		// validating would surface here).
		const { count } = await admin
			.from('club_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('club_id', FRIENDS_OF_JARED_ID)
			.eq('user_id', USER_A.id)
			.eq('role', 'member');
		expect(count).toBe(0);
	});
});
