import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { test } from 'node:test';

/**
 * Guard: an e2e spec that drives the UI sign-out helper while bound to a
 * SHARED seeded-user session must re-mint that session before it ends.
 *
 * The Playwright suite signs each seeded user (USER_A/B/C) in once during
 * globalSetup and persists the session to `.auth/<user>.json`; every spec
 * reuses it via `test.use({ storageState: <user>.storageStatePath })`.
 * The app's UI sign-out calls `supabase.auth.signOut({ scope: 'local' })`,
 * which revokes that very refresh token SERVER-SIDE. So a spec that signs a
 * shared user out without re-minting the storage state leaves every later
 * USER_A/B/C spec in the same shard loading a revoked session — they bounce
 * to /login and fail far from the real cause.
 *
 * This bit run 27567813578: settings-cache.spec.ts's "sign-out drops the
 * cached prefs" test revoked the shared user-a.json session, and week-strip
 * .spec.ts (the next USER_A spec sharded after it) saw the sign-in page
 * instead of the dashboard. The remedy — `refreshStorageState(...)` in a
 * `finally`, as auth/reset.spec.ts already does for password rotation — is
 * what this guard makes mandatory, converting a shard-order-dependent flake
 * into a deterministic unit failure.
 *
 * The clean alternative the guard also accepts: a spec whose sign-out test
 * runs against an EPHEMERAL session (`storageState: { cookies: [], origins:
 * [] }`) and signs in fresh, so the sign-out only touches a throwaway
 * session it minted itself — never the shared file. cross-cutting/
 * sign-in-out.spec.ts is the canonical example.
 */

const E2E_ROOT = resolve(import.meta.dirname, '..', '..', 'tests-e2e');

function specFiles(): string[] {
	return readdirSync(E2E_ROOT, { recursive: true, withFileTypes: true })
		.filter((e) => e.isFile() && e.name.endsWith('.spec.ts'))
		.map((e) => resolve((e as unknown as { parentPath: string }).parentPath, e.name));
}

test('every spec that UI-signs-out a shared seeded session re-mints its storage state', () => {
	const offenders: string[] = [];

	for (const file of specFiles()) {
		const src = readFileSync(file, 'utf-8');

		// Only the UI sign-out helper revokes the persisted session. A bare
		// mention in a comment/import without an actual call is harmless, so
		// key on the call form `signOut(`.
		if (!/\bsignOut\s*\(/.test(src)) continue;

		// Bound to a shared, file-persisted seeded session?
		const usesSharedSession = /\.storageStatePath\b/.test(src);
		if (!usesSharedSession) continue; // ephemeral-session specs are safe

		// Re-mints the shared session before handing the file back?
		if (/\brefreshStorageState\s*\(/.test(src)) continue;

		offenders.push(file.slice(file.indexOf('tests-e2e/')));
	}

	assert.deepEqual(
		offenders,
		[],
		`These e2e specs sign a shared seeded user out via the UI without re-minting the ` +
			`persisted session, so a USER_A/B/C spec sharded after them will bounce to /login:\n  ` +
			offenders.join('\n  ') +
			`\nAdd refreshStorageState(browser, baseURL, USER_X) in a finally (see ` +
			`auth/reset.spec.ts), or run the sign-out test against an ephemeral storageState ` +
			`(see cross-cutting/sign-in-out.spec.ts).`,
	);
});
