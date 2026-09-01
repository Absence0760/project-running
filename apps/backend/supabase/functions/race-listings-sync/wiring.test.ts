/// The provider selector, which is the whole of this function's decision
/// surface today.
///
/// `race-listings-sync` had no test of any kind. Its body is a bare
/// `Deno.serve` with no exports, so these are source greps in the
/// `delete-account/wiring.test.ts` idiom, each paired with the positive it
/// depends on.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sync/wiring.test.ts`.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const SIBLING = await Deno.readTextFile(
  new URL('../race-results-import/index.ts', import.meta.url),
);

Deno.test('an unrecognised provider is refused, not read as the default', () => {
  // `body.provider === 'ultrasignup' ? 'ultrasignup' : 'runsignup'` gated a
  // caller's request on a credential for a provider they never named: a 503
  // while RunSignUp's key is missing, and a `synced: 0` success once it lands,
  // for a provider this function has never heard of.
  assert(
    /if \(requested !== 'runsignup' && requested !== 'ultrasignup'\) \{/.test(SRC),
    'the provider must be validated against the set it supports',
  );
  const refusal = SRC.slice(SRC.indexOf("requested !== 'runsignup'"));
  assert(
    /'unknown_provider'[\s\S]{0,60}status: 400/.test(refusal),
    'an unknown provider must answer 400 unknown_provider',
  );
  assert(
    !/body\.provider === 'ultrasignup' \? 'ultrasignup' : 'runsignup'/.test(SRC),
    'the coercing selector must not come back',
  );
  // The sibling this is aligned with still answers the same way, so the two
  // legs of one feature cannot drift apart again unnoticed.
  assert(
    SIBLING.includes("'unknown_provider'"),
    'race-results-import must still refuse an unknown provider too',
  );
});

Deno.test('an omitted provider still defaults, so the refusal costs nothing', () => {
  assert(
    /const requested = body\.provider \?\? 'runsignup';/.test(SRC),
    'an absent provider must still default to RunSignUp',
  );
});

Deno.test('both legs are gated on their own credential pair, fail-closed', () => {
  // A leg whose key or secret is unset must not reach the network; the 503 is
  // the missing-credential rule, and it is per-provider so provisioning one
  // does not open the other.
  assert(SRC.includes("Deno.env.get('ULTRASIGNUP_API_KEY')"), 'the ultrasignup key is not read');
  assert(SRC.includes("Deno.env.get('RUNSIGNUP_API_KEY')"), 'the runsignup key is not read');
  assert(
    /if \(!apiKey \|\| !apiSecret\) \{[\s\S]{0,140}status: 503/.test(SRC),
    'a missing key OR secret must answer 503 provider_not_configured',
  );
  const gate = SRC.indexOf('if (!apiKey || !apiSecret)');
  // The full expression, not the bare `synced: 0` — that phrase also appears
  // in a comment above the gate, and `indexOf` would find the comment.
  const ok = SRC.indexOf('return Response.json({ synced: 0 });');
  assert(gate !== -1 && ok !== -1);
  assert(gate < ok, 'the gate must precede the success answer');
});

Deno.test('the caller is identified and throttled before the gate is spent', () => {
  const auth = SRC.indexOf('await supabase.auth.getUser()');
  const limit = SRC.indexOf('checkRateLimitTiered(');
  const gate = SRC.indexOf('const requested =');
  assert(auth !== -1 && limit !== -1 && gate !== -1);
  assert(auth < limit, 'the caller must be identified before their bucket is chosen');
  assert(limit < gate, 'the throttle must precede the provider work');
  assert(
    /checkRateLimitTiered\(supabase, user\.id, 'race-listings-sync', 2, 8, 3600\)/.test(SRC),
    'the tiered ceilings and window must stay 2 / 8 per hour',
  );
});
