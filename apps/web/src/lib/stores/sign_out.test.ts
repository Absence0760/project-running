import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { signOutWithScope, type AuthSignOutClient, type SignOutScope } from './sign_out';

function mockAuth(error: { message?: string } | null = null): {
	client: AuthSignOutClient;
	calls: SignOutScope[];
} {
	const calls: SignOutScope[] = [];
	return {
		calls,
		client: {
			async signOut({ scope }) {
				calls.push(scope);
				return { error };
			},
		},
	};
}

test('signOutWithScope forwards the local scope to the auth client', async () => {
	const { client, calls } = mockAuth();
	const err = await signOutWithScope(client, 'local');
	assert.equal(err, null);
	assert.deepEqual(calls, ['local']);
});

test('signOutWithScope forwards the global scope to the auth client', async () => {
	const { client, calls } = mockAuth();
	const err = await signOutWithScope(client, 'global');
	assert.equal(err, null);
	assert.deepEqual(calls, ['global']);
});

test('signOutWithScope returns the provider error rather than throwing', async () => {
	const { client } = mockAuth({ message: 'network down' });
	const err = await signOutWithScope(client, 'global');
	assert.equal(err?.message, 'network down');
});

// Source-level guard for the store wiring — auth.svelte.ts uses Svelte $state
// runes (and imports the runes-laden units signal), so it can't execute under
// raw tsx. These assertions pin that the two affordances stay distinct: the
// sidebar's local Sign out passes 'local', and logoutEverywhere() passes
// 'global' AND fails closed (throws) on a revocation error instead of clearing
// the local session and implying success.
const here = dirname(fileURLToPath(import.meta.url));
const store = readFileSync(resolve(here, './auth.svelte.ts'), 'utf8');

test('logout() routes through the local scope', () => {
	const body = store.slice(store.indexOf('async function logout('), store.indexOf('async function logoutEverywhere('));
	assert.match(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'local'\s*\)/);
	assert.doesNotMatch(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'global'\s*\)/);
});

test('logoutEverywhere() routes through the global scope and fails closed', () => {
	const start = store.indexOf('async function logoutEverywhere(');
	assert.ok(start > 0, 'logoutEverywhere must exist on the store');
	const body = store.slice(start, store.indexOf('// Listen for auth state changes'));
	assert.match(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'global'\s*\)/);
	// The error branch must throw BEFORE the local teardown (user = null),
	// so a failed global revocation can't masquerade as a successful sign-out.
	const throwIdx = body.indexOf('throw');
	const teardownIdx = body.indexOf('user = null');
	assert.ok(throwIdx > 0 && teardownIdx > 0 && throwIdx < teardownIdx,
		'logoutEverywhere must throw on error before clearing local session');
});

test('the store exposes logoutEverywhere alongside logout', () => {
	assert.match(store, /\blogoutEverywhere\b\s*,/);
});
