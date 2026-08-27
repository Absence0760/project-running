/// Run with `cd apps/backend && deno test --allow-read supabase/functions/strava-import/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// handler needs a live Supabase + a real Strava grant to exercise, so what
/// is checked here is the SHAPE the validation has to keep: the value each
/// handler runs on is the value that was validated, not a second read of the
/// untyped request bag.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the sync handler runs on the validated lookback, not a re-read of the body', () => {
	// The bound check and the call site used to read `body.lookbackDays`
	// independently — the check tested it, then `handleSync(..., body
	// .lookbackDays ?? 90)` went back to the bag for it. Nothing tied the two,
	// and only `Number.isInteger` stood between a JSON `null` and the epoch
	// arithmetic: reorder that `||` chain so a bound came first and `null`
	// reached `backfill`, where `null * 86400_000` is 0 and the sync silently
	// looks back to this instant and imports nothing.
	assert(
		/return handleSync\(supabase, user\.id, lookbackDays\);/.test(SRC),
		'handleSync must be handed the validated `lookbackDays` local, not an expression ' +
			'that reads `body.lookbackDays` a second time',
	);
	assert(
		!/handleSync\([^)]*body\.lookbackDays/.test(SRC),
		'handleSync must not read `body.lookbackDays` — the bag is untyped and unvalidated ' +
			'at that point',
	);
	assert(
		/typeof requested !== 'number'/.test(SRC),
		"the lookback validation must narrow with an explicit `typeof ... !== 'number'` " +
			'test; leaning on `Number.isInteger` alone to reject a JSON `null` makes the ' +
			'refusal an accident of clause order',
	);
});

Deno.test('the connect handler runs on the validated strings, not a re-read of the body', () => {
	// Same shape, same reason: `body.code` / `body.scope` / `body.redirect_uri`
	// were type-checked in one block and read again at the call site in
	// another, so the values passed on were never the narrowed ones.
	assert(
		/return handleConnect\(supabase, user\.id, code, scope, redirectUri\);/.test(SRC),
		'handleConnect must be handed the validated locals',
	);
	assert(
		!/handleConnect\([^)]*body\./.test(SRC),
		'handleConnect must not read the request bag directly',
	);
});
