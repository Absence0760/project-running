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
  // Against the outbound FETCH, not against a success answer. The leg used to
  // be a stub whose whole body was `return Response.json({ synced: 0 })`, so
  // ordering the gate before it was the strongest claim available; now that the
  // sync is written, the thing a missing credential must stop is the request
  // going out at all (decisions § 977).
  const out = SRC.indexOf('await fetch(');
  assert(gate !== -1, 'the credential gate is gone');
  assert(out !== -1, 'the leg makes no outbound call at all — is it a stub again?');
  assert(gate < out, 'the credential gate must precede the outbound fetch');
});

Deno.test('the caller is identified and throttled before the gate is spent', () => {
  const auth = SRC.indexOf('await supabase.auth.getUser()');
  const limit = SRC.indexOf('checkRateLimitTiered(');
  const gate = SRC.indexOf('const requested =');
  assert(auth !== -1 && limit !== -1 && gate !== -1);
  assert(auth < limit, 'the caller must be identified before their bucket is chosen');
  assert(limit < gate, 'the throttle must precede the provider work');
  assert(
    /checkRateLimitTiered\(supabase, user\.id, 'race-listings-sync', 2, 8, 3600, \{\s*failClosed: true,?\s*\}\)/
      .test(SRC),
    'the tiered ceilings and window must stay 2 / 8 per hour, and fail closed',
  );
});

Deno.test('the calendar write runs as the service role, not as the caller', () => {
  // `race_listings_force_unverified` (migration `20270214_001`) forces
  // `is_verified` false for every role but service_role, and the INSERT policy
  // requires `submitted_by = auth.uid()` — so a provider race written on the
  // caller's client would land as an unverified crowd submission attributed to
  // whoever happened to trigger the sync (decisions § 977).
  assert(SRC.includes("import { publishableKey, secretKey }"), 'the secret key is not imported');
  const service = SRC.indexOf('const service = createClient<Database>(Deno.env.get(\'SUPABASE_URL\')!, secretKey());');
  assert(service !== -1, 'the write client is not the service role');
  const insert = SRC.indexOf("service\n    .from('race_listings')");
  const insertShort = SRC.indexOf("service.from('race_listings').insert(");
  assert(insert !== -1 || insertShort !== -1, 'the insert does not go through the service client');
  assert(
    !/supabase\s*\n?\s*\.from\('race_listings'\)/.test(SRC),
    'the caller-scoped client must never write race_listings',
  );
  assert(SRC.includes('is_verified: true'), 'the update path drops the verified flag');
});

Deno.test('a failed read of what is stored is an error, not an empty calendar', () => {
  // Treating a read error as "nothing stored" re-inserts every race in the feed
  // and duplicates the calendar on the next sync.
  const read = SRC.indexOf("const { data: storedRows, error: readErr }");
  assert(read !== -1, 'the existing-listing read is gone');
  assert(
    /if \(readErr\) \{[\s\S]{0,400}?status: 500/.test(SRC.slice(read)),
    'a failed existing-listing read must refuse rather than proceed',
  );
  const reconcile = SRC.indexOf('reconcileListingBatch(');
  assert(reconcile !== -1 && read < reconcile, 'the batch must be reconciled against a real read');
});

Deno.test('an upstream that is not 2xx or not JSON fails loud, and writes nothing', () => {
  // Feeding an error page into the parser answers `synced: 0`, which is
  // indistinguishable from a region with no races.
  assert(/if \(!upstream\.ok\) \{[\s\S]{0,400}?status: 502/.test(SRC), 'a non-2xx is not refused');
  assert(
    /upstream not JSON` \}, \{ status: 502 \}/.test(SRC),
    'an unparseable body is not refused',
  );
  const bad = SRC.indexOf('if (!upstream.ok)');
  const write = SRC.indexOf('.insert(');
  assert(bad !== -1 && write !== -1 && bad < write, 'the upstream check must precede any write');
});

Deno.test('the response says what it could not read, so a wrong shape is visible at once', () => {
  // No credential exists for either provider, so the field names in lib.ts are
  // unverified. A payload shaped differently must answer `synced: 0` with
  // `unusable` equal to the row count rather than writing junk into a calendar
  // every user of the deployment reads.
  assert(SRC.includes('unusable++;'), 'nothing counts the rows that could not be read');
  for (const field of ['synced', 'updated', 'skipped', 'unusable', 'total', 'complete']) {
    assert(
      new RegExp(`\\b${field}[,:]`).test(SRC),
      `the response omits ${field}`,
    );
  }
});

Deno.test('a call that did not ask for a sync performs none', () => {
  // Every caller in the tree is a credential probe — web's two
  // `isRunSignUpConfigured` / `isUltraSignUpConfigured` invocations and mobile's
  // two `probeFunction` entries — and nothing reads `synced`. A probe that
  // walked the provider feed would write the shared calendar on a page load and
  // spend the 2/hour bucket, so the second probe in an hour would 429 and the
  // tile would read unavailable for the rest of it (decisions § 977).
  const gate = SRC.indexOf('if (body.sync !== true) {');
  const out = SRC.indexOf('await fetch(');
  const write = SRC.indexOf('.insert(');
  assert(gate !== -1, 'a sync runs without the caller asking for one');
  assert(out !== -1 && write !== -1);
  assert(gate < out, 'the opt-in must precede the outbound fetch');
  assert(gate < write, 'the opt-in must precede any write');
  assert(
    /if \(body\.sync !== true\) \{\s*return Response\.json\(\{ configured: true \}\);/.test(SRC),
    'a probe must answer the credential verdict, not a sync result',
  );
  // And it must sit BEHIND the credential gate, or an unprovisioned deploy
  // would report itself configured.
  const cred = SRC.indexOf('if (!apiKey || !apiSecret)');
  assert(cred !== -1 && cred < gate, 'the probe answer must follow the credential gate');
});
