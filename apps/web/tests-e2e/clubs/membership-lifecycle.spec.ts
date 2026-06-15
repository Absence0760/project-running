import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug] — the full request-policy membership lifecycle driven
 * end-to-end through the UI, not pre-seeded at each step:
 *
 *   not a member → "Request to join" → status=pending → "Request
 *   pending" disabled CTA → owner approves from the admin panel →
 *   member sees the active member surface (post composer) → member
 *   leaves → back to "Request to join".
 *
 * Tempo Tuesday is the seeded join_policy='request' club. Morgan
 * (USER_C_PRO) isn't seeded into it, so each test starts from a clean
 * not-a-member state. afterEach sweeps morgan's row so the seed shape
 * is restored for downstream specs.
 *
 * The approve sub-flow uses two browser contexts (morgan requests,
 * owner approves) so the request really travels through RLS — the
 * `self-request join request-policy clubs` insert policy, then the
 * admin's `admins can manage members` update.
 */

const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

async function sweepMorgan(): Promise<void> {
	try {
		await getAdminClient()
			.from('club_members')
			.delete()
			.eq('club_id', TEMPO_TUESDAY_ID)
			.eq('user_id', USER_C_PRO.id);
	} catch (_) {
		/* best-effort */
	}
}

test.describe('/clubs/[slug] — request-policy membership lifecycle', () => {
	test.afterEach(async () => {
		await sweepMorgan();
	});

	test('request → pending CTA → owner approves → member composer → leave restores the Request CTA', async ({
		browser
	}) => {
		const admin = getAdminClient();
		await sweepMorgan();

		const ctxMorgan = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath
		});
		const ctxOwner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const morgan = await ctxMorgan.newPage();
		const owner = await ctxOwner.newPage();

		try {
			// ── Morgan: not a member → Request to join ──
			await morgan.goto('/clubs/tempo-tuesday');
			await expect(
				morgan.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })
			).toBeVisible({ timeout: 10_000 });

			// request-policy clubs show "Request to join", not "Join club".
			const requestBtn = morgan.getByRole('button', { name: 'Request to join' });
			await expect(requestBtn).toBeVisible({ timeout: 10_000 });
			// The post composer must NOT be mounted for a non-member.
			await expect(morgan.locator('.post-form textarea')).toHaveCount(0);

			await requestBtn.click();

			// The CTA flips to a disabled "Request pending" — the page
			// re-derives viewer_status='pending' from the inserted row.
			await expect(
				morgan.getByRole('button', { name: 'Request pending' })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				morgan.getByRole('button', { name: 'Request pending' })
			).toBeDisabled();
			// Still no composer — pending is not active membership.
			await expect(morgan.locator('.post-form textarea')).toHaveCount(0);

			// DB sanity: a pending (not active) row landed.
			const { data: reqRow } = await admin
				.from('club_members')
				.select('status, role')
				.eq('club_id', TEMPO_TUESDAY_ID)
				.eq('user_id', USER_C_PRO.id)
				.single();
			expect(reqRow?.status).toBe('pending');
			expect(reqRow?.role).toBe('member');

			// ── Owner: approve from the pending panel ──
			await owner.goto('/clubs/tempo-tuesday');
			const pendingPanel = owner.locator('section.admin-card', {
				hasText: /Pending requests/
			});
			await expect(pendingPanel).toBeVisible({ timeout: 10_000 });
			// Both alex (seeded pending) and morgan (just requested) are pending.
			await expect(pendingPanel).toContainText('Pending requests (2)');
			const morganRow = pendingPanel.locator('.pending-row', {
				hasText: 'Morgan'
			});
			await expect(morganRow).toBeVisible({ timeout: 10_000 });
			await morganRow.getByRole('button', { name: 'Approve' }).click();

			// Morgan's row leaves the panel; only alex remains.
			await expect(
				pendingPanel.locator('.pending-row', { hasText: 'Morgan' })
			).toHaveCount(0, { timeout: 10_000 });
			await expect(pendingPanel).toContainText('Pending requests (1)');

			// DB sanity: morgan is now active.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('club_members')
							.select('status')
							.eq('club_id', TEMPO_TUESDAY_ID)
							.eq('user_id', USER_C_PRO.id)
							.single();
						return data?.status;
					},
					{ timeout: 10_000 }
				)
				.toBe('active');

			// ── Morgan: reload → now an active member, composer mounts ──
			await morgan.reload();
			await expect(
				morgan.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })
			).toBeVisible({ timeout: 10_000 });
			await expect(
				morgan.locator('.post-form textarea').first()
			).toBeVisible({ timeout: 10_000 });

			// ── Morgan: leave → confirm → Request CTA returns ──
			await morgan.getByRole('button', { name: 'Leave' }).click();
			const dialog = morgan.locator('.modal', { hasText: 'Leave club' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Leave', exact: true }).click();

			await expect(
				morgan.getByRole('button', { name: 'Request to join' })
			).toBeVisible({ timeout: 10_000 });
			await expect(morgan.locator('.post-form textarea')).toHaveCount(0);

			// DB sanity: the row is gone (leave deletes, not soft-deletes).
			const { data: gone } = await admin
				.from('club_members')
				.select('user_id')
				.eq('club_id', TEMPO_TUESDAY_ID)
				.eq('user_id', USER_C_PRO.id)
				.maybeSingle();
			expect(gone).toBeNull();
		} finally {
			await ctxMorgan.close();
			await ctxOwner.close();
		}
	});

	test('owner rejecting a fresh request returns the requester to the Request-to-join CTA', async ({
		browser
	}) => {
		// Counterpart to approval.spec's seeded-pending reject: here the
		// request is made live, then rejected, and we assert the requester
		// can request AGAIN (the delete leaves no tombstone blocking a
		// re-request).
		const admin = getAdminClient();
		await sweepMorgan();

		const ctxMorgan = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath
		});
		const ctxOwner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const morgan = await ctxMorgan.newPage();
		const owner = await ctxOwner.newPage();

		try {
			await morgan.goto('/clubs/tempo-tuesday');
			await morgan.getByRole('button', { name: 'Request to join' }).click();
			await expect(
				morgan.getByRole('button', { name: 'Request pending' })
			).toBeVisible({ timeout: 10_000 });

			// Owner rejects morgan's request.
			await owner.goto('/clubs/tempo-tuesday');
			const pendingPanel = owner.locator('section.admin-card', {
				hasText: /Pending requests/
			});
			await expect(pendingPanel).toBeVisible({ timeout: 10_000 });
			const morganRow = pendingPanel.locator('.pending-row', {
				hasText: 'Morgan'
			});
			await expect(morganRow).toBeVisible({ timeout: 10_000 });
			await morganRow.getByRole('button', { name: 'Reject' }).click();
			await expect(
				pendingPanel.locator('.pending-row', { hasText: 'Morgan' })
			).toHaveCount(0, { timeout: 10_000 });

			// DB sanity: rejection deletes the row.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('club_members')
							.select('user_id')
							.eq('club_id', TEMPO_TUESDAY_ID)
							.eq('user_id', USER_C_PRO.id)
							.maybeSingle();
						return data === null;
					},
					{ timeout: 10_000 }
				)
				.toBe(true);

			// Morgan reloads → can request again (no lingering pending CTA).
			await morgan.reload();
			await expect(
				morgan.getByRole('button', { name: 'Request to join' })
			).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctxMorgan.close();
			await ctxOwner.close();
		}
	});

	test('a rejected member is locked out: no composer, and re-requesting is a no-op (the row stays rejected)', async ({
		browser
	}) => {
		// 'rejected' is the terminal lockout status (the club_members
		// status CHECK is active|pending|rejected — there is no 'banned').
		// Plant morgan rejected on Tempo Tuesday and assert the page shows
		// no active member surface (composer). A rejected row must not be
		// silently "upgraded" to a fresh pending request: the self-request
		// RLS insert collides with the existing (club_id,user_id) row and
		// the joinClub handler swallows the 23505 conflict, so the stored
		// status stays 'rejected' rather than flipping back to 'pending'.
		const admin = getAdminClient();
		const { error: upsertErr } = await admin.from('club_members').upsert(
			{
				club_id: TEMPO_TUESDAY_ID,
				user_id: USER_C_PRO.id,
				role: 'member',
				status: 'rejected'
			},
			{ onConflict: 'club_id,user_id' }
		);
		// Guard: if the CHECK rejected this value the rest of the test is
		// meaningless — fail loudly here rather than on a confusing later
		// assertion.
		expect(upsertErr).toBeNull();

		const ctx = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath
		});
		const morgan = await ctx.newPage();
		try {
			await morgan.goto('/clubs/tempo-tuesday');
			await expect(
				morgan.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })
			).toBeVisible({ timeout: 10_000 });

			// Rejected = no active membership → no composer.
			await expect(morgan.locator('.post-form textarea')).toHaveCount(0);

			// The page treats a rejected viewer as a non-member, so the
			// request CTA is still offered — click it and prove the insert
			// is a no-op against the existing row.
			const requestBtn = morgan.getByRole('button', {
				name: 'Request to join'
			});
			await expect(requestBtn).toBeVisible({ timeout: 10_000 });
			await requestBtn.click();
			// Give the (swallowed-conflict) insert a moment to resolve.
			await morgan
				.waitForLoadState('networkidle')
				.catch(() => {});

			// The stored row must still be 'rejected', never downgraded to
			// 'pending' (which would let a kicked-out user back into the
			// queue by reloading the page).
			const { data } = await admin
				.from('club_members')
				.select('status')
				.eq('club_id', TEMPO_TUESDAY_ID)
				.eq('user_id', USER_C_PRO.id)
				.single();
			expect(data?.status).toBe('rejected');
		} finally {
			await ctx.close();
			// afterEach sweeps the row.
		}
	});
});
