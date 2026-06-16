import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Multi-user coach <-> athlete roster JOURNEY — the full relationship from a
 * coach minting an invite link, through the athlete redeeming it in a second
 * browser context, the coach reviewing the now-linked athlete's runs, and the
 * coach revoking the link so the athlete drops off both sides.
 *
 * This complements the existing coaching specs, which each assert ONE boundary
 * by SEEDING the link via the admin client (invite.spec, link-lifecycle,
 * coach-athlete-depth). None of them drive the real end-to-end path that a user
 * actually walks: mint in the UI -> capture the generated token -> redeem it as
 * a different signed-in user -> see the new athlete on the roster -> open the
 * review surface -> revoke -> confirm both sides drop the relationship. That is
 * the journey pinned here, in one flow, with no seeded coach_athletes row.
 *
 * Users: USER_B (alex) is the COACH; USER_C_PRO (morgan) is the ATHLETE.
 * Seeded, not saga: seed.sql creates no coach_athletes rows for either user
 * (every existing coaching spec clears links in beforeEach, which only works
 * because the seed leaves them unlinked), so there is no conflicting role to
 * trip the invite/accept. Morgan carries 13 NOW()-relative seeded runs, which
 * gives the review surface (step 4) real athlete data to render. The link is
 * created by the journey itself and torn down by the revoke step + the
 * clearLinks() teardown, so the spec restores the seeded users' state.
 *
 * Token capture: createCoachInvite() does NOT render the token into the DOM —
 * mintInvite() copies the invite URL to the clipboard and shows only a generic
 * "Pending invite" row. So the journey grants clipboard permissions, clicks
 * "Invite an athlete", and reads the URL back out of the clipboard to recover
 * the token (the only UI-reachable source). It is cross-checked against the DB
 * so a clipboard hiccup fails loudly rather than redeeming a bogus token.
 *
 * createCoachInvite is a plain INSERT into coach_athletes with no rate-limit
 * trigger (unlike create_club / create_route), so no rate-limit reset is needed.
 */

async function clearLinks() {
	const admin = getAdminClient();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
}

test.describe('coach <-> athlete roster journey (invite -> accept -> review -> revoke)', () => {
	// The COACH (USER_B) owns the default page/context this spec runs in.
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(clearLinks);
	test.afterEach(clearLinks);

	test('a coach invites an athlete, reviews their runs, then revokes the link', async ({
		page,
		context,
		browser
	}, testInfo) => {
		// The coach reads the minted invite URL off the clipboard.
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);

		let inviteToken = '';
		const baseURL = testInfo.project.use.baseURL ?? 'http://localhost:7777';

		// The athlete acts in a SEPARATE browser context (its own storage state /
		// session) — a genuine second user, not a tab of the coach's session.
		let athleteContext: BrowserContext | null = null;

		try {
			await test.step('coach mints an invite link and captures the token', async () => {
				await page.goto('/coaching');
				await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
					timeout: 10_000
				});
				// No pending invite or athlete yet (clean link state).
				await expect(page.getByText('Pending invite')).toHaveCount(0);

				await page.getByRole('button', { name: 'Invite an athlete' }).click();

				// The pending-invite row appears once the insert lands.
				await expect(page.getByText('Pending invite')).toBeVisible({ timeout: 10_000 });

				// The token isn't rendered into the DOM — mintInvite copies the
				// /coaching/accept/<token> URL to the clipboard. Read it back.
				const clipText = await page.evaluate(() => navigator.clipboard.readText());
				const match = clipText.match(/\/coaching\/accept\/([0-9a-f]+)/i);
				expect(match, `invite URL not on clipboard, got: ${clipText}`).not.toBeNull();
				inviteToken = match![1];
				expect(inviteToken.length).toBeGreaterThan(0);

				// Cross-check the captured token against the DB row so a clipboard
				// hiccup can't silently redeem a wrong/empty token downstream.
				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('invite_token, status, athlete_id')
					.eq('coach_id', USER_B.id)
					.is('athlete_id', null)
					.single();
				expect(data?.invite_token).toBe(inviteToken);
				expect(data?.status).toBe('pending');
			});

			await test.step('athlete redeems the invite in a second context', async () => {
				athleteContext = await browser.newContext({
					baseURL,
					storageState: USER_C_PRO.storageStatePath
				});
				const athletePage: Page = await athleteContext.newPage();

				// The public accept landing redeems via redeem_coach_invite and, on
				// success, redirects the signed-in athlete to /coaching.
				await athletePage.goto(`/coaching/accept/${inviteToken}`);
				await athletePage.waitForURL(/\/coaching$/, { timeout: 15_000 });
				await expect(
					athletePage.getByRole('heading', { level: 1, name: 'Coaching' })
				).toBeVisible({ timeout: 10_000 });

				// The athlete now sees the coach under "My coaches".
				await expect(
					athletePage.getByRole('heading', { level: 2, name: 'My coaches' })
				).toBeVisible({ timeout: 10_000 });
				await expect(athletePage.locator(`a[href="/u/${USER_B.id}"]`)).toBeVisible({
					timeout: 10_000
				});

				// And the link is active in the DB — the invite was consumed by the
				// athlete, not left pending.
				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('status, athlete_id')
					.eq('coach_id', USER_B.id)
					.eq('invite_token', inviteToken)
					.single();
				expect(data?.status).toBe('active');
				expect(data?.athlete_id).toBe(USER_C_PRO.id);
			});

			await test.step('coach sees the new athlete on the roster', async () => {
				await page.goto('/coaching');
				await expect(page.getByRole('heading', { level: 1, name: 'Coaching' })).toBeVisible({
					timeout: 10_000
				});
				// The pending row is gone (redeemed) and the athlete row is present,
				// linking to the coach review surface.
				await expect(page.getByText('Pending invite')).toHaveCount(0, { timeout: 10_000 });
				const athleteLink = page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`);
				await expect(athleteLink.first()).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator(`a.link-name[href="/coaching/athletes/${USER_C_PRO.id}"]`)
				).toHaveText('Morgan Lee');
			});

			await test.step('coach opens the athlete review surface and sees their runs', async () => {
				await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
				// Both review sections render for an on-roster athlete.
				await expect(
					page.getByRole('heading', { level: 2, name: 'Recent runs' })
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.getByRole('heading', { level: 2, name: 'Plan compliance' })
				).toBeVisible({ timeout: 10_000 });

				// Morgan's NOW()-relative seeded runs land in the recent window, so the
				// surface renders the athlete's data via the `active coach reads
				// athlete runs` RLS policy (decisions §98) — not the empty state.
				await expect(page.getByText('No runs yet')).toHaveCount(0);
				expect(await page.locator('.run-list .run-row').count()).toBeGreaterThanOrEqual(1);
			});

			await test.step('coach revokes the link; the athlete drops off the roster', async () => {
				await page.goto('/coaching');
				const athleteLink = page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`);
				await expect(athleteLink.first()).toBeVisible({ timeout: 10_000 });

				// Remove routes through the shared ConfirmDialog.
				await page.getByRole('button', { name: 'Remove' }).first().click();
				const dialog = page.locator('.modal', { hasText: 'Remove' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Remove' }).click();

				// The athlete row is gone from the coach's roster.
				await expect(athleteLink).toHaveCount(0, { timeout: 10_000 });

				// The review surface is now refused (RLS, not just a hidden list row).
				await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
				await expect(
					page.getByRole('heading', { name: 'Not on your roster' })
				).toBeVisible({ timeout: 10_000 });

				// The link row is ended (not deleted).
				const { data } = await getAdminClient()
					.from('coach_athletes')
					.select('status')
					.eq('coach_id', USER_B.id)
					.eq('athlete_id', USER_C_PRO.id)
					.single();
				expect(data?.status).toBe('ended');
			});

			await test.step('the athlete no longer sees the coach in their coach list', async () => {
				const athletePage: Page = await athleteContext!.newPage();
				await athletePage.goto('/coaching');
				await expect(
					athletePage.getByRole('heading', { level: 1, name: 'Coaching' })
				).toBeVisible({ timeout: 10_000 });
				// The coach has dropped off "My coaches" — the link is ended on both sides.
				await expect(athletePage.locator(`a[href="/u/${USER_B.id}"]`)).toHaveCount(0, {
					timeout: 10_000
				});
			});
		} finally {
			if (athleteContext) await athleteContext.close();
		}
	});
});
