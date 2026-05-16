import { expect, test } from '@playwright/test';

import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser
} from '../../fixtures/saga-users';

/**
 * Club join saga — first multi-user saga, validates the saga-users
 * fixture pattern for future deeper sagas.
 *
 * Flow:
 *   1. Mint 3 ephemeral users (alice, bob, carl).
 *   2. ALICE creates a public, open-join club via /clubs/new.
 *   3. BOB and CARL each visit /clubs/<slug> and click "Join club".
 *   4. ALICE switches to the Members tab, sees all three names.
 *   5. ALICE deletes the club via the owner-only Delete button.
 *
 * Cleanup runs in a finally so a failed assertion doesn't leak the
 * users — `deleteSagaUsers` wipes any owned rows (clubs, events,
 * runs, posts) before deleting the auth.users rows.
 *
 * Pattern lessons for future sagas:
 *   - Always create users in `beforeAll`, delete in `afterAll`.
 *     Per-test creation (in `beforeEach`) is too slow.
 *   - One `test()` per saga journey. The saga IS the assertion;
 *     splitting it into many tests would re-run setup repeatedly
 *     AND leak shared state between them.
 *   - Use distinct browser contexts per user. Same browser process,
 *     different contexts (separate cookies + localStorage), so the
 *     test acts as N users running in parallel-or-serial as needed.
 */

const uniqueSuffix = () =>
	`${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('saga: club create → 2 users join → owner sees members → delete', () => {
	// Sagas drive multiple browser contexts in sequence; the default
	// 30 s test timeout is tight. 90 s gives headroom for the auth-
	// race polling on each user's first navigation + the realtime
	// member-count subscription on /clubs/<slug>.
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];

	test.beforeAll(async () => {
		users = await createSagaUsers(3, {
			displayNames: ['Saga Alice', 'Saga Bob', 'Saga Carl']
		});
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('alice creates club, bob + carl join via UI, members tab shows all three, alice deletes', async ({
		browser
	}) => {
		const [alice, bob, carl] = users;
		const clubName = `Saga Club ${uniqueSuffix()}`;

		// One context per user — separate cookies + localStorage so
		// each acts as a fully isolated browser session.
		const aliceCtx = await browser.newContext({
			storageState: alice.storageStatePath
		});
		const bobCtx = await browser.newContext({
			storageState: bob.storageStatePath
		});
		const carlCtx = await browser.newContext({
			storageState: carl.storageStatePath
		});
		const alicePage = await aliceCtx.newPage();
		const bobPage = await bobCtx.newPage();
		const carlPage = await carlCtx.newPage();

		try {
			// ── 1. ALICE creates a public, open-join club ──
			// Note: avoid `waitForLoadState('networkidle')` here and
			// throughout. /clubs/[slug] subscribes to a Supabase
			// realtime channel for member-count updates which keeps a
			// websocket open — networkidle never fires. Wait for the
			// concrete element we need to interact with instead.
			await alicePage.goto('/clubs/new');
			const nameInput = alicePage.locator('input[type="text"]').first();
			await expect(nameInput).toBeVisible({ timeout: 10_000 });
			await nameInput.fill(clubName);
			// Visibility = public (default) + join policy = open (default).
			await alicePage.getByRole('button', { name: 'Create club' }).click();
			// On success the page navigates to /clubs/<slug>. The slug
			// is `slugify(name)` which keeps lowercase letters + digits
			// + hyphens. We must NOT match `/clubs/new` (where alice
			// already is) — Playwright's waitForURL fires the instant
			// the regex matches, and a permissive `[a-z0-9-]+$` would
			// satisfy on /clubs/new before the navigation completes.
			// Require a digit in the slug so it can only match the
			// stamped saga slug, never the literal `new`.
			await alicePage.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, {
				timeout: 10_000
			});
			const slug = alicePage.url().match(/\/clubs\/([a-z0-9-]+)$/)![1];
			expect(slug).toBeTruthy();
			expect(slug).not.toBe('new');

			// Sanity: alice is the owner so she sees Delete club, not Join.
			await expect(
				alicePage.getByRole('button', { name: /Delete club/ })
			).toBeVisible({ timeout: 10_000 });

			// ── 2. BOB visits the club + joins ──
			await bobPage.goto(`/clubs/${slug}`);
			const bobJoinBtn = bobPage.getByRole('button', { name: /Join club/ });
			await expect(bobJoinBtn).toBeVisible({ timeout: 10_000 });
			await bobJoinBtn.click();
			// Successful join flips the button to "Leave".
			await expect(
				bobPage.getByRole('button', { name: /Leave/ })
			).toBeVisible({ timeout: 10_000 });

			// ── 3. CARL same flow ──
			await carlPage.goto(`/clubs/${slug}`);
			const carlJoinBtn = carlPage.getByRole('button', { name: /Join club/ });
			await expect(carlJoinBtn).toBeVisible({ timeout: 10_000 });
			await carlJoinBtn.click();
			await expect(
				carlPage.getByRole('button', { name: /Leave/ })
			).toBeVisible({ timeout: 10_000 });

			// ── 4. ALICE checks the Members tab ──
			// Reload so the realtime member-count + Members tab list
			// reflect bob + carl's joins.
			await alicePage.reload();
			await expect(
				alicePage.getByRole('button', { name: /Delete club/ })
			).toBeVisible({ timeout: 10_000 });
			await alicePage.getByRole('tab', { name: /^Members/ }).click();

			const memberList = alicePage.locator('.member-list');
			await expect(memberList).toBeVisible({ timeout: 10_000 });
			// All three display_names should appear in the list.
			await expect(memberList).toContainText('Saga Alice');
			await expect(memberList).toContainText('Saga Bob');
			await expect(memberList).toContainText('Saga Carl');
			await expect(memberList.locator('.member')).toHaveCount(3);

			// ── 5. ALICE deletes the club ──
			// Stay on the members tab — Delete button is in the hero
			// header, always visible to the owner.
			await alicePage.getByRole('button', { name: /Delete club/ }).click();
			// ConfirmDialog opens; the modal's confirm button reads "Delete".
			await alicePage
				.getByRole('button', { name: 'Delete', exact: true })
				.last()
				.click();
			// On success the page navigates back to /clubs.
			await alicePage.waitForURL(/\/clubs(\?.*)?$/, { timeout: 10_000 });
		} finally {
			await aliceCtx.close();
			await bobCtx.close();
			await carlCtx.close();
		}
	});
});
