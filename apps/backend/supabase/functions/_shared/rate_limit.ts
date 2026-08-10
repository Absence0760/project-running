/// Per-user rate-limit helper for Edge Functions.
///
/// Calls the SECURITY DEFINER `check_rate_limit` function (migration
/// `20260604_001_rate_limits.sql`), which atomically increments a
/// fixed-window counter and returns whether the call should proceed.
/// On denial the helper returns a 429 `Response` with a `Retry-After`
/// header so the caller can `return` it directly:
///
///   const denied = await checkRateLimit(supabase, user.id, 'parkrun-import', 4, 3600);
///   if (denied) return denied;
///
/// On allow it returns null. EFs that don't have a user.id (cron-only
/// or service-role) shouldn't call this — the rate-limit table is
/// keyed on user_id.
///
/// **Failure posture.** By default the helper fails open on RPC error
/// (a transient DB blip lets the request through rather than 429-ing
/// every caller). Pass `{ failClosed: true }` for destructive or
/// expensive paths where letting traffic through on RPC failure is
/// worse than the false-positive denial — `delete-account`,
/// `export-data` heavy zips, OAuth code exchange. Fail-closed returns
/// 503 with a `Retry-After: 60` so the client can back off and retry.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';

export interface RateLimitOpts {
  /// When the rate-limit RPC itself errors, return 503 instead of
  /// allowing the request through. Use on destructive / expensive
  /// paths. Default false.
  failClosed?: boolean;
}

/// Log-safe projection of a Supabase/PostgREST error: `.code` +
/// `.message` only. `.details`/`.hint` can echo the offending row's
/// values (the sentry_scrub.ts threat model) and must never reach the
/// function-log aggregator. Mirrors `supabaseErrorFields` in the web
/// coach handler. /audit/pii-in-logs.
function supabaseErrorFields(
  error: unknown,
): { code: string | undefined; message: string | undefined } {
  const e = error as { code?: string; message?: string } | null | undefined;
  return { code: e?.code, message: e?.message };
}

function rpcErrorResponse(bucket: string, error: unknown, failClosed: boolean): Response | null {
  if (!failClosed) {
    console.warn('check_rate_limit RPC failed; allowing request:', supabaseErrorFields(error));
    return null;
  }
  console.warn(
    'check_rate_limit RPC failed; rejecting fail-closed request:',
    supabaseErrorFields(error),
  );
  return new Response(
    JSON.stringify({
      error: 'rate_limit_unavailable',
      bucket,
      retry_after_seconds: 60,
    }),
    {
      status: 503,
      headers: {
        'Content-Type': 'application/json',
        'Retry-After': '60',
      },
    },
  );
}

export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  bucket: string,
  max: number,
  windowSeconds: number,
  opts: RateLimitOpts = {},
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('check_rate_limit', {
    p_user_id: userId,
    p_bucket: bucket,
    p_max: max,
    p_window_seconds: windowSeconds,
  });

  if (error || !Array.isArray(data) || data.length === 0) {
    return rpcErrorResponse(bucket, error, opts.failClosed === true);
  }

  const row = data[0] as { allowed: boolean; retry_after_seconds: number };
  if (row.allowed) return null;

  const retryAfter = Math.max(1, row.retry_after_seconds | 0);
  return new Response(
    JSON.stringify({
      error: 'rate_limit_exceeded',
      bucket,
      retry_after_seconds: retryAfter,
    }),
    {
      status: 429,
      headers: {
        'Content-Type': 'application/json',
        'Retry-After': String(retryAfter),
      },
    },
  );
}

/// The header the deployment's own edge sets, and the ONLY one trusted
/// to name the client. Hosted Supabase runs behind Cloudflare, which
/// overwrites `cf-connecting-ip` on every request, so a client cannot
/// forge it. Self-hosted / non-Cloudflare deployments override this
/// with the header their own reverse proxy overwrites (`x-real-ip` for
/// a typical nginx front end).
const DEFAULT_TRUSTED_IP_HEADER = 'cf-connecting-ip';

/// Bucket for callers whose IP the trusted header did not establish.
/// It is a single shared bucket ON PURPOSE: keying an unidentified
/// caller off anything they control (an `x-forwarded-for` element, the
/// header value itself) hands them a fresh window per value, which is
/// not a rate limit at all. Sharing one bucket is the fail-closed
/// choice — the worst case is that legitimate header-less callers
/// contend with each other.
const UNKNOWN_IP_BUCKET = 'unknown';

export function trustedIpHeaderName(): string {
  const configured = Deno.env.get('TRUSTED_CLIENT_IP_HEADER')?.trim().toLowerCase();
  return configured ? configured : DEFAULT_TRUSTED_IP_HEADER;
}

/// Accept a value only if it is a single, plausible IP literal. A comma
/// means a forwarded chain rather than one address, which the trusted
/// header never carries — treating the leftmost element as the client
/// is the classic spoof, so the whole value is discarded instead.
function trustedClientIp(raw: string | null): string | null {
  if (raw === null) return null;
  const value = raw.trim().toLowerCase();
  if (value.length === 0 || value.length > 45 || value.includes(',')) return null;
  const ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/;
  const ipv6 = /^[0-9a-f:]+$/;
  if (!ipv4.test(value) && !ipv6.test(value)) return null;
  return value;
}

/// Derive a synthetic UUID from the request's client IP. Used for
/// IP-keyed rate-limiting on EFs that accept anon callers (e.g.
/// `clip-public-track`) — the `rate_limits` table is `user_id uuid`,
/// so the key has to fit a UUID.
///
/// Only `trustedIpHeaderName()` is read. The earlier `x-real-ip` /
/// leftmost-`x-forwarded-for` fallbacks were attacker-controlled: on
/// any deployment not fronted by Cloudflare, a caller set them per
/// request and minted a fresh window each time. Anything the trusted
/// header doesn't establish collapses into `UNKNOWN_IP_BUCKET`.
///
/// Caller must use the service-role client when calling
/// `check_rate_limit` with this key — the user-context guard added
/// in migration `20260616_001` rejects keys that don't match
/// `auth.uid()`, and a synthetic anon key never matches.
export async function ipBucketKey(req: Request): Promise<string> {
  const ip = trustedClientIp(req.headers.get(trustedIpHeaderName())) ?? UNKNOWN_IP_BUCKET;
  const data = new TextEncoder().encode(`anon-rate-limit-v1:${ip}`);
  const hash = await crypto.subtle.digest('SHA-256', data);
  const hex = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  // UUIDv8-shape (literal '8' in the version nibble) so the synthetic
  // key can never collide with a real auth.users row.
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-8${hex.slice(13, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/// Tier-aware variant. Picks between `freeMax` and `proMax` based on
/// the caller's `user_profiles.subscription_tier`. Single SQL round
/// trip — the function does the tier lookup + the window check in
/// one transaction (migration 20260605_001).
///
///   const denied = await checkRateLimitTiered(supabase, user.id,
///     'strava-import:sync', /* free */ 4, /* pro */ 16, 3600);
///   if (denied) return denied;
///
/// On allow returns null. On deny returns 429 with Retry-After.
/// Pro / lifetime users get the higher ceiling; everyone else
/// (including missing-profile rows) gets the free ceiling — the
/// conservative default if the RevenueCat sync drifts.
export async function checkRateLimitTiered(
  supabase: SupabaseClient,
  userId: string,
  bucket: string,
  freeMax: number,
  proMax: number,
  windowSeconds: number,
  opts: RateLimitOpts = {},
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('check_rate_limit_tiered', {
    p_user_id: userId,
    p_bucket: bucket,
    p_free_max: freeMax,
    p_pro_max: proMax,
    p_window_seconds: windowSeconds,
  });

  if (error || !Array.isArray(data) || data.length === 0) {
    return rpcErrorResponse(bucket, error, opts.failClosed === true);
  }

  const row = data[0] as {
    allowed: boolean;
    retry_after_seconds: number;
    tier: string;
  };
  if (row.allowed) return null;

  const retryAfter = Math.max(1, row.retry_after_seconds | 0);
  return new Response(
    JSON.stringify({
      error: 'rate_limit_exceeded',
      bucket,
      tier: row.tier,
      retry_after_seconds: retryAfter,
    }),
    {
      status: 429,
      headers: {
        'Content-Type': 'application/json',
        'Retry-After': String(retryAfter),
      },
    },
  );
}
