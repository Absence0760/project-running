/// Where the throttle sits relative to the compare, on this function and on
/// the sibling it deliberately does not copy.
///
/// `refresh-tokens` and `strava-webhook` are the two `verify_jwt = false`
/// functions in the tree: a bearer compared against a shared secret is the only
/// thing in front of real work, and the URL is the only thing an attacker needs.
/// The webhook limits BEFORE its secret check. This one limits only AFTER a
/// FAILED one, and the difference is load-bearing rather than stylistic —
/// `ipBucketKey` collapses every caller the trusted header does not identify
/// into one shared bucket, nothing establishes that pg_cron's invocation
/// carries `cf-connecting-ip`, and a limiter in front of the compare would
/// therefore hand an attacker a way to starve the hourly token refresh out of a
/// bucket they share with it (decisions § 973).
///
/// Both halves of that are assertable and both are asserted, because either one
/// alone reads as an oversight to the next person: a throttle that migrated in
/// front of the compare here, or one that migrated behind it on the webhook,
/// would each look like the tree being made consistent with itself.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/refresh-tokens/gate_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
const WEBHOOK = Deno.readTextFileSync(
  new URL('../strava-webhook/index.ts', import.meta.url),
);

/// The CALL, never the named import at the top of the file — an `indexOf` on
/// the bare identifier finds line 1 and makes every ordering claim below
/// unfailable, which is the defect § 937 found in its own first draft.
function callIndex(src: string, fn: string): number {
  return src.search(new RegExp(`\\b${fn}\\s*\\(`));
}

Deno.test('the cron gate throttles a failed guess, at the sibling ceiling', () => {
  assert(
    /checkRateLimit\(\s*admin,\s*await ipBucketKey\(req\),\s*'refresh-tokens:anon',\s*60,\s*3600,\s*\{\s*failClosed: true,?\s*\}/
      .test(SRC),
    'the guess throttle must be IP-keyed on its own bucket at 60/hour and fail closed',
  );
});

Deno.test('a bearerless probe is refused without spending the guess bucket', () => {
  // The ceiling counts GUESSES. An empty POST carries no guess, and it is the
  // cheapest request an attacker can generate — counting it would spend a
  // `rate_limits` write on each one and crowd out the guesses the ceiling is
  // for. The gate is `if (token)`, INSIDE the refusal branch and before the
  // limiter, so the assertion is an ordering one rather than a spelling one.
  const branch = SRC.indexOf("if (!token || !timingSafeEqual(token, cronSecret)) {");
  const tokenGate = SRC.indexOf('if (token) {', branch);
  const limit = SRC.search(/\bcheckRateLimit\s*\(/);
  assert(branch !== -1, 'the cron gate is gone');
  assert(tokenGate !== -1, 'the guess bucket is spent on a request carrying no bearer');
  assert(tokenGate > branch && tokenGate < limit, 'the bearer test must gate the limiter');
});

Deno.test('the throttle is spent on a failed compare, never in front of it', () => {
  const compare = callIndex(SRC, 'timingSafeEqual');
  const limit = callIndex(SRC, 'checkRateLimit');
  const sweep = callIndex(SRC, 'refreshExpiringStravaTokens');
  assert(compare !== -1, 'the timing-safe compare is gone');
  assert(limit !== -1, 'the guess throttle is gone');
  assert(sweep !== -1, 'the sweep call is gone');
  assert(
    compare < limit,
    'a throttle in FRONT of the compare shares one bucket with pg_cron and can starve the hourly refresh out of it',
  );
  assert(limit < sweep, 'the throttle must be reached before the sweep, not after it');
  // Exactly one, and inside the refusal branch: a second call anywhere else is
  // how the authorised path would acquire a database dependency it must not
  // have. The refusal the branch exists to answer with must follow it.
  assertEquals(
    SRC.match(/\bcheckRateLimit\s*\(/g)?.length,
    1,
    'the authorised path must reach no rate limiter at all',
  );
  const refusal = SRC.indexOf("{ error: 'forbidden' }");
  assert(refusal !== -1, 'the 403 refusal is gone');
  assert(limit < refusal, 'the throttle must be spent before the refusal it counts');
});

Deno.test('the sibling keeps the opposite order, which is why this one is stated', () => {
  const compare = callIndex(WEBHOOK, 'timingSafeEqual');
  const limit = callIndex(WEBHOOK, 'checkRateLimit');
  assert(compare !== -1 && limit !== -1, 'strava-webhook lost its compare or its throttle');
  assert(
    limit < compare,
    'strava-webhook limits BEFORE its secret check; if that has changed, § 973 records a divergence that no longer exists',
  );
});
