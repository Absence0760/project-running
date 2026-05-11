// HTTP-level handler-envelope tests for the three webhook / cron
// functions that bypass the platform's `verify_jwt` gate
// (`config.toml` pins `verify_jwt = false` for these three because
// they authenticate themselves another way). These tests close the
// "Edge Function HTTP envelope" gap from docs/testing.md — the pure
// helpers in `_shared/webhook_security.ts` + `revenuecat-webhook/lib.ts`
// are already covered (~33 deno tests); this file pins the WIRE-LEVEL
// auth-rejection behaviour of the handlers that compose those helpers
// with `serve()` + `createClient()`.
//
// Why only the three webhook functions: the five JWT-gated functions
// (clip-public-track, delete-account, export-data, parkrun-import,
// strava-import) are 401'd at the platform gateway before the
// handler runs, so the handler-body auth surface there is degenerate
// — the platform's `verify_jwt = true` config IS the test. The three
// here are the ones where the handler does its own auth, which is
// where bugs would actually surface.
//
// **Skipped unless SUPABASE_TEST_URL is set.** Run locally with:
//   cd apps/backend && supabase status -o env
//   export SUPABASE_TEST_URL=http://127.0.0.1:54321
//   deno test --no-check --allow-net --allow-env \
//     supabase/functions/_shared/handler_envelope.test.ts

const TEST_URL = Deno.env.get('SUPABASE_TEST_URL') ?? '';
const SKIP = TEST_URL.length === 0;
const SKIP_REASON =
  'Set SUPABASE_TEST_URL to run handler-envelope integration tests ' +
  '(needs a running local Supabase + functions host).';

function endpoint(name: string): string {
  return `${TEST_URL.replace(/\/$/, '')}/functions/v1/${name}`;
}

// ── refresh-tokens ────────────────────────────────────────────────
// Triggered by pg_cron with `Authorization: Bearer ${CRON_SECRET}`.
// The handler reads `CRON_SECRET` from env and timing-safe compares
// against the bearer token. Without the gate, the function URL is
// publicly invokable and would loop the entire integrations table
// through Strava's OAuth refresh endpoint.

Deno.test({
  name: 'refresh-tokens: 403 on missing Authorization header',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('refresh-tokens'), { method: 'POST' });
    await res.body?.cancel();
    if (res.status !== 403) {
      throw new Error(
        `expected 403 (forbidden — no bearer), got ${res.status}; ` +
        'the cron-secret gate must reject missing-Auth requests.',
      );
    }
  },
});

Deno.test({
  name: 'refresh-tokens: 403 on wrong CRON_SECRET',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('refresh-tokens'), {
      method: 'POST',
      headers: { Authorization: 'Bearer not-the-real-secret-x123' },
    });
    await res.body?.cancel();
    if (res.status !== 403) {
      throw new Error(
        `expected 403 (forbidden — wrong bearer), got ${res.status}; ` +
        'the timing-safe compare must reject mismatched secrets.',
      );
    }
  },
});

Deno.test({
  name: 'refresh-tokens: 403 on a non-Bearer Authorization header',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('refresh-tokens'), {
      method: 'POST',
      // Basic-auth-style header — the handler's `auth.startsWith('Bearer ')`
      // check should reject this without ever reaching timingSafeEqual.
      headers: { Authorization: 'Basic dXNlcjpwYXNz' },
    });
    await res.body?.cancel();
    if (res.status !== 403) {
      throw new Error(
        `expected 403 (non-Bearer Authorization), got ${res.status}`,
      );
    }
  },
});

// ── strava-webhook ────────────────────────────────────────────────
// Strava doesn't sign POSTs, so the only auth on the POST surface is
// `?secret=<STRAVA_WEBHOOK_SECRET>` in the callback URL Strava POSTs
// to. GET adds `hub.verify_token` on top. The handler also rate-
// limits per-IP BEFORE the secret check (60/hour), so a high test
// volume could hit 429 first — these tests are spaced light.

Deno.test({
  name: 'strava-webhook: 403 on POST with no ?secret=',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('strava-webhook'), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });
    await res.body?.cancel();
    // 403 = forbidden; 429 = rate-limited (acceptable noise from a
    // shared CI runner IP). Either way the secret-gate must not let
    // an unsecreted request through to handler logic — a 200 here
    // would be the regression.
    if (res.status !== 403 && res.status !== 429) {
      throw new Error(
        `expected 403 (or 429 rate-limited), got ${res.status}; ` +
        'the secret gate must reject ?secret-less requests.',
      );
    }
  },
});

Deno.test({
  name: 'strava-webhook: 403 on GET with no ?secret=',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('strava-webhook'));
    await res.body?.cancel();
    if (res.status !== 403 && res.status !== 429) {
      throw new Error(
        `expected 403 (or 429), got ${res.status}; the secret ` +
        'gate guards GET (hub.verify_token handshake) too.',
      );
    }
  },
});

Deno.test({
  name: 'strava-webhook: 403 on POST with wrong ?secret= value',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(
      `${endpoint('strava-webhook')}?secret=not-the-real-strava-webhook-secret`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}',
      },
    );
    await res.body?.cancel();
    if (res.status !== 403 && res.status !== 429) {
      throw new Error(
        `expected 403 (or 429), got ${res.status}; the timing-safe ` +
        'compare must reject mismatched secrets.',
      );
    }
  },
});

// ── revenuecat-webhook ────────────────────────────────────────────
// RevenueCat HMAC-signs the raw body with REVENUECAT_WEBHOOK_SECRET
// and sends the hex digest in `x-revenuecat-hmac`. The handler
// constant-time compares against its own HMAC of the body. Replay
// protection lives downstream of the signature check, so an
// unsigned request never even reaches the replay window.

Deno.test({
  name: 'revenuecat-webhook: 405 on GET (POST-only)',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('revenuecat-webhook'));
    await res.body?.cancel();
    if (res.status !== 405) {
      throw new Error(
        `expected 405 (method-not-allowed), got ${res.status}; ` +
        'the method gate must reject GET before reading body.',
      );
    }
  },
});

Deno.test({
  name: 'revenuecat-webhook: 401 missing_signature when no ' +
    'x-revenuecat-hmac header',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('revenuecat-webhook'), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"event":{}}',
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 401) {
      throw new Error(
        `expected 401 (missing_signature), got ${res.status}; ` +
        'an HMAC-less POST must never reach JSON parsing or downstream.',
      );
    }
    if (json?.error !== 'missing_signature') {
      throw new Error(
        `expected error: missing_signature, got ${JSON.stringify(json)}; ` +
        'the response body shape is part of the contract.',
      );
    }
  },
});

Deno.test({
  name: 'revenuecat-webhook: 401 bad_signature on wrong HMAC',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('revenuecat-webhook'), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // A plausible-shape 64-char hex digest that isn't the real one.
        'x-revenuecat-hmac':
          '0'.repeat(64),
      },
      body: '{"event":{"id":"evt_test","event_timestamp_ms":1}}',
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 401) {
      throw new Error(
        `expected 401 (bad_signature), got ${res.status}; ` +
        'a wrong HMAC must be rejected — not pass through to body parsing.',
      );
    }
    if (json?.error !== 'bad_signature') {
      throw new Error(
        `expected error: bad_signature, got ${JSON.stringify(json)}`,
      );
    }
  },
});

// ── docstring placeholder so deno test reports zero ignored when the
//    env var isn't set, instead of "no tests" ────────────────────────
if (SKIP) {
  Deno.test({
    name: 'handler-envelope tests skipped',
    ignore: true,
    fn: () => {},
  });
  console.error(SKIP_REASON);
}
