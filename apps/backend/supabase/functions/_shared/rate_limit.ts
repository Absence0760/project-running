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

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';

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

/// Derive a synthetic UUID from the request's client IP. Used for
/// IP-keyed rate-limiting on EFs that accept anon callers (e.g.
/// `clip-public-track`) — the `rate_limits` table is `user_id uuid`,
/// so the key has to fit a UUID. The Cloudflare header is preferred
/// (Supabase's edge runs behind Cloudflare); `x-real-ip` and
/// `x-forwarded-for` are fallbacks for local-dev and self-hosted
/// setups. A missing IP collapses to `0.0.0.0` which buckets every
/// header-less caller together — strict but rare in practice.
///
/// Caller must use the service-role client when calling
/// `check_rate_limit` with this key — the user-context guard added
/// in migration `20260616_001` rejects keys that don't match
/// `auth.uid()`, and a synthetic anon key never matches.
export async function ipBucketKey(req: Request): Promise<string> {
  const ip =
    req.headers.get('cf-connecting-ip') ??
    req.headers.get('x-real-ip') ??
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    '0.0.0.0';
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
