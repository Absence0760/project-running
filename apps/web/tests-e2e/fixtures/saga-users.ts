import { mkdir, unlink } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '@playwright/test';

import { getAdminClient } from './local-supabase';

/**
 * Saga-users fixture — mints N ephemeral users for a single test, with
 * matching storage-state files Playwright contexts can load. Use it
 * when the test needs more users than the three pinned in `seed.sql`,
 * or when it should not pollute the seeded `auth.users` rows.
 *
 * Lifecycle:
 *   1. `createSagaUsers(3)` admin-creates auth.users rows + matching
 *      `user_profiles` rows + signs each user in via the form
 *      (parallel, single browser instance) to capture storage state.
 *   2. The test attaches each context via
 *      `browser.newContext({ storageState: user.storageStatePath })`.
 *   3. `deleteSagaUsers(users)` removes the auth.users rows (CASCADE
 *      strips every child row — runs, club_members, kudos, etc.) and
 *      unlinks the storage-state files.
 *
 * Cost: ~1.5-2s setup for 3 users, ~3-4s for 10. Sign-in is the
 * dominant cost (admin createUser is ~50ms each). Don't use this
 * for tests that fit a 1-3 user shape — those run faster against
 * the seeded users.
 *
 * Cleanup is best-effort. If a test crashes between create + delete,
 * the next `supabase db reset` wipes the orphaned users + the .auth/
 * directory cleanup is part of the gitignore tree, so the only cost
 * is a few orphan profiles until the next reset.
 */

export type SagaUser = {
	id: string;
	email: string;
	password: string;
	displayName: string;
	storageStatePath: string;
};

const STORAGE_DIR = resolve(import.meta.dirname, '..', '.auth', 'sagas');
const PASSWORD = 'sagatest123';

export async function createSagaUsers(
	count: number,
	opts?: { displayNames?: string[] }
): Promise<SagaUser[]> {
	if (count < 1) throw new Error('createSagaUsers: count must be >= 1');
	const admin = getAdminClient();
	const stamp = Date.now();
	const rand = Math.random().toString(36).slice(2, 6);
	await mkdir(STORAGE_DIR, { recursive: true });

	// 1) admin-create auth.users rows + user_profiles in parallel.
	const users: SagaUser[] = await Promise.all(
		Array.from({ length: count }, async (_, i) => {
			const email = `saga-${stamp}-${rand}-${i}@test.com`;
			const displayName = opts?.displayNames?.[i] ?? `Saga User ${i + 1}`;

			const { data, error } = await admin.auth.admin.createUser({
				email,
				password: PASSWORD,
				email_confirm: true
			});
			if (error || !data?.user) {
				throw new Error(
					`createSagaUsers: failed to create user #${i} (${email}): ${error?.message ?? 'no user returned'}`
				);
			}
			const id = data.user.id;

			// `user_profiles` is created on first sign-in by auth.svelte.ts's
			// fetchUser fallback, but we want display_name pre-set so saga
			// assertions can match by name (otherwise they'd see the email).
			const { error: profileError } = await admin
				.from('user_profiles')
				.upsert({
					id,
					display_name: displayName,
					preferred_unit: 'km',
					subscription_tier: 'free',
					// Saga users are programmatically minted, not real
					// signups — skip the /onboarding wizard so existing
					// tests that wait for /dashboard or /history aren't
					// redirected away. The wizard's own e2e spec mints
					// a separate saga user with onboarded_at: null to
					// exercise the gate.
					onboarded_at: new Date().toISOString()
				});
			if (profileError) {
				throw new Error(
					`createSagaUsers: failed to upsert profile for #${i} (${email}): ${profileError.message}`
				);
			}

			return {
				id,
				email,
				password: PASSWORD,
				displayName,
				storageStatePath: '' // filled in step 2
			};
		})
	);

	// 2) sign each user in via the form to capture storage state.
	//    Single browser process, parallel contexts. ~1.5s for 3 users.
	const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:7777';
	const browser = await chromium.launch();
	try {
		await Promise.all(
			users.map(async (user, i) => {
				const ctx = await browser.newContext({ baseURL });
				const page = await ctx.newPage();
				try {
					await page.goto('/login');
					await page.waitForLoadState('networkidle');
					await page.locator('input[type="email"]').fill(user.email);
					await page.locator('input[type="password"]').fill(user.password);
					await page.locator('form button[type="submit"]').click();
					// /login redirects to /dashboard on success.
					await page.waitForURL(/\/(dashboard|runs|coach)$/, { timeout: 15_000 });
					const path = resolve(STORAGE_DIR, `saga-${stamp}-${rand}-${i}.json`);
					await ctx.storageState({ path });
					user.storageStatePath = path;
				} finally {
					await ctx.close();
				}
			})
		);
	} finally {
		await browser.close();
	}

	return users;
}

/**
 * Tables whose `<col>` references auth.users *without* `on delete
 * cascade`. Deleting an auth.users row while any of these rows
 * still point at it raises a FK violation (`23503`). Sweep them
 * before the user delete in `deleteSagaUsers`.
 *
 * Cascading FKs (run_kudos, club_members, run_comments, user_follows,
 * notifications, etc.) clean themselves up on the auth.users delete
 * and don't need to be listed here.
 */
const OWNER_TABLES: { table: string; col: string }[] = [
	{ table: 'club_posts', col: 'author_id' },
	{ table: 'events', col: 'created_by' },
	{ table: 'clubs', col: 'owner_id' },
	{ table: 'route_reviews', col: 'user_id' },
	{ table: 'training_plans', col: 'user_id' },
	{ table: 'routes', col: 'user_id' },
	{ table: 'runs', col: 'user_id' }
];

export async function deleteSagaUsers(users: SagaUser[]): Promise<void> {
	const admin = getAdminClient();

	// 1) Wipe any rows in non-cascading owner tables first. Order
	//    matters: club_posts and events both reference clubs, so wipe
	//    them before clubs. The OWNER_TABLES order encodes that.
	for (const user of users) {
		for (const { table, col } of OWNER_TABLES) {
			const { error } = await admin.from(table).delete().eq(col, user.id);
			if (error && error.code !== 'PGRST116') {
				// PGRST116 = "0 rows" not actually an error here. Log
				// anything else but keep going — best-effort cleanup.
				console.warn(
					`deleteSagaUsers: failed to wipe ${table}.${col} for ${user.id}: ${error.message}`
				);
			}
		}
	}

	// 2) Now delete the auth.users rows + storage files in parallel.
	await Promise.all(
		users.map(async (user) => {
			try {
				await admin.auth.admin.deleteUser(user.id);
			} catch (e) {
				console.warn(`deleteSagaUsers: failed to delete ${user.id}:`, e);
			}
			if (user.storageStatePath) {
				try {
					await unlink(user.storageStatePath);
				} catch (_) {
					// File may already be gone (failed before storageState was
					// captured, or a previous cleanup pass took it). Ignore.
				}
			}
		})
	);
}
