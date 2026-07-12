// HTTP-level handler-envelope tests for the webhook / cron / hook
// functions that bypass the platform's `verify_jwt` gate
// (`config.toml` pins `verify_jwt = false` for these five —
// refresh-tokens, strava-webhook, revenuecat-webhook, stripe-events-
// webhook, auth-email — because they authenticate themselves another way). These tests close the
// "Edge Function HTTP envelope" gap from docs/testing/testing.md — the pure
// helpers in `_shared/webhook_security.ts` + `revenuecat-webhook/lib.ts`
// are already covered (~33 deno tests); this file pins the WIRE-LEVEL
// auth-rejection behaviour of the handlers that compose those helpers
// with `serve()` + `createClient()`.
//
// Why only these webhook functions: the five JWT-gated functions
// (clip-public-track, delete-account, export-data, parkrun-import,
// strava-import) are 401'd at the platform gateway before the
// handler runs, so the handler-body auth surface there is degenerate
// — the platform's `verify_jwt = true` config IS the test. The five
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

// ── auth-email ────────────────────────────────────────────────────
// GoTrue's send-email hook signs each POST per the Standard Webhooks
// spec (webhook-id / webhook-timestamp / webhook-signature over the
// raw body, keyed by SEND_EMAIL_HOOK_SECRET). The signature IS the
// trust boundary — verify_jwt is false, so these tests prove an
// unsigned caller can't make the function render + send auth mail.
// They expect the env-loaded host (the CI step's .env.local carries a
// ci-scoped SEND_EMAIL_HOOK_SECRET); without the secret the handler
// 503s hook_not_configured instead, which fails these loudly.

Deno.test({
  name: 'auth-email: 405 on GET (POST-only)',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('auth-email'));
    await res.body?.cancel();
    if (res.status !== 405) {
      throw new Error(
        `expected 405 (method-not-allowed), got ${res.status}; ` +
        'the method gate must reject GET before reading the body.',
      );
    }
  },
});

Deno.test({
  name: 'auth-email: 401 missing_headers when the Standard Webhooks ' +
    'headers are absent',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('auth-email'), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"user":{"email":"a@example.com"},"email_data":{"email_action_type":"signup"}}',
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 401) {
      throw new Error(
        `expected 401 (missing_headers), got ${res.status}; ` +
        'an unsigned POST must never reach rendering or SMTP.',
      );
    }
    if (json?.error !== 'missing_headers') {
      throw new Error(
        `expected error: missing_headers, got ${JSON.stringify(json)}; ` +
        'the response body shape is part of the contract.',
      );
    }
  },
});

Deno.test({
  name: 'auth-email: 401 bad_signature on a wrong signature',
  ignore: SKIP,
  fn: async () => {
    const res = await fetch(endpoint('auth-email'), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_envelope_test',
        // Fresh timestamp so the freshness window can't be what rejects.
        'webhook-timestamp': String(Math.floor(Date.now() / 1000)),
        'webhook-signature': `v1,${btoa('not-the-real-signature')}`,
      },
      body: '{"user":{"email":"a@example.com"},"email_data":{"email_action_type":"signup"}}',
    });
    const json = await res.json().catch(() => null);
    if (res.status !== 401) {
      throw new Error(
        `expected 401 (bad_signature), got ${res.status}; ` +
        'a wrong HMAC must be rejected — not pass through to sending.',
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

// The revenuecat-webhook tier-flip test plants an ephemeral user +
// reads the written user_profiles row back, so it needs a service-role
// key on top of SUPABASE_TEST_URL. Gated separately so the wire-level
// tests above still run when only the webhook secret is configured.
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const SKIP_DB = SKIP || SERVICE_ROLE_KEY.length === 0;

// Service-role REST/auth-admin fetch — bypasses RLS + the
// lock_subscription_columns trigger (which the webhook itself bypasses
// via its own service-role client), so the test can plant the fixture
// and observe the column the handler writes.
function svc(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${TEST_URL.replace(/\/$/, '')}${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'content-type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

// POST a RevenueCat event with a valid HMAC over the serialized body.
async function postRcEvent(
  ev: Record<string, unknown>,
): Promise<{ status: number; json: { new_tier?: unknown; skipped?: unknown } | null }> {
  const body = JSON.stringify({ event: ev });
  const sig = await hmacHex(REVENUECAT_SECRET, body);
  const res = await fetch(endpoint('revenuecat-webhook'), {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-revenuecat-hmac': sig },
    body,
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json };
}

// Must match the .env.local block the CI boot step writes (mirrored into
// the integration step's env so the signature the function host verifies
// against matches).
const STRIPE_EVENTS_SECRET =
  Deno.env.get('STRIPE_EVENTS_WEBHOOK_SECRET') ?? 'ci-stripe-events-secret';

// POST a Stripe event with a valid `Stripe-Signature` header. Stripe
// signs the literal `${t}.${rawBody}` (see verifyStripeSignature); the
// timestamp is recomputed per call so a replay (same event.id, fresh
// signature) still passes the freshness gate and exercises the
// event-id dedupe rather than the replay-window reject.
async function postStripeEvent(
  event: Record<string, unknown>,
): Promise<{ status: number; json: Record<string, unknown> | null }> {
  const body = JSON.stringify(event);
  const t = Math.floor(Date.now() / 1000);
  const v1 = await hmacHex(STRIPE_EVENTS_SECRET, `${t}.${body}`);
  const res = await fetch(endpoint('stripe-events-webhook'), {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'stripe-signature': `t=${t},v1=${v1}` },
    body,
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json };
}

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

// ── revenuecat-webhook: the SIDE EFFECT, not just the envelope ─────
// The tests above prove the auth/freshness/anon gates. This one proves
// the part the pure `lib.test.ts` mappers can't: that the decided tier
// actually reaches `user_profiles`, that a replayed delivery is deduped
// (not double-applied), that EXPIRATION downgrades, and that a
// PRODUCT_CHANGE reads the WRITTEN current tier back so a lifetime
// holder isn't downgraded. Drives an ephemeral user end-to-end so the
// seed user's tier is never mutated.

Deno.test({
  name: 'revenuecat-webhook: writes user_profiles — pro → dedupe → free → ' +
    'lifetime → lifetime-protected PRODUCT_CHANGE',
  ignore: SKIP_DB,
  fn: async () => {
    // GoTrue admin create. No auth.users→user_profiles trigger exists
    // (the row is normally created by confirm_age_and_terms()), so the
    // handler's `.update().eq('id', userId)` would silently match zero
    // rows without an explicit plant — defeating the whole assertion.
    const email = `rc-webhook-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.test`;
    const createRes = await svc('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'testtest-rc-123', email_confirm: true }),
    });
    const created = await createRes.json().catch(() => null);
    const userId = created?.id as string | undefined;
    if (!userId) {
      throw new Error(
        `failed to create ephemeral user: ${createRes.status} ${JSON.stringify(created)}`,
      );
    }

    const eventIds: string[] = [];
    const mkEvent = (type: string, productId: string | null): Record<string, unknown> => {
      const id = `evt_int_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      eventIds.push(id);
      const ev: Record<string, unknown> = {
        id,
        type,
        event_timestamp_ms: Date.now(),
        app_user_id: userId,
      };
      if (productId !== null) ev.product_id = productId;
      return ev;
    };
    const readTier = async (): Promise<string | null> => {
      const r = await svc(
        `/rest/v1/user_profiles?id=eq.${userId}&select=subscription_tier`,
      );
      const rows = await r.json().catch(() => []);
      return Array.isArray(rows) && rows[0]
        ? (rows[0].subscription_tier ?? null)
        : null;
    };

    try {
      const profRes = await svc('/rest/v1/user_profiles', {
        method: 'POST',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ id: userId, subscription_tier: 'free' }),
      });
      const profStatus = profRes.status;
      await profRes.body?.cancel();
      if (profStatus >= 300) {
        throw new Error(`failed to plant user_profiles row: ${profStatus}`);
      }

      // (a) INITIAL_PURCHASE → pro, and the write must land in the row.
      const initial = mkEvent('INITIAL_PURCHASE', 'pro_monthly');
      let r = await postRcEvent(initial);
      if (r.status !== 200 || r.json?.new_tier !== 'pro') {
        throw new Error(
          `(a) expected 200 new_tier=pro, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      if (await readTier() !== 'pro') {
        throw new Error('(a) user_profiles.subscription_tier did not flip to pro');
      }

      // (b) Replay the SAME delivery — identical body → identical event
      // id → 23505 → skipped, and the tier must NOT move again.
      const initialBody = JSON.stringify({ event: initial });
      const initialSig = await hmacHex(REVENUECAT_SECRET, initialBody);
      const replay = await fetch(endpoint('revenuecat-webhook'), {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-revenuecat-hmac': initialSig },
        body: initialBody,
      });
      const replayJson = await replay.json().catch(() => null);
      if (replay.status !== 200 || replayJson?.skipped !== 'duplicate_event') {
        throw new Error(
          `(b) expected 200 skipped=duplicate_event, got ${replay.status} ${JSON.stringify(replayJson)}`,
        );
      }
      if (await readTier() !== 'pro') {
        throw new Error('(b) a deduped replay must not re-apply the tier');
      }

      // (c) EXPIRATION on a non-lifetime tier → downgrade to free.
      r = await postRcEvent(mkEvent('EXPIRATION', 'pro_monthly'));
      if (r.status !== 200 || r.json?.new_tier !== 'free') {
        throw new Error(
          `(c) expected new_tier=free, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      if (await readTier() !== 'free') {
        throw new Error('(c) user_profiles did not downgrade to free on EXPIRATION');
      }

      // (d) INITIAL_PURCHASE of a lifetime product → lifetime.
      r = await postRcEvent(mkEvent('INITIAL_PURCHASE', 'pro_lifetime'));
      if (r.status !== 200 || r.json?.new_tier !== 'lifetime') {
        throw new Error(
          `(d) expected new_tier=lifetime, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      if (await readTier() !== 'lifetime') {
        throw new Error('(d) user_profiles did not become lifetime');
      }

      // (e) A PRODUCT_CHANGE to a non-lifetime product must NOT knock a
      // lifetime holder down — the handler looks up the CURRENT tier
      // (written in (d)) so the mapper returns null and the patch is a
      // no-op. This is the one path that proves the read-back, not just
      // the write.
      r = await postRcEvent(mkEvent('PRODUCT_CHANGE', 'pro_monthly'));
      if (r.status !== 200 || r.json?.new_tier != null) {
        throw new Error(
          `(e) expected new_tier=null (lifetime protected), got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      if (await readTier() !== 'lifetime') {
        throw new Error('(e) lifetime holder was wrongly downgraded by PRODUCT_CHANGE');
      }
    } finally {
      // webhook_events is keyed (provider, event_id) — drop ours so a
      // re-run stays clean (the 30-day prune would eventually too).
      for (const id of eventIds) {
        await svc(
          `/rest/v1/webhook_events?provider=eq.revenuecat&event_id=eq.${id}`,
          { method: 'DELETE' },
        ).then((x) => x.body?.cancel());
      }
      // Deleting the auth user cascades the user_profiles row (the FK is
      // on delete cascade per migration 20260728_001).
      await svc(`/auth/v1/admin/users/${userId}`, { method: 'DELETE' })
        .then((x) => x.body?.cancel());
    }
  },
});

// ── stripe-events-webhook: account.updated SIDE EFFECT + dedupe ────
// handleAccountUpdated is the ONLY path that flips a host to charges-
// enabled, and it had no coverage of any kind. The pure lib tests cover
// the signature verifier + CAS; this proves the account.updated handler
// actually mirrors the capability flags into instructor_payout_accounts
// and that a replayed delivery is deduped (not re-applied).

Deno.test({
  name: 'stripe-events-webhook: account.updated mirrors capability flags ' +
    'into instructor_payout_accounts + dedupes a replay',
  ignore: SKIP_DB,
  fn: async () => {
    const email = `stripe-host-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.test`;
    const createRes = await svc('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'testtest-stripe-1', email_confirm: true }),
    });
    const created = await createRes.json().catch(() => null);
    const userId = created?.id as string | undefined;
    if (!userId) {
      throw new Error(
        `failed to create ephemeral host: ${createRes.status} ${JSON.stringify(created)}`,
      );
    }

    const acctId = `acct_test_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const eventId = `evt_acct_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    try {
      // Plant the payout account in the pre-onboarding state the
      // events-connect-onboard EF leaves it in (charges disabled until
      // Stripe says otherwise via exactly this event).
      const plant = await svc('/rest/v1/instructor_payout_accounts', {
        method: 'POST',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({
          user_id: userId,
          stripe_connect_account_id: acctId,
          charges_enabled: false,
          payouts_enabled: false,
          details_submitted: false,
        }),
      });
      const plantStatus = plant.status;
      await plant.body?.cancel();
      if (plantStatus >= 300) {
        throw new Error(`failed to plant instructor_payout_accounts: ${plantStatus}`);
      }

      const readAcct = async (): Promise<Record<string, unknown> | null> => {
        const r = await svc(
          `/rest/v1/instructor_payout_accounts?stripe_connect_account_id=eq.${acctId}` +
            `&select=charges_enabled,payouts_enabled,details_submitted,onboarded_at`,
        );
        const rows = await r.json().catch(() => []);
        return Array.isArray(rows) && rows[0] ? rows[0] : null;
      };

      const accountEvent = {
        id: eventId,
        type: 'account.updated',
        data: {
          object: {
            id: acctId,
            charges_enabled: true,
            payouts_enabled: true,
            details_submitted: true,
          },
        },
      };

      // (a) The capability flags must land + onboarded_at must stamp
      // (details_submitted=true).
      let r = await postStripeEvent(accountEvent);
      if (r.status !== 200 || r.json?.account_synced !== true) {
        throw new Error(
          `(a) expected 200 account_synced=true, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      const after = await readAcct();
      if (
        after?.charges_enabled !== true ||
        after?.payouts_enabled !== true ||
        after?.details_submitted !== true ||
        after?.onboarded_at == null
      ) {
        throw new Error(
          `(a) instructor_payout_accounts not mirrored: ${JSON.stringify(after)}`,
        );
      }

      // (b) Replay the same event id (fresh signature, valid freshness)
      // → 23505 dedupe → skipped, never re-applied.
      r = await postStripeEvent(accountEvent);
      if (r.status !== 200 || r.json?.skipped !== 'duplicate_event') {
        throw new Error(
          `(b) expected 200 skipped=duplicate_event, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
    } finally {
      await svc(
        `/rest/v1/webhook_events?provider=eq.stripe&event_id=eq.${eventId}`,
        { method: 'DELETE' },
      ).then((x) => x.body?.cancel());
      await svc(`/auth/v1/admin/users/${userId}`, { method: 'DELETE' })
        .then((x) => x.body?.cancel());
    }
  },
});

// ── stripe-events-webhook: the DONATION lifecycle SIDE EFFECT ──────
// The account.updated test above proves ONE of the four event types the
// webhook writes. This proves the donation money path — the fundraising.md
// ledger — which had zero HTTP-level coverage: a self-signed
// checkout.session.completed (metadata.kind='donation') flips donations
// pending->paid + records the payment intent, a replay is deduped (not
// double-counted), and a self-signed charge.refunded resolves the donation
// by payment intent and CAS's it paid->refunded. Drives an ephemeral owner
// end-to-end so no seed row is mutated. Self-signed exactly like the
// account.updated test (postStripeEvent computes a valid Stripe-Signature
// over `${t}.${body}` against the CI-mirrored ci-stripe-events-secret), so
// it exercises the REAL verify + parse + dedupe + write chain without any
// operator whsec_ key.

Deno.test({
  name: 'stripe-events-webhook: donation checkout.session.completed marks ' +
    'donations paid + dedupes a replay + charge.refunded refunds it',
  ignore: SKIP_DB,
  fn: async () => {
    const email = `stripe-donor-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.test`;
    const createRes = await svc('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'testtest-don-1', email_confirm: true }),
    });
    const created = await createRes.json().catch(() => null);
    const userId = created?.id as string | undefined;
    if (!userId) {
      throw new Error(
        `failed to create ephemeral donor: ${createRes.status} ${JSON.stringify(created)}`,
      );
    }

    const acctId = `acct_don_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const runId = crypto.randomUUID();
    const fundraiserId = crypto.randomUUID();
    const donationId = crypto.randomUUID();
    const paymentIntent = `pi_don_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const completedEventId = `evt_don_c_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const refundEventId = `evt_don_r_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

    const plant = async (path: string, row: Record<string, unknown>) => {
      const res = await svc(path, {
        method: 'POST',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify(row),
      });
      const status = res.status;
      await res.body?.cancel();
      if (status >= 300) throw new Error(`failed to plant ${path}: ${status}`);
    };
    const readDonation = async (): Promise<Record<string, unknown> | null> => {
      const r = await svc(
        `/rest/v1/donations?id=eq.${donationId}&select=status,stripe_payment_intent_id`,
      );
      const rows = await r.json().catch(() => []);
      return Array.isArray(rows) && rows[0] ? rows[0] : null;
    };

    try {
      // A fundraiser can only open with a charges-enabled payout account
      // (enforce_fundraiser_requires_charges), so plant that capability
      // first — the same pre-onboarding row the account.updated test uses,
      // but already charges-enabled.
      await plant('/rest/v1/instructor_payout_accounts', {
        user_id: userId,
        stripe_connect_account_id: acctId,
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true,
      });
      // The fundraiser needs exactly one anchor; a run is the cheapest.
      await plant('/rest/v1/runs', {
        id: runId,
        user_id: userId,
        started_at: new Date().toISOString(),
        duration_s: 1800,
        distance_m: 5000,
        source: 'app',
        metadata: { activity_type: 'run' },
      });
      await plant('/rest/v1/fundraisers', {
        id: fundraiserId,
        owner_user_id: userId,
        run_id: runId,
        charity_name: 'Test Charity',
        title: 'Test Fundraiser',
        goal_cents: 100000,
      });
      await plant('/rest/v1/donations', {
        id: donationId,
        fundraiser_id: fundraiserId,
        owner_user_id: userId,
        amount_cents: 5000,
        status: 'pending',
      });

      const completed = {
        id: completedEventId,
        type: 'checkout.session.completed',
        data: {
          object: {
            metadata: { kind: 'donation', donation_id: donationId },
            payment_intent: paymentIntent,
          },
        },
      };

      // (a) completed -> donations paid + payment intent recorded.
      let r = await postStripeEvent(completed);
      if (r.status !== 200 || r.json?.donation_paid !== true) {
        throw new Error(
          `(a) expected 200 donation_paid=true, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      const afterPaid = await readDonation();
      if (
        afterPaid?.status !== 'paid' ||
        afterPaid?.stripe_payment_intent_id !== paymentIntent
      ) {
        throw new Error(`(a) donation not marked paid: ${JSON.stringify(afterPaid)}`);
      }

      // (b) replay the same event id (fresh signature) -> 23505 dedupe ->
      // skipped, and the donation must NOT be re-processed.
      r = await postStripeEvent(completed);
      if (r.status !== 200 || r.json?.skipped !== 'duplicate_event') {
        throw new Error(
          `(b) expected 200 skipped=duplicate_event, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }

      // (c) charge.refunded resolves the donation by payment intent and
      // CAS's paid->refunded.
      r = await postStripeEvent({
        id: refundEventId,
        type: 'charge.refunded',
        data: { object: { payment_intent: paymentIntent } },
      });
      if (r.status !== 200 || r.json?.donation_refunded !== true) {
        throw new Error(
          `(c) expected 200 donation_refunded=true, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      if ((await readDonation())?.status !== 'refunded') {
        throw new Error('(c) donation did not move to refunded');
      }
    } finally {
      for (const id of [completedEventId, refundEventId]) {
        await svc(
          `/rest/v1/webhook_events?provider=eq.stripe&event_id=eq.${id}`,
          { method: 'DELETE' },
        ).then((x) => x.body?.cancel());
      }
      // Deleting the user cascades run -> fundraiser -> donations and the
      // payout account (all FKs on delete cascade to auth.users).
      await svc(`/auth/v1/admin/users/${userId}`, { method: 'DELETE' })
        .then((x) => x.body?.cancel());
    }
  },
});

// ── stripe-events-webhook: the EVENT-ORDER expiry SIDE EFFECT ──────
// The paid-events order ledger (club_events.md P1) is the webhook's other
// status machine and had no positive HTTP coverage. This proves a self-
// signed checkout.session.expired CAS's an event_orders row pending->
// canceled (releasing the soft seat reservation). The webhook is the sole
// service-role writer of event_orders.status, so this is the only place the
// expiry transition can be exercised end-to-end.

Deno.test({
  name: 'stripe-events-webhook: event-order checkout.session.expired ' +
    'CAS pending->canceled',
  ignore: SKIP_DB,
  fn: async () => {
    const email = `stripe-buyer-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.test`;
    const createRes = await svc('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'testtest-ord-1', email_confirm: true }),
    });
    const created = await createRes.json().catch(() => null);
    const userId = created?.id as string | undefined;
    if (!userId) {
      throw new Error(
        `failed to create ephemeral buyer: ${createRes.status} ${JSON.stringify(created)}`,
      );
    }

    const clubId = crypto.randomUUID();
    const eventId = crypto.randomUUID();
    const orderId = crypto.randomUUID();
    const instanceStart = new Date().toISOString();
    const stripeEventId = `evt_ord_exp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

    const plant = async (path: string, row: Record<string, unknown>) => {
      const res = await svc(path, {
        method: 'POST',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify(row),
      });
      const status = res.status;
      await res.body?.cancel();
      if (status >= 300) throw new Error(`failed to plant ${path}: ${status}`);
    };

    try {
      await plant('/rest/v1/clubs', {
        id: clubId,
        owner_id: userId,
        name: 'Order Test Club',
        slug: `order-test-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      });
      await plant('/rest/v1/events', {
        id: eventId,
        club_id: clubId,
        title: 'Order Test Event',
        starts_at: instanceStart,
        author_id: userId,
      });
      await plant('/rest/v1/event_orders', {
        id: orderId,
        event_id: eventId,
        instance_start: instanceStart,
        buyer_user_id: userId,
        host_user_id: userId,
        amount_cents: 2000,
        status: 'pending',
      });

      const r = await postStripeEvent({
        id: stripeEventId,
        type: 'checkout.session.expired',
        data: { object: { metadata: { order_id: orderId } } },
      });
      if (r.status !== 200 || r.json?.canceled !== true) {
        throw new Error(
          `expected 200 canceled=true, got ${r.status} ${JSON.stringify(r.json)}`,
        );
      }
      const read = await svc(
        `/rest/v1/event_orders?id=eq.${orderId}&select=status`,
      );
      const rows = await read.json().catch(() => []);
      if (!Array.isArray(rows) || rows[0]?.status !== 'canceled') {
        throw new Error(
          `event_orders.status did not CAS to canceled: ${JSON.stringify(rows)}`,
        );
      }
    } finally {
      await svc(
        `/rest/v1/webhook_events?provider=eq.stripe&event_id=eq.${stripeEventId}`,
        { method: 'DELETE' },
      ).then((x) => x.body?.cancel());
      // clubs.owner_id has NO on-delete-cascade, so drop the club first
      // (cascades events -> event_orders), then the user.
      await svc(`/rest/v1/clubs?id=eq.${clubId}`, { method: 'DELETE' })
        .then((x) => x.body?.cancel());
      await svc(`/auth/v1/admin/users/${userId}`, { method: 'DELETE' })
        .then((x) => x.body?.cancel());
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
