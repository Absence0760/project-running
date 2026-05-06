import { resolve } from 'node:path';

/**
 * Seeded users referenced by Playwright specs.
 *
 * UUIDs are pinned in `apps/backend/supabase/seed.sql` so the test
 * files can reference them by literal — no `select id from auth.users
 * where email = ?` lookups in tests, which would create a hidden
 * dependency on the seed running before the test fixture.
 *
 * If you change a UUID here you must change it in seed.sql too — and
 * vice-versa. The Playwright specs grep these constants so a typo
 * fails loudly at the assertion site, not silently as "no rows".
 */

export type SeededUser = {
	email: string;
	password: string;
	id: string; // auth.users.id
	tier: 'free' | 'pro' | 'lifetime';
	/// Absolute path; populated by globalSetup, then read by spec
	/// files via test.use({ storageState }). Absolute so the path
	/// resolves identically regardless of Playwright's cwd.
	storageStatePath: string;
};

// .auth/ lives next to playwright.config.ts (one level up from this
// fixtures/ directory). Resolve once at module-load.
const STORAGE_DIR = resolve(import.meta.dirname, '..', '.auth');

// All three users + their UUIDs are pre-existing in seed.sql — User B
// is alex@test.com (joined club fixtures, two-way follow with runner),
// User C is morgan@test.com (mutual follow with runner). The e2e seed
// extension ensures alex has both a public and a private run, upgrades
// morgan's tier to pro, and configures a privacy zone on runner. Keep
// these literals in lockstep with seed.sql.
export const USER_A: SeededUser = {
	email: 'runner@test.com',
	password: 'testtest',
	id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
	tier: 'free',
	storageStatePath: resolve(STORAGE_DIR, 'user-a.json')
};

export const USER_B: SeededUser = {
	email: 'alex@test.com',
	password: 'testtest',
	id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012',
	tier: 'free',
	storageStatePath: resolve(STORAGE_DIR, 'user-b.json')
};

export const USER_C_PRO: SeededUser = {
	email: 'morgan@test.com',
	password: 'testtest',
	id: 'c3d4e5f6-a7b8-9012-cdef-345678901234',
	tier: 'pro',
	storageStatePath: resolve(STORAGE_DIR, 'user-c-pro.json')
};

export const ALL_USERS: SeededUser[] = [USER_A, USER_B, USER_C_PRO];
