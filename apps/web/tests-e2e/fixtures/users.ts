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
	storageStatePath: string; // gets populated by globalSetup
};

const STORAGE_DIR = '.auth';

export const USER_A: SeededUser = {
	email: 'runner@test.com',
	password: 'testtest',
	id: '11111111-1111-1111-1111-111111111111',
	tier: 'free',
	storageStatePath: `${STORAGE_DIR}/user-a.json`
};

export const USER_B: SeededUser = {
	email: 'friend@test.com',
	password: 'testtest',
	id: '22222222-2222-2222-2222-222222222222',
	tier: 'free',
	storageStatePath: `${STORAGE_DIR}/user-b.json`
};

export const USER_C_PRO: SeededUser = {
	email: 'pro@test.com',
	password: 'testtest',
	id: '33333333-3333-3333-3333-333333333333',
	tier: 'pro',
	storageStatePath: `${STORAGE_DIR}/user-c-pro.json`
};

export const ALL_USERS: SeededUser[] = [USER_A, USER_B, USER_C_PRO];
