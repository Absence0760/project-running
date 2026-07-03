/// Run with `cd apps/backend && deno test supabase/functions/_shared/rate_limit.test.ts`.
/// (No allow-net flag — pure header + crypto.subtle.)
///
/// Pins the contract on `ipBucketKey` and the response shape of
/// `checkRateLimit` / `checkRateLimitTiered`. The actual SECURITY
/// DEFINER `check_rate_limit` RPC is covered by `pgtap` tests in
/// `supabase/tests/`; what's pinned here is the EF helper's behaviour
/// on top of it — header precedence, UUIDv8 shape, 429 response shape,
/// fail-open vs fail-closed posture.
///
/// ### Why ipBucketKey is high-value to pin
///
/// `ipBucketKey` is the keying function for IP-based rate-limiting on
/// EFs that accept anon callers (`clip-public-track` is the headline
/// caller today). A regression in:
/// - Header precedence (e.g. picking x-forwarded-for over
///   cf-connecting-ip) would let any anonymous user spoof their
///   "IP" by setting x-forwarded-for, bypassing the rate limit.
/// - The UUIDv8 nibble (literal '8' at position 14 of the final
///   UUID) means the synthetic key could collide with a real
///   auth.users row — the SECURITY DEFINER guard added in
///   migration 20260616_001 rejects keys that don't match
///   auth.uid(), and the version-nibble discriminator is what
///   keeps the namespaces disjoint.
/// - Determinism (same IP must hash to the same UUID) is the
///   entire point of a fixed-window rate limit — non-determinism
///   would let an attacker get a fresh window on every request.

import {
  assert,
  assertEquals,
  assertExists,
  assertMatch,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { checkRateLimit, checkRateLimitTiered, ipBucketKey } from './rate_limit.ts';

// ───────────────────── ipBucketKey ─────────────────────

function reqWithHeaders(headers: Record<string, string>): Request {
  return new Request('http://x.test/', { method: 'POST', headers });
}

Deno.test('ipBucketKey: cf-connecting-ip wins over x-real-ip and x-forwarded-for', async () => {
  // Header precedence is the security-critical part. cf-connecting-ip
  // is set by Cloudflare and can't be spoofed; x-forwarded-for can.
  // A regression that flipped the order would let any caller spoof
  // their bucket by injecting x-forwarded-for: 1.2.3.4 on the request.
  const a = await ipBucketKey(
    reqWithHeaders({
      'cf-connecting-ip': '1.1.1.1',
      'x-real-ip': '2.2.2.2',
      'x-forwarded-for': '3.3.3.3',
    }),
  );
  const justCf = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '1.1.1.1' }));
  assertEquals(a, justCf, 'cf-connecting-ip must dominate when present');
});

Deno.test('ipBucketKey: x-real-ip used when cf-connecting-ip is absent', async () => {
  const a = await ipBucketKey(
    reqWithHeaders({
      'x-real-ip': '2.2.2.2',
      'x-forwarded-for': '3.3.3.3',
    }),
  );
  const justReal = await ipBucketKey(reqWithHeaders({ 'x-real-ip': '2.2.2.2' }));
  assertEquals(a, justReal, 'x-real-ip must dominate over x-forwarded-for');
});

Deno.test('ipBucketKey: x-forwarded-for picks the FIRST hop and trims whitespace', async () => {
  // x-forwarded-for is comma-separated; the leftmost value is the
  // original client (the rest are intermediate proxies). A regression
  // that picked the rightmost would group every request through a
  // shared proxy into the same bucket. Trimming matters because RFC
  // 7239 explicitly allows surrounding whitespace in comma lists.
  const a = await ipBucketKey(
    reqWithHeaders({ 'x-forwarded-for': '  4.4.4.4 , 10.0.0.1, 192.168.1.1' }),
  );
  const justFirst = await ipBucketKey(reqWithHeaders({ 'x-forwarded-for': '4.4.4.4' }));
  assertEquals(a, justFirst, 'must pick the leftmost x-forwarded-for entry');
});

Deno.test('ipBucketKey: falls back to 0.0.0.0 when no headers are set', async () => {
  // Header-less callers are rare in practice (Supabase always sets
  // x-forwarded-for at the platform gateway), but local-dev requests
  // and tests can hit this branch. Bucket them ALL together so a
  // header-less attacker can't fan out infinite buckets — strict but
  // correct.
  const a = await ipBucketKey(reqWithHeaders({}));
  const b = await ipBucketKey(reqWithHeaders({}));
  assertEquals(a, b, 'header-less requests must collapse to the same bucket');
});

Deno.test('ipBucketKey: matches the UUID format', async () => {
  // Regex from RFC 4122 with the version nibble being any hex.
  const k = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '1.2.3.4' }));
  assertMatch(
    k,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
});

Deno.test('ipBucketKey: version nibble is literal 8 (UUIDv8 discriminator)', async () => {
  // The version nibble at position 14 of the final string is the only
  // thing keeping the synthetic key from colliding with a real
  // auth.users row (which uses v4 — nibble '4'). A regression here
  // could let an anon caller's bucket collide with a real user.
  const k = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '1.2.3.4' }));
  // Group layout: xxxxxxxx-xxxx-Mxxx-... where M is the version digit.
  assertEquals(k[14], '8', `version nibble must be '8' in ${k}`);
});

Deno.test('ipBucketKey: deterministic — same IP → same UUID', async () => {
  // Fixed-window rate-limiting requires deterministic bucket keys.
  // A regression that included a clock / nonce would silently break
  // every IP-keyed throttle.
  const a = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '8.8.8.8' }));
  const b = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '8.8.8.8' }));
  assertEquals(a, b);
});

Deno.test('ipBucketKey: distinct IPs produce distinct UUIDs', async () => {
  // The hash function (SHA-256) gives extremely high collision
  // resistance — pin that two close-looking IPs don't share a bucket.
  const a = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '1.2.3.4' }));
  const b = await ipBucketKey(reqWithHeaders({ 'cf-connecting-ip': '1.2.3.5' }));
  assert(a !== b, `1.2.3.4 and 1.2.3.5 must bucket differently; both → ${a}`);
});

// ───────────────────── checkRateLimit response shape ─────────────────────

// Tiny mock supabase client with just enough surface to drive the
// helper. Each test parameterises what `rpc()` returns.

interface MockRpcResult {
  data: unknown;
  error: unknown;
}

// deno-lint-ignore no-explicit-any
function mockSupabase(rpcResult: MockRpcResult): any {
  return {
    rpc: (_name: string, _args: unknown) => Promise.resolve(rpcResult),
  };
}

Deno.test('checkRateLimit: returns null on allow', async () => {
  // The contract is "null = allowed, Response = denied". A regression
  // that returned a 200-shape Response on allow would short-circuit
  // every EF — they'd return early with the rate-limit "OK" response
  // instead of doing their work.
  const sb = mockSupabase({
    data: [{ allowed: true, retry_after_seconds: 0 }],
    error: null,
  });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  assertEquals(r, null);
});

Deno.test('checkRateLimit: returns 429 with Retry-After on deny', async () => {
  const sb = mockSupabase({
    data: [{ allowed: false, retry_after_seconds: 42 }],
    error: null,
  });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  assertExists(r);
  assertEquals(r!.status, 429);
  assertEquals(r!.headers.get('Retry-After'), '42');
  assertEquals(r!.headers.get('Content-Type'), 'application/json');
  const body = await r!.json();
  assertEquals(body.error, 'rate_limit_exceeded');
  assertEquals(body.bucket, 'b');
  assertEquals(body.retry_after_seconds, 42);
});

Deno.test('checkRateLimit: Retry-After coerces to at least 1', async () => {
  // Defensive: a zero / negative retry_after from a misbehaving RPC
  // must coerce to 1 so the client backs off at least a second. A
  // 0 would let a tight retry loop hammer the EF.
  const sb = mockSupabase({
    data: [{ allowed: false, retry_after_seconds: 0 }],
    error: null,
  });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  assertExists(r);
  assertEquals(r!.headers.get('Retry-After'), '1');
});

Deno.test('checkRateLimit: fail-open on RPC error returns null', async () => {
  // Default posture — a transient DB blip must not 429 every caller.
  // The user-facing path stays available; the operator sees the
  // console.warn line in logs.
  const sb = mockSupabase({ data: null, error: new Error('boom') });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  assertEquals(r, null, 'fail-open default must let traffic through on RPC error');
});

Deno.test('checkRateLimit: fail-closed on RPC error returns 503 with Retry-After 60', async () => {
  // For destructive / expensive paths (delete-account, export-data
  // zips, OAuth code exchange) the safer default is to 503 the
  // caller. Pin the 60s Retry-After so the client backs off properly.
  const sb = mockSupabase({ data: null, error: new Error('boom') });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600, { failClosed: true });
  assertExists(r);
  assertEquals(r!.status, 503);
  assertEquals(r!.headers.get('Retry-After'), '60');
  const body = await r!.json();
  assertEquals(body.error, 'rate_limit_unavailable');
  assertEquals(body.bucket, 'b');
});

Deno.test('checkRateLimit: empty-array result is treated as RPC failure (fail-open path)', async () => {
  // If the RPC returns no rows (data=[]), there's no row[0] to read.
  // The helper must NOT NPE on `data[0]` and must NOT treat this as
  // "allowed" by default — it's a malformed RPC response, treat as
  // an error per the failure posture. The fail-open default still
  // lets traffic through but logs the warn.
  const sb = mockSupabase({ data: [], error: null });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  assertEquals(r, null, 'empty-array result must hit the failure-posture branch');
});

Deno.test('checkRateLimit: non-array data is treated as RPC failure', async () => {
  // Same as empty-array — defensive against a future RPC contract
  // change. The runtime check `Array.isArray(data)` is what guards.
  const sb = mockSupabase({ data: { allowed: true }, error: null });
  const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600, { failClosed: true });
  assertExists(r);
  assertEquals(r!.status, 503, 'non-array RPC result under fail-closed must 503');
});

// ───────────────────── RPC-error log scrubbing ─────────────────────

// PostgREST errors carry `.details`/`.hint` that can echo the offending
// row's values (the sentry_scrub.ts threat model). The helper must log
// only `.code` + `.message` — a regression back to logging the raw
// error object would ship row fragments to the function-log aggregator
// on every rate-limited EF. /audit/pii-in-logs.

function captureWarn(fn: () => Promise<void>): Promise<string> {
  const logged: unknown[][] = [];
  const orig = console.warn;
  console.warn = (...args: unknown[]) => {
    logged.push(args);
  };
  return fn()
    .then(() => JSON.stringify(logged, (_k, v) => (v === undefined ? '<undefined>' : v)))
    .finally(() => {
      console.warn = orig;
    });
}

const rowEchoingRpcError = {
  message: 'duplicate key value violates unique constraint',
  code: '23505',
  details: 'Key (user_id)=(details-sentinel-uuid) already exists.',
  hint: 'hint-sentinel do not log',
};

Deno.test('checkRateLimit: fail-open RPC-error log carries code+message, never details/hint', async () => {
  const sb = mockSupabase({ data: null, error: rowEchoingRpcError });
  const flat = await captureWarn(async () => {
    await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
  });
  assert(flat.includes('23505'), 'SQLSTATE code must survive for triage');
  assert(flat.includes('duplicate key value'), 'message must survive for triage');
  assert(!flat.includes('details-sentinel-uuid'), `details must be scrubbed; logged: ${flat}`);
  assert(!flat.includes('hint-sentinel'), `hint must be scrubbed; logged: ${flat}`);
});

Deno.test('checkRateLimit: fail-closed RPC-error log carries code+message, never details/hint', async () => {
  const sb = mockSupabase({ data: null, error: rowEchoingRpcError });
  const flat = await captureWarn(async () => {
    await checkRateLimit(sb, 'u-1', 'b', 4, 3600, { failClosed: true });
  });
  assert(flat.includes('23505'));
  assert(!flat.includes('details-sentinel-uuid'), `details must be scrubbed; logged: ${flat}`);
  assert(!flat.includes('hint-sentinel'), `hint must be scrubbed; logged: ${flat}`);
});

Deno.test('checkRateLimitTiered: RPC-error log carries code+message, never details/hint', async () => {
  const sb = mockSupabase({ data: null, error: rowEchoingRpcError });
  const flat = await captureWarn(async () => {
    await checkRateLimitTiered(sb, 'u-1', 'b', 4, 16, 3600);
  });
  assert(flat.includes('23505'));
  assert(!flat.includes('details-sentinel-uuid'), `details must be scrubbed; logged: ${flat}`);
  assert(!flat.includes('hint-sentinel'), `hint must be scrubbed; logged: ${flat}`);
});

Deno.test('rpc-error log tolerates a null error (empty-array RPC result)', async () => {
  // The failure-posture branch is also reached with error=null when the
  // RPC returns no rows — the scrub must not throw on it.
  const sb = mockSupabase({ data: [], error: null });
  const flat = await captureWarn(async () => {
    const r = await checkRateLimit(sb, 'u-1', 'b', 4, 3600);
    assertEquals(r, null);
  });
  assert(flat.length > 0, 'the warn line must still be emitted');
});

// ───────────────────── checkRateLimitTiered ─────────────────────

Deno.test('checkRateLimitTiered: returns null on allow', async () => {
  const sb = mockSupabase({
    data: [{ allowed: true, retry_after_seconds: 0, tier: 'pro' }],
    error: null,
  });
  const r = await checkRateLimitTiered(sb, 'u-1', 'b', 4, 16, 3600);
  assertEquals(r, null);
});

Deno.test('checkRateLimitTiered: deny body includes the resolved tier', async () => {
  // The tier in the response body lets the caller render a paywall
  // CTA when a free user hits the limit ("upgrade to Pro for 4×
  // higher throughput"). Pin that the field is forwarded — a
  // regression that dropped it would render a generic 429 with no
  // upsell path.
  const sb = mockSupabase({
    data: [{ allowed: false, retry_after_seconds: 60, tier: 'free' }],
    error: null,
  });
  const r = await checkRateLimitTiered(sb, 'u-1', 'b', 4, 16, 3600);
  assertExists(r);
  assertEquals(r!.status, 429);
  const body = await r!.json();
  assertEquals(body.tier, 'free');
  assertEquals(body.retry_after_seconds, 60);
});

Deno.test('checkRateLimitTiered: fail-closed posture returns 503 same as untiered', async () => {
  const sb = mockSupabase({ data: null, error: new Error('boom') });
  const r = await checkRateLimitTiered(sb, 'u-1', 'b', 4, 16, 3600, { failClosed: true });
  assertExists(r);
  assertEquals(r!.status, 503);
  assertEquals(r!.headers.get('Retry-After'), '60');
});
