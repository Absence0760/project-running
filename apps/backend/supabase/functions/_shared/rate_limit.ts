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

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  bucket: string,
  max: number,
  windowSeconds: number,
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('check_rate_limit', {
    p_user_id: userId,
    p_bucket: bucket,
    p_max: max,
    p_window_seconds: windowSeconds,
  });

  // If the RPC itself failed, don't deny the user — log and let the
  // request through. Hard-failing on the rate-limit pathway would
  // make a transient DB blip look like an outage.
  if (error || !Array.isArray(data) || data.length === 0) {
    console.warn('check_rate_limit RPC failed; allowing request:', error);
    return null;
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
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('check_rate_limit_tiered', {
    p_user_id: userId,
    p_bucket: bucket,
    p_free_max: freeMax,
    p_pro_max: proMax,
    p_window_seconds: windowSeconds,
  });

  if (error || !Array.isArray(data) || data.length === 0) {
    console.warn('check_rate_limit_tiered RPC failed; allowing request:', error);
    return null;
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
