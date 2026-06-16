import { expect, test } from '@playwright/test';

import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser
} from '../fixtures/saga-users';
import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { deleteClub, setClubMemberRole } from '../fixtures/simulate';

/**
 * Club membership + role-operations LIFECYCLE journey.
 *
 * The granular clubs specs each pin ONE hop of the membership arc:
 *   - approval.spec.ts        — admin approves/rejects a *seeded* pending row
 *   - bulk-approve.spec.ts    — approve-all over many pending rows
 *   - join-flow.spec.ts       — the /clubs/join/[token] invite landing
 *   - invite-rotation.spec.ts — rotating the invite token
 *   - members.spec.ts         — the role <select> on the Members tab
 * None of them walk the STITCHED arc, where each hop's state is the
 * precondition for the next. This saga does the whole story as one
 * thread, with TWO real users in two browser contexts:
 *
 *   1. OWNER creates an approval-required club (public + join_policy
 *      'request'). The enroll_club_owner_trigger (AFTER INSERT ON
 *      clubs) seats the owner as an 'owner' club_members row — even on
 *      a service-role insert (triggers fire regardless of RLS bypass),
 *      so we NEVER insert the owner row by hand (it would dup-key on
 *      the (club_id,user_id) unique constraint).
 *   2. JOINER (a non-member) visits the club page and clicks
 *      "Request to join" → lands status='pending' (the request-policy
 *      INSERT gate, migration 20260702_001). They can NOT yet post.
 *   3. OWNER sees the pending-requests admin panel, approves the
 *      request (approveMember flips status→'active').
 *   4. JOINER, now an active member, posts in the club feed — the
 *      "members can post" RLS policy (migration 20260428_001) lets any
 *      active member write; the owner sees the post.
 *   5. OWNER promotes the member to 'admin' via the Members-tab role
 *      <select> (setMemberRole).
 *   6. OWNER removes the (now-admin) member via the person_remove
 *      kick button (removeMember deletes the row).
 *   7. JOINER reloads: they are a non-member again — the hero shows
 *      "Request to join" instead of the post composer, and a direct
 *      service-role-checked post INSERT *as the joiner* is rejected by
 *      RLS. This is the load-bearing security assertion: removing a
 *      member who held an elevated (admin) role must revoke BOTH the
 *      membership AND every capability that rode on it. A removed
 *      ex-admin who could still post would be a real RLS gap.
 *
 * Why public+request, not is_public=false+request: a PRIVATE club is
 * invisible to non-members (`clubs for select using is_public=true`,
 * pinned by private-rls-negative.spec.ts), so a non-member can't even
 * load the page to request to join — the only private-club entry is an
 * invite token. "Approval-required" is therefore a PUBLIC, request-
 * policy club, which is the realistic surface this arc lives on.
 *
 * Cleanup runs in a finally: deleteClub drops the club (cascading its
 * members/posts), deleteSagaUsers wipes the auth.users rows.
 */

function setConsentAccepted() {
	// Saga contexts start cookieless; the consent banner is a
	// role="dialog" that floats over the hero actions + admin panels,
	// intercepting clicks. Pre-accept it before any navigation.
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

const uniqueSuffix = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('saga: request-to-join → approve → post → promote → remove → access revoked', () => {
	test.describe.configure({ timeout: 120_000 });

	let users: SagaUser[];

	test.beforeAll(async () => {
		users = await createSagaUsers(2, {
			displayNames: ['Lifecycle Owner', 'Lifecycle Joiner']
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('one non-member walks request → approve → participate → promote → remove → lose access', async ({
		browser
	}) => {
		const [owner, joiner] = users;
		let clubId: string | null = null;

		const ownerCtx = await browser.newContext({
			storageState: owner.storageStatePath
		});
		const joinerCtx = await browser.newContext({
			storageState: joiner.storageStatePath
		});
		await ownerCtx.addInitScript(setConsentAccepted);
		await joinerCtx.addInitScript(setConsentAccepted);
		const ownerPage = await ownerCtx.newPage();
		const joinerPage = await joinerCtx.newPage();

		try {
			// ── 0. Seed an approval-required club owned by `owner`. ──
			// Service-role insert; the enroll_club_owner_trigger seats the
			// owner's 'owner' club_members row for us. Slug carries a digit
			// so /clubs/<slug> can never collide with /clubs/new.
			const slug = `lifecycle-club-${uniqueSuffix()}`;
			const clubName = `Lifecycle Club ${uniqueSuffix()}`;
			const { data: clubRow, error: clubErr } = await getAdminClient()
				.from('clubs')
				.insert({
					owner_id: owner.id,
					name: clubName,
					slug,
					is_public: true,
					join_policy: 'request'
				})
				.select('id')
				.single();
			if (clubErr || !clubRow) {
				throw new Error(`club seed failed: ${clubErr?.message ?? 'no row'}`);
			}
			clubId = clubRow.id as string;

			await test.step('owner sees their approval-required club (owner role from trigger)', async () => {
				await ownerPage.goto(`/clubs/${slug}`);
				await expect(
					ownerPage.getByRole('heading', { level: 1, name: clubName })
				).toBeVisible({ timeout: 10_000 });
				// The trigger seated the owner row, so the owner affordance
				// (Delete club) renders — not a Join button.
				await expect(
					ownerPage.getByRole('button', { name: /Delete club/ })
				).toBeVisible({ timeout: 10_000 });
				await expect(ownerPage.locator('.role-line')).toContainText('owner');
			});

			await test.step('joiner requests to join → lands pending, cannot post yet', async () => {
				await joinerPage.goto(`/clubs/${slug}`);
				// request-policy clubs render "Request to join", not "Join club".
				const requestBtn = joinerPage.getByRole('button', {
					name: 'Request to join'
				});
				await expect(requestBtn).toBeVisible({ timeout: 10_000 });
				await requestBtn.click();

				// joinClub returns 'pending' → the page surfaces the
				// requestSent notice + the button flips to a disabled
				// "Request pending".
				await expect(
					joinerPage.getByText('Request sent. An admin will review it.')
				).toBeVisible({ timeout: 10_000 });
				await expect(
					joinerPage.getByRole('button', { name: 'Request pending' })
				).toBeVisible({ timeout: 10_000 });

				// A pending member is NOT active → the post composer
				// ({#if isMember}) must not render.
				await expect(joinerPage.locator('form.post-form textarea')).toHaveCount(0);

				// DB sanity: the row exists with status='pending', role='member'.
				const { data: m } = await getAdminClient()
					.from('club_members')
					.select('status, role')
					.eq('club_id', clubId!)
					.eq('user_id', joiner.id)
					.maybeSingle();
				expect(m).not.toBeNull();
				expect((m as { status: string }).status).toBe('pending');
				expect((m as { role: string }).role).toBe('member');
			});

			await test.step('owner sees the pending request + approves it', async () => {
				await ownerPage.reload();
				const pendingPanel = ownerPage.locator('section.admin-card', {
					hasText: /Pending requests/
				});
				await expect(pendingPanel).toBeVisible({ timeout: 10_000 });
				await expect(pendingPanel).toContainText('Pending requests (1)');
				await expect(pendingPanel.locator('.pending-row')).toContainText(
					'Lifecycle Joiner'
				);

				await pendingPanel.getByRole('button', { name: 'Approve' }).click();
				// {#if pending.length > 0} guard hides the panel once empty.
				await expect(pendingPanel).toHaveCount(0, { timeout: 10_000 });

				// approveMember flipped status→'active'.
				const { data: m } = await getAdminClient()
					.from('club_members')
					.select('status')
					.eq('club_id', clubId!)
					.eq('user_id', joiner.id)
					.maybeSingle();
				expect((m as { status: string }).status).toBe('active');
			});

			const postBody = `joiner lifecycle post ${uniqueSuffix()}`;
			await test.step('approved member posts in the feed; owner sees it', async () => {
				await joinerPage.reload();
				// Now an active member → the role line + post composer render.
				await expect(joinerPage.locator('.role-line')).toContainText(
					"You're a member",
					{ timeout: 10_000 }
				);
				const composer = joinerPage.locator('form.post-form textarea');
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill(postBody);
				await joinerPage
					.locator('form.post-form button[type="submit"]')
					.click();
				// On success the composer clears + the post renders in the feed.
				await expect(composer).toHaveValue('', { timeout: 10_000 });
				await expect(
					joinerPage.locator('.feed .post-body', { hasText: postBody })
				).toBeVisible({ timeout: 10_000 });

				// Owner sees the member's post (cold-start poll / realtime
				// reload picks it up; reload is deterministic).
				await ownerPage.reload();
				await expect(
					ownerPage.locator('.feed .post-body', { hasText: postBody })
				).toBeVisible({ timeout: 15_000 });
			});

			await test.step('owner promotes the member to admin via the role select', async () => {
				await ownerPage.getByRole('tab', { name: /^Members/ }).click();
				const memberList = ownerPage.locator('.member-list');
				await expect(memberList).toBeVisible({ timeout: 10_000 });
				const joinerRow = memberList.locator('.member', {
					hasText: 'Lifecycle Joiner'
				});
				await expect(joinerRow).toBeVisible({ timeout: 10_000 });

				// The admin viewer sees a role <select> (not a badge) for a
				// non-owner member. Promote member → admin.
				const roleSelect = joinerRow.locator('select.role-select');
				await expect(roleSelect).toBeVisible({ timeout: 10_000 });
				await expect(roleSelect).toHaveValue('member');
				await roleSelect.selectOption('admin');
				// The select's bound value flips to 'admin' immediately on
				// change; the setMemberRole write is async, so poll the DB
				// rather than treat the bound value as proof of persistence.
				await expect(roleSelect).toHaveValue('admin', { timeout: 10_000 });
				const readRole = async (): Promise<string | null> => {
					const { data } = await getAdminClient()
						.from('club_members')
						.select('role')
						.eq('club_id', clubId!)
						.eq('user_id', joiner.id)
						.maybeSingle();
					return (data as { role: string } | null)?.role ?? null;
				};
				await expect.poll(readRole, { timeout: 10_000 }).toBe('admin');
				// Status is unchanged by a role promotion.
				const { data: m } = await getAdminClient()
					.from('club_members')
					.select('status')
					.eq('club_id', clubId!)
					.eq('user_id', joiner.id)
					.maybeSingle();
				expect((m as { status: string }).status).toBe('active');
			});

			await test.step('owner removes the (now-admin) member via the kick button', async () => {
				const memberList = ownerPage.locator('.member-list');
				const joinerRow = memberList.locator('.member', {
					hasText: 'Lifecycle Joiner'
				});
				// person_remove icon button → opens the remove ConfirmDialog.
				await joinerRow
					.getByRole('button', { name: 'Remove member' })
					.click();
				// ConfirmDialog confirm button reads "Remove".
				await ownerPage
					.getByRole('button', { name: 'Remove', exact: true })
					.last()
					.click();
				// The row drops out of the members list.
				await expect(joinerRow).toHaveCount(0, { timeout: 10_000 });

				// removeMember deleted the row entirely.
				const { data: m } = await getAdminClient()
					.from('club_members')
					.select('user_id')
					.eq('club_id', clubId!)
					.eq('user_id', joiner.id)
					.maybeSingle();
				expect(m).toBeNull();
			});

			await test.step('removed ex-admin loses access — composer gone + RLS rejects a post', async () => {
				await joinerPage.reload();
				// Back to a non-member: the hero shows "Request to join"
				// again, and the post composer is gone.
				await expect(
					joinerPage.getByRole('button', { name: 'Request to join' })
				).toBeVisible({ timeout: 10_000 });
				await expect(joinerPage.locator('form.post-form textarea')).toHaveCount(0);
				// Belt: the removed user cannot see the admin-only pending panel.
				await expect(
					joinerPage.locator('section.admin-card', {
						hasText: /Pending requests/
					})
				).toHaveCount(0);

				// Load-bearing security assertion. Drive the EXACT club_posts
				// INSERT the composer would issue, but through the joiner's
				// OWN authenticated REST session (not service-role) so RLS
				// is in force. The "members can post" policy (migration
				// 20260428_001) requires is_club_member(club_id); the joiner
				// was just removed (and previously held 'admin'), so the
				// insert must be rejected. A removed ex-admin who could still
				// post would be the real RLS gap this saga hunts for.
				const joinerClient = await getUserClient({
					email: joiner.email,
					password: joiner.password
				});
				const { data: postData, error: postError } = await joinerClient
					.from('club_posts')
					.insert({
						club_id: clubId!,
						author_id: joiner.id,
						body: `ghost post after removal ${uniqueSuffix()}`
					})
					.select('id');
				// RLS rejection surfaces as a PostgREST error (42501) with no
				// returned row — never a silent success.
				expect(postError).not.toBeNull();
				expect(postData ?? []).toHaveLength(0);

				// And the negative: no club_posts row authored by the joiner
				// leaked through (admin client bypasses RLS to read truth).
				const { count } = await getAdminClient()
					.from('club_posts')
					.select('id', { count: 'exact', head: true })
					.eq('club_id', clubId!)
					.eq('author_id', joiner.id);
				// The one post they made WHILE a member is still there (1);
				// the ghost post after removal never landed.
				expect(count).toBe(1);
			});
		} finally {
			if (clubId) {
				try {
					await deleteClub(clubId);
				} catch (_) {
					/* best-effort; deleteSagaUsers also sweeps owner clubs */
				}
			}
			// Reset role defensively in case a later edit re-creates the
			// row — harmless no-op when the membership is already gone.
			try {
				await setClubMemberRole(clubId ?? '', joiner.id, 'member');
			} catch (_) {
				/* row deleted — nothing to reset */
			}
			await ownerCtx.close();
			await joinerCtx.close();
		}
	});
});
