import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/join/[token] — branch coverage for the polished invite
 * landing page.
 *
 * The page has three render branches that the existing specs only
 * touch obliquely:
 *   - 'joining' (spinner) → redirected to /clubs/<slug> on success
 *   - 'not-authed' → sign-in + create-account CTAs with return_to
 *   - 'error' → "Invite problem" with Browse clubs + Go to dashboard
 *
 * Richmond Run Club has `join_policy = 'open'` and a null invite_token
 * in the seed. We plant a token on it for the duration of each test
 * that needs one and clear it on teardown, so the seed shape is
 * restored for downstream specs (notably clubs/join.spec.ts which
 * relies on the open-policy Join button still mattering).
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const SYDNEY_INVITE_TOKEN = 'syd5n3yrun5clubtest3njoin000000';
const BAD_TOKEN = 'no-such-token-xxx';

async function plantSeedToken(): Promise<void> {
	await getAdminClient()
		.from('clubs')
		.update({ invite_token: SYDNEY_INVITE_TOKEN })
		.eq('id', SYDNEY_RUN_CLUB_ID);
}

async function clearSeedToken(): Promise<void> {
	try {
		await getAdminClient()
			.from('clubs')
			.update({ invite_token: null })
			.eq('id', SYDNEY_RUN_CLUB_ID);
	} catch (_) {
		/* best-effort */
	}
}

async function removeMembership(userId: string): Promise<void> {
	try {
		await getAdminClient()
			.from('club_members')
			.delete()
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('user_id', userId);
	} catch (_) {
		/* best-effort */
	}
}

test.describe('/clubs/join/[token] — signed-out branch', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async () => {
		await plantSeedToken();
	});

	test.afterEach(async () => {
		await clearSeedToken();
	});

	test('anon visitor sees the sign-in kicker + both CTAs with return_to back to the invite URL', async ({
		page
	}) => {
		const invitePath = `/clubs/join/${SYDNEY_INVITE_TOKEN}`;
		await page.goto(invitePath);

		await expect(
			page.getByRole('heading', { level: 1, name: 'Sign in to accept this invite' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kicker', { hasText: "You've been invited" }))
			.toBeVisible();

		const signIn = page.getByRole('link', { name: 'Sign in', exact: true });
		const signUp = page.getByRole('link', { name: 'Create a free account' });
		await expect(signIn).toBeVisible();
		await expect(signUp).toBeVisible();

		const expectedReturn = encodeURIComponent(invitePath);
		await expect(signIn).toHaveAttribute(
			'href',
			`/login?return_to=${expectedReturn}`
		);
		await expect(signUp).toHaveAttribute(
			'href',
			`/login?signup=1&return_to=${expectedReturn}`
		);

		await expect(page.locator('.logo .logo-mark')).toBeVisible();
		await expect(page.locator('.logo span', { hasText: 'Threkir' }))
			.toBeVisible();
	});

	test('clicking Create a free account lands on /login?signup=1&return_to=<invite>', async ({
		page
	}) => {
		const invitePath = `/clubs/join/${SYDNEY_INVITE_TOKEN}`;
		await page.goto(invitePath);

		await page.getByRole('link', { name: 'Create a free account' }).click();
		await page.waitForURL(/\/login\?signup=1&return_to=/, { timeout: 10_000 });

		const url = new URL(page.url());
		expect(url.searchParams.get('signup')).toBe('1');
		expect(url.searchParams.get('return_to')).toBe(invitePath);
	});
});

test.describe('/clubs/join/[token] — error branch (signed-in, bad token)', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('signed-in user with a nonexistent token sees the Invite problem branch + both recovery CTAs', async ({
		page
	}) => {
		await page.goto(`/clubs/join/${BAD_TOKEN}`);

		await expect(
			page.getByRole('heading', { level: 1, name: 'Invite problem' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kicker', { hasText: 'Hmm' })).toBeVisible();
		// The catch block surfaces either the RPC error message
		// ("invalid invite token") or a generic fallback ("This invite is
		// invalid or expired.") depending on whether the client wraps the
		// PostgrestError as an Error instance. Accept both.
		await expect(page.locator('.error')).toContainText(
			/invalid invite token|invalid or expired/i
		);
		await expect(
			page.getByText(/may have been rotated|share a fresh one/i)
		).toBeVisible();

		const browse = page.getByRole('link', { name: 'Browse clubs' });
		const dash = page.getByRole('link', { name: 'Go to dashboard' });
		await expect(browse).toHaveAttribute('href', '/clubs');
		await expect(dash).toHaveAttribute('href', '/dashboard');
	});
});

test.describe('/clubs/join/[token] — already-a-member (owner)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await plantSeedToken();
	});

	test.afterEach(async () => {
		await clearSeedToken();
	});

	test('owner visiting their own clubs valid invite URL is bounced to /clubs/<slug>', async ({
		page
	}) => {
		// `join_club_by_token` is an upsert (`on conflict ... do update set
		// status = 'active'`), so even the owner-already-a-member case
		// resolves to a redirect to the club page. This pins that contract
		// — a regression that started raising on the conflict path would
		// strand the owner on the "Invite problem" branch.
		await page.goto(`/clubs/join/${SYDNEY_INVITE_TOKEN}`);

		await page.waitForURL(/\/clubs\/richmond-run-club$/, { timeout: 15_000 });
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/clubs/join/[token] — successful redemption (cross-user)', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.beforeEach(async () => {
		await plantSeedToken();
		await removeMembership(USER_C_PRO.id);
	});

	test.afterEach(async () => {
		await clearSeedToken();
		await removeMembership(USER_C_PRO.id);
	});

	test('non-member visiting a valid invite URL joins → lands on /clubs/<slug> → name appears in members list', async ({
		page
	}) => {
		await page.goto(`/clubs/join/${SYDNEY_INVITE_TOKEN}`);

		await page.waitForURL(/\/clubs\/richmond-run-club$/, { timeout: 15_000 });
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// DB sanity — the row was inserted, not just the URL redirected.
		const { data: membership } = await getAdminClient()
			.from('club_members')
			.select('role, status')
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('user_id', USER_C_PRO.id)
			.maybeSingle();
		expect(membership).not.toBeNull();
		expect((membership as { status: string }).status).toBe('active');

		await page.getByRole('tab', { name: /^Members/ }).click();
		await expect(
			page.locator('.member-list .member', { hasText: 'Morgan' })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/clubs/join/[token] — already-a-member (existing member upsert)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(async () => {
		await plantSeedToken();
	});

	test.afterEach(async () => {
		await clearSeedToken();
		// Restore alex's seeded membership shape (active member of
		// Richmond Run Club) so downstream specs see the seed.
		try {
			await getAdminClient()
				.from('club_members')
				.upsert(
					{
						club_id: SYDNEY_RUN_CLUB_ID,
						user_id: USER_B.id,
						role: 'member',
						status: 'active'
					},
					{ onConflict: 'club_id,user_id' }
				);
		} catch (_) {
			/* best-effort */
		}
	});

	test('existing active member revisiting the invite URL is redirected to the club page (upsert is a no-op)', async ({
		page
	}) => {
		await page.goto(`/clubs/join/${SYDNEY_INVITE_TOKEN}`);

		await page.waitForURL(/\/clubs\/richmond-run-club$/, { timeout: 15_000 });
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });

		const { count } = await getAdminClient()
			.from('club_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('user_id', USER_B.id);
		expect(count).toBe(1);
	});
});
