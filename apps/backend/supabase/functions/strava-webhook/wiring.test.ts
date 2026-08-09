/// Run with `cd apps/backend && deno test --allow-read supabase/functions/strava-webhook/wiring.test.ts`.
///
/// Source-grep guards in the `delete-account/wiring.test.ts` idiom. The
/// handler needs a live Supabase + a real Strava token to exercise, but
/// both properties below are positional and readable off the source.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { WEBHOOK_SECRET_HEADER } from '../_shared/webhook_security.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

/// The region before the request body is consumed. Everything that
/// returns from here has to cancel the body on the way out.
function preBodyRegion(): string {
	const helperStart = SRC.indexOf('const refuseUnread =');
	assert(helperStart !== -1, 'the refuseUnread helper is gone — has the drain been removed?');
	const helperEnd = SRC.indexOf('};', helperStart) + 2;
	const bodyRead = SRC.indexOf('readJsonWithLimit<');
	assert(bodyRead !== -1, 'could not find the readJsonWithLimit call — has the POST branch moved?');
	assert(helperEnd < bodyRead, 'the refuseUnread helper must be declared before the body read');
	return SRC.slice(helperEnd, bodyRead);
}

Deno.test('every pre-body exit cancels the request body', () => {
	// Deno keeps the connection open for an unread request stream. A
	// caller that POST-streams a chunked body into one of the refusal
	// branches (503 unconfigured, 429 throttled, 403 wrong secret, 405
	// wrong method) held a slot until the runtime timeout — a slow-loris
	// against the one function reachable by URL alone, with no JWT.
	//
	// The fix is structural: every exit before `readJsonWithLimit` goes
	// through `refuseUnread`, which drains first. This guard is what
	// makes that structural rather than a convention — a new early
	// return that forgets it fails here.
	const region = preBodyRegion();
	const returns = [...region.matchAll(/return\s+/g)];
	assert(
		returns.length >= 6,
		`expected at least 6 pre-body returns (503 x2, 429, 403 x2, 405), found ${returns.length}. ` +
			'Has a refusal branch been dropped?',
	);
	const bare: string[] = [];
	for (const m of returns) {
		const at = m.index! + m[0].length;
		if (!region.slice(at).startsWith('refuseUnread(')) {
			bare.push(region.slice(Math.max(0, m.index! - 60), at + 60).trim());
		}
	}
	assert(
		bare.length === 0,
		'every return before the body is read must go through refuseUnread(...) so the ' +
			`request body is cancelled.\nBare returns:\n${bare.join('\n---\n')}`,
	);
});

Deno.test('the shared secret is accepted from a header, preferred over the query string', () => {
	// A `?secret=` in the callback URL is written verbatim into
	// Supabase's function request logs on every delivery, so anyone with
	// log read access recovers it and can forge activity ingests. Strava
	// only lets you register a URL, so the query path has to keep
	// working until the registration is changed and the secret rotated
	// (a pre-deploy ops item) — but the header path exists now, and any
	// non-Strava caller of this endpoint should use it.
	const header = SRC.indexOf(`req.headers.get(WEBHOOK_SECRET_HEADER)`);
	const query = SRC.indexOf(`url.searchParams.get('secret')`);
	assert(header !== -1, `handler must read the secret from ${WEBHOOK_SECRET_HEADER}`);
	assert(query !== -1, 'the ?secret= path must keep working until Strava is re-registered');
	assert(
		header < query,
		'the header must be consulted BEFORE the query param — and via `??`, so a caller ' +
			'that supplies a wrong header gets one judgement, not a second try at the query',
	);
	assert(
		SRC.includes('const suppliedSecret = headerSecret ?? '),
		'the two sources must collapse to ONE value before the compare, so both paths ' +
			'go through the same constant-time check',
	);
});

Deno.test('both secret paths are compared in constant time', () => {
	// One compare, on the merged value, using timingSafeEqual. A plain
	// `!==` on either path reopens the byte-by-byte latency channel that
	// the rate limit only slows down.
	assert(
		SRC.includes('timingSafeEqual(suppliedSecret, webhookSecret)'),
		'the merged secret must be compared with timingSafeEqual',
	);
	assert(
		!/suppliedSecret\s*[!=]==/.test(SRC),
		'the supplied secret must never be compared with === / !== — use timingSafeEqual',
	);
});
