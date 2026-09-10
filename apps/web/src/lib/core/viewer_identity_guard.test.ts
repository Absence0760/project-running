// The viewer a privacy clip is decided against comes from the SESSION, not
// from the reactive auth store.
//
// `auth.ready()` is a bounded gate: when the initial session check is wedged
// it resolves a waiter on its timeout rather than hanging the page
// (`stores/auth_ready.ts`), so a mount-time fetch that awaits it can still run
// with `auth.user` null. supabase-js has the persisted token by then anyway,
// so PostgREST answers as the owner — and `fetchRouteById` then compared the
// owner's `user_id` against null, took the non-owner branch, and handed the
// owner their own route with `geom` / `start_point` nulled and the waypoints
// server-clipped. `isOwner` flipped true as soon as the store landed, so the
// owner-only affordances rendered over stripped geometry and nothing
// re-fetched (§ 1562).
//
// `getSession()` awaits the client's own initialisation and reads the same
// persisted session the request carried, so the two cannot disagree. This
// guard exists because the function calls the `supabase` singleton directly
// and cannot be run without a live stack — the same reason `data.test.ts`
// states its invariants as source rules.
//
// Invocation: npx tsx --test src/lib/core/viewer_identity_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments';

/// Reads whose answer differs by WHO is asking, and whose caller mounts before
/// auth has necessarily settled.
const VIEWER_SCOPED_READS = ['fetchRouteById'];

function bodyOf(src: string, name: string): string {
	const start = src.indexOf(`export async function ${name}(`);
	assert.ok(start >= 0, `Could not locate ${name} in core/data.ts — renamed?`);
	const next = src.indexOf('\nexport ', start + 1);
	return src.slice(start, next > start ? next : undefined);
}

test('a viewer-scoped read resolves its viewer from the session, not the store', () => {
	const src = stripComments(
		readFileSync(resolve(import.meta.dirname, 'data.ts'), 'utf-8'),
	);
	for (const name of VIEWER_SCOPED_READS) {
		const body = bodyOf(src, name);
		assert.ok(
			/currentViewerId\(|auth\.getSession\(/.test(body),
			`${name} must resolve its viewer from the session — currentViewerId() or ` +
				'supabase.auth.getSession(). Reading the store instead clips the owner ' +
				'out of their own row whenever auth.ready() falls through on its timeout.',
		);
		assert.ok(
			!/\bauth\.user\b/.test(body),
			`${name} reads auth.user. The reactive store can still be null after ` +
				'auth.ready() resolves on its timeout, while supabase-js already has the ' +
				'persisted token — so PostgREST answers as the owner and this function ' +
				'decides they are not one.',
		);
	}
});

test('currentViewerId prefers the session and falls back only on a throw', () => {
	const src = stripComments(
		readFileSync(resolve(import.meta.dirname, 'data.ts'), 'utf-8'),
	);
	const start = src.indexOf('async function currentViewerId(');
	assert.ok(start >= 0, 'currentViewerId is gone — the guard above has nothing to point at.');
	const body = src.slice(start, src.indexOf('\n}', start));
	// The store read has to sit inside the catch: as the primary it is the
	// bug, and as an `??` coalesce off a null session it would answer for an
	// anon viewer, who has no id to compare and must take the clipped branch.
	const store = body.indexOf('auth.user');
	const rescue = body.indexOf('} catch');
	assert.ok(store > rescue && rescue >= 0, 'auth.user must be read only in the catch.');
});
