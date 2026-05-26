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

// ── positive-path tests ───────────────────────────────────────────
// The auth-rejection tests above are enough to catch a regression
// in the wire-level gate. These cover the happy path + the replay-
// protection / dedupe / freshness branches that only get exercised
// when the signature actually passes. The test reads the secret
// values from env vars so it works against whichever .env file the
// `supabase functions serve --env-file` host loaded — CI plants
// `ci-*` values, local dev uses whatever's in apps/backend/.env.local.
// Defaults match the CI fixture so a developer with `supabase
// functions serve` running against the CI-style env doesn't need
// to export anything.

const REVENUECAT_SECRET =
  Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? 'ci-revenuecat-secret';
// audit/strava May 2026 Low #2 — the strava-webhook EF refuses to
// operate with a <32-char secret. Bump the test defaults so the
// `webhook_not_configured` branch isn't the answer to every test.
const STRAVA_WEBHOOK_SECRET =
  Deno.env.get('STRAVA_WEBHOOK_SECRET') ?? 'ci-strava-webhook-secret-32chars-ok';
const STRAVA_VERIFY_TOKEN =
  Deno.env.get('STRAVA_VERIFY_TOKEN') ?? 'ci-strava-verify-token-32-chars-ok';

// HMAC-SHA256 hex of `body` keyed by `secret`. Matches the EF's
// `hmacHex` in _shared/webhook_security.ts.
async function hmacHex(secret: string, body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const buf = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.test({
  name: 'revenuecat-webhook: 200 on valid HMAC + fresh anonymous event',
  ignore: SKIP,
  fn: async () => {
    // RevenueCat sends `$RCAnonymousID:...` for sandbox / test users
    // that never logged in. The handler short-circuits these with
    // `skipped: anonymous_user` BEFORE the dedupe insert — so the
    // test exercises the full HMAC + freshness + body-parse chain
    // without polluting webhook_events (which would fail the test
    // on re-run).
    const event = {
      event: {
        id: `evt_pos_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        type: 'INITIAL_PURCHASE',
        event_timestamp_ms: Date.now(),
        app_user_id: '$RCAnonymousID:test-anon',
        product_id: 'pro_monthly',
      },
    };
    const body = JSON.stringify(event);
    const sig = await hmacHex(REVENUECAT_SECRET, body);
    const res = await fetch(endpoint('revenuecat-webhook'), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-revenuecat-hmac': sig,
      },
      body,
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 200) {
      throw new Error(
        `expected 200 on valid HMAC + anon user, got ${res.status} ${JSON.stringify(json)}`,
      );
    }
    if (json?.skipped !== 'anonymous_user') {
      throw new Error(
        `expected skipped=anonymous_user (proves HMAC + freshness passed but ' +
        'the anon-user short-circuit fired), got ${JSON.stringify(json)}`,
      );
    }
  },
});

Deno.test({
  name: 'revenuecat-webhook: 400 event_outside_freshness_window on stale event',
  ignore: SKIP,
  fn: async () => {
    // 14 days in the past — well outside the default 7-day replay
    // window. Valid HMAC; the freshness gate should reject it BEFORE
    // dedupe or user-resolution runs.
    const fourteenDaysAgo = Date.now() - 14 * 24 * 3600 * 1000;
    const event = {
      event: {
        id: `evt_stale_${Date.now()}`,
        type: 'INITIAL_PURCHASE',
        event_timestamp_ms: fourteenDaysAgo,
        app_user_id: '$RCAnonymousID:stale',
        product_id: 'pro_monthly',
      },
    };
    const body = JSON.stringify(event);
    const sig = await hmacHex(REVENUECAT_SECRET, body);
    const res = await fetch(endpoint('revenuecat-webhook'), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-revenuecat-hmac': sig,
      },
      body,
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 400) {
      throw new Error(
        `expected 400 event_outside_freshness_window, got ${res.status} ${JSON.stringify(json)}`,
      );
    }
    if (json?.error !== 'event_outside_freshness_window') {
      throw new Error(
        `expected error: event_outside_freshness_window, got ${JSON.stringify(json)}`,
      );
    }
  },
});

Deno.test({
  name: 'revenuecat-webhook: 400 missing_event_timestamp_ms when timestamp absent',
  ignore: SKIP,
  fn: async () => {
    // No `event_timestamp_ms`. Valid HMAC; the body-shape gate after
    // HMAC verification should reject with a specific error code so
    // a misconfigured sender knows what to fix.
    const event = {
      event: {
        id: `evt_no_ts_${Date.now()}`,
        type: 'INITIAL_PURCHASE',
        app_user_id: '$RCAnonymousID:no-ts',
      },
    };
    const body = JSON.stringify(event);
    const sig = await hmacHex(REVENUECAT_SECRET, body);
    const res = await fetch(endpoint('revenuecat-webhook'), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-revenuecat-hmac': sig,
      },
      body,
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 400) {
      throw new Error(
        `expected 400, got ${res.status} ${JSON.stringify(json)}`,
      );
    }
    if (json?.error !== 'missing_event_timestamp_ms') {
      throw new Error(
        `expected error: missing_event_timestamp_ms, got ${JSON.stringify(json)}`,
      );
    }
  },
});

Deno.test({
  name: 'strava-webhook: GET handshake echoes hub.challenge on correct secret + verify_token',
  ignore: SKIP,
  fn: async () => {
    // The handshake is what Strava calls during subscription
    // registration. A correct `secret` + `hub.verify_token` must
    // produce `{"hub.challenge": "<challenge>"}` so Strava accepts
    // the subscription.
    const challenge = `ch_${Date.now()}`;
    const url =
      `${endpoint('strava-webhook')}?secret=${STRAVA_WEBHOOK_SECRET}` +
      `&hub.mode=subscribe&hub.challenge=${challenge}` +
      `&hub.verify_token=${STRAVA_VERIFY_TOKEN}`;
    const res = await fetch(url);
    const json = await res.json().catch(() => null);
    if (res.status === 429) return; // rate-limited shared-IP noise; tolerate
    if (res.status !== 200) {
      throw new Error(
        `expected 200 on valid handshake, got ${res.status} ${JSON.stringify(json)}`,
      );
    }
    if (json?.['hub.challenge'] !== challenge) {
      throw new Error(
        `expected hub.challenge=${challenge}, got ${JSON.stringify(json)}`,
      );
    }
  },
});

Deno.test({
  name: 'strava-webhook: 200 "OK" on non-create event after valid secret',
  ignore: SKIP,
  fn: async () => {
    // An athlete `update` is the cheapest non-actionable shape that
    // proves the secret + body-parse path works without enqueuing
    // anything (the EF early-returns "OK" before dedupe / freshness).
    // A `create` event would require an `integrations` row keyed on
    // owner_id, which the seed user doesn't have a Strava
    // connection for under the test fixture.
    const body = JSON.stringify({
      object_type: 'athlete',
      object_id: 12345,
      aspect_type: 'update',
      owner_id: 12345,
      event_time: Math.floor(Date.now() / 1000),
    });
    const res = await fetch(
      `${endpoint('strava-webhook')}?secret=${STRAVA_WEBHOOK_SECRET}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
      },
    );
    if (res.status === 429) {
      await res.body?.cancel();
      return; // tolerate shared-IP rate-limit noise
    }
    const text = await res.text();
    if (res.status !== 200) {
      throw new Error(
        `expected 200 on non-create event, got ${res.status} body=${text}`,
      );
    }
    if (text !== 'OK') {
      throw new Error(
        `expected body "OK" on non-actionable event, got ${JSON.stringify(text)}`,
      );
    }
  },
});

Deno.test({
  name: 'strava-webhook: 400 missing_object_id_or_owner_id on create-shaped event with no ids',
  ignore: SKIP,
  fn: async () => {
    // A `create` event with empty ids: the secret + method gates
    // pass, the early-return on non-actionable doesn't fire, then
    // the body-shape gate rejects with the documented error code.
    const body = JSON.stringify({
      object_type: 'activity',
      aspect_type: 'create',
      event_time: Math.floor(Date.now() / 1000),
    });
    const res = await fetch(
      `${endpoint('strava-webhook')}?secret=${STRAVA_WEBHOOK_SECRET}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
      },
    );
    if (res.status === 429) {
      await res.body?.cancel();
      return;
    }
    const json = await res.json().catch(() => null);
    if (res.status !== 400) {
      throw new Error(
        `expected 400 on missing object/owner ids, got ${res.status} ${JSON.stringify(json)}`,
      );
    }
    if (json?.error !== 'missing_object_id_or_owner_id') {
      throw new Error(
        `expected error: missing_object_id_or_owner_id, got ${JSON.stringify(json)}`,
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
