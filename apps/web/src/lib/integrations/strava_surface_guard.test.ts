// What the Strava OAuth + sync call sites are allowed to do with a
// response, and what the surface above them must say about it.
// Invocation:
//   npx tsx --test src/lib/integrations/strava_surface_guard.test.ts
//
// `strava.ts` imports `$env/dynamic/public` and supabase-js, so it cannot
// be executed under `tsx --test`; the grading it delegates to is pinned in
// `strava_sync_result.test.ts`. What no test could see is the thing that
// was actually wrong before decisions § 766: both call sites CAST the
// function's body (`data as StravaSyncResult`), so every response —
// throttled, truncated by an upstream error, stopped at the 20-page cap —
// rendered as a finished import. A cast compiles, so reverting to one is
// silent everywhere except here.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
	STRAVA_LOOKBACK_DEFAULT_DAYS,
	STRAVA_LOOKBACK_MAX_DAYS,
	STRAVA_LOOKBACK_OPTIONS,
} from './strava_sync_result';

const CLIENT = 'src/lib/integrations/strava.ts';
const PAGE = 'src/routes/settings/integrations/+page.svelte';

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

test('every strava-import response is graded, never cast', () => {
	const source = read(CLIENT);
	const invocations = [...source.matchAll(/functions\.invoke\('strava-import'/g)];
	assert.equal(invocations.length, 2, 'expected the connect + sync call sites');
	assert.equal(
		[...source.matchAll(/parseStravaSyncResult\(/g)].length,
		2,
		'both call sites must grade their body through parseStravaSyncResult',
	);
	assert.doesNotMatch(
		source,
		/as\s+StravaSyncResult/,
		'a cast lets a body that says nothing about `complete` render as a finished import',
	);
});

test("the sync default is the shared constant, not a second literal of it", () => {
	// The lookback bound is one contract across three rails (the two
	// clients and the Edge Function's own 400 `invalid_lookback_days`).
	// A hand-written default here is a fourth declaration that no guard
	// compares.
	const source = read(CLIENT);
	assert.match(
		source,
		/lookbackDays\s*=\s*STRAVA_LOOKBACK_DEFAULT_DAYS/,
		'syncStrava must default to STRAVA_LOOKBACK_DEFAULT_DAYS',
	);
	assert.equal(STRAVA_LOOKBACK_DEFAULT_DAYS, STRAVA_LOOKBACK_OPTIONS[0]);
	assert.ok(
		STRAVA_LOOKBACK_OPTIONS.every((d) => d <= STRAVA_LOOKBACK_MAX_DAYS),
		'no offered window may exceed the bound the function refuses above',
	);
});

test('the OAuth callback refuses before it spends the code', () => {
	// RFC 6749 § 10.12. The state has to be consumed and compared BEFORE
	// the code reaches the Edge Function — a check after the exchange has
	// already linked the victim's session to the attacker's Strava account.
	const source = read(CLIENT);
	const body = source.slice(
		source.indexOf('export async function completeStravaOAuth'),
		source.indexOf('export async function syncStrava'),
	);
	assert.ok(body.length > 0, 'completeStravaOAuth not found — did it move?');

	const consumed = body.indexOf('consumeStravaOAuthState()');
	const refused = body.search(/if\s*\(!expected\s*\|\|\s*expected\s*!==\s*state\)/);
	const exchanged = body.indexOf("functions.invoke('strava-import'");
	assert.notEqual(consumed, -1, 'the stashed state must be consumed');
	assert.notEqual(refused, -1, 'a missing or mismatched state must be refused');
	assert.notEqual(exchanged, -1, 'the exchange must still happen');
	assert.ok(consumed < refused, 'the state must be read before it is compared');
	assert.ok(refused < exchanged, 'the refusal must precede the code exchange');
	assert.match(
		body.slice(refused, exchanged),
		/throw new Error/,
		'a mismatch must throw rather than fall through',
	);
});

test('both Strava import paths record a truncation, not just the sync one', () => {
	// A truncated import is a state of the connection, not a moment: the
	// toast is dismissed and the missed activities stay reachable only
	// until they age past the lookback window. The first-connect backfill
	// is the sync MOST likely to come up short — it is the only one that
	// walks the whole window — and it used to leave the card silent.
	const page = read(PAGE);
	const script = page.slice(0, page.indexOf('</script>'));
	const graded = [...script.matchAll(/stravaPartial = result\.complete \? null : \{/g)];
	assert.equal(
		graded.length,
		2,
		'the connect handler and the sync handler must each record the truncation',
	);
	for (const fn of ['completeStravaOAuth(', 'syncStrava(']) {
		const at = script.indexOf(fn);
		assert.notEqual(at, -1, `${fn} call site not found`);
		const after = script.slice(at, at + 1200);
		assert.match(
			after,
			/result\.complete/,
			`${fn} must branch on the graded completeness`,
		);
		assert.match(
			after,
			/stravaPartial =/,
			`${fn} must record the truncation past the toast`,
		);
	}
});
