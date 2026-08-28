/// Run with `cd apps/backend && deno test --allow-read supabase/functions/strava-import/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// handler needs a live Supabase + a real Strava grant to exercise, so what
/// is checked here is the SHAPE the validation has to keep: the value each
/// handler runs on is the value that was validated, not a second read of the
/// untyped request bag.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const WALK = await Deno.readTextFile(new URL('./backfill.ts', import.meta.url));

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

Deno.test('the connect code is validated where it is read, not inside the handler', () => {
	// `handleConnect` carried an `if (!code) return missing_code` that could
	// never fire: the top level rejects a non-string or an empty `code` before
	// the handler is called at all. Deleting the branch is only safe while the
	// check it duplicated is still there, so pin that instead.
	assert(
		/typeof body\.code !== 'string' \|\| body\.code\.length === 0/.test(SRC),
		'the top level must reject a non-string or empty `code` — `handleConnect` no ' +
			'longer re-checks it',
	);
	assert(
		!/missing_code/.test(SRC),
		'`handleConnect` must not re-check `code`: the branch is unreachable and reads ' +
			'as though the validation above it were optional',
	);
});

Deno.test('only an end-of-window exit may report the backfill as complete', () => {
	// The page loop has seven exits and five of them leave activities in the
	// lookback window unfetched: Strava throttling us (429/503), an upstream
	// error, a transport failure, a malformed page body, and the 20-page safety
	// cap. Only the throttle case ever carried a field, so the others reported
	// a truncated import as a finished one. `complete` is the field that says
	// otherwise, and it may only be raised on the two exits that reached the
	// end of the window — an empty page and a short page.
	const raises = WALK.match(/complete = true;/g) ?? [];
	assert(
		raises.length === 2,
		`exactly two exits may set \`complete = true\` (an empty page and a short ` +
			`page); found ${raises.length}. A new \`complete = true\` on an error or ` +
			`cap path re-opens the bug: a truncated import reported as a finished one.`,
	);
	assert(
		/resumable: !complete && \(nextCursor !== null \|\| resumedFrom !== null\),/.test(WALK),
		'`backfill` must return `resumable` alongside `complete` — a client cannot ' +
			'fail closed on a field the function never sends',
	);
});

Deno.test('a transport failure is a truncation, not an escape', () => {
	// `fetch` rejects on DNS / TLS / a dropped connection and `resp.json()` on
	// an HTML error page from anything in front of Strava. Both used to
	// propagate past `handleSync` into `withSentry`, which answers 500
	// `internal_error` — the one truncation shape `complete` could not describe,
	// because it never reached the return.
	assert(
		/try \{\s*\n\s*const resp = await fetch\(url,/.test(WALK),
		'the page fetch + its JSON parse must sit inside a try/catch, or a transport ' +
			'failure discards every count the walk had earned',
	);
	assert(
		/\} catch \(err\) \{\s*\n\s*console\.warn\('strava backfill transport error'/.test(WALK),
		'the transport catch must break the walk rather than rethrow',
	);
});

Deno.test('last_sync_at is stamped, and the resume point cleared, only on a finished window', () => {
	// Both integration tiles render `last_sync_at` as "Last synced <ago>".
	// Stamping it after a truncated backfill is a second, independent claim
	// that the import finished — and it survives the toast the runner
	// dismissed. The resume cursor is the mirror of the same rule: a finished
	// window subsumes any point inside it, and a cursor left behind would
	// narrow every later sync to a window that is already done.
	assert(
		/if \(complete\) \{\s*\n\s*patch\.last_sync_at = new Date\(\)\.toISOString\(\);/.test(WALK),
		'the `last_sync_at` stamp must sit inside an `if (complete)` guard',
	);
	assert(
		/if \(complete\) \{[^}]*patch\.sync_cursor = null;/s.test(WALK),
		'a finished window must clear `sync_cursor`',
	);
	assert(
		/\} else if \(nextCursor\) \{\s*\n\s*patch\.sync_cursor = serialiseSyncCursor\(nextCursor\);/
			.test(WALK),
		'a resume point may only be written on a truncated walk',
	);
});

Deno.test('the dev allow-list carries the callback the mobile clients send', async () => {
	// The mobile connect flow posts `kStravaCallbackUri`, and the comparison in
	// `_shared/redirect_allowlist.ts` is whole-string. A list carrying only the
	// web callback answers an in-app connect with 400 `invalid_redirect_uri`
	// whatever the developer registered with Strava — and `.env.example` is
	// what an operator copies to configure production.
	const dart = await Deno.readTextFile(
		new URL('../../../../mobile_android/lib/strava.dart', import.meta.url),
	);
	const scheme = dart.match(/kStravaCallbackScheme = '([^']+)'/)?.[1];
	assert(scheme, 'mobile_android/lib/strava.dart no longer declares kStravaCallbackScheme');
	const expected = `${scheme}://strava-callback`;
	assert(
		dart.includes(`kStravaCallbackUri = '$kStravaCallbackScheme://strava-callback'`),
		'kStravaCallbackUri is no longer the scheme plus /strava-callback — this guard ' +
			'reconstructs it and would now be pinning the wrong URI',
	);
	for (const envFile of ['.env.development', '.env.example']) {
		const src = await Deno.readTextFile(new URL(`../../../${envFile}`, import.meta.url));
		const line = src.match(/^STRAVA_ALLOWED_REDIRECTS=(.*)$/m)?.[1] ?? '';
		assert(
			line.split(',').map((v) => v.trim()).includes(expected),
			`${envFile}'s STRAVA_ALLOWED_REDIRECTS must contain ${expected}. Found: ${line}`,
		);
	}
});
