/// Pure helpers for webhook signature + replay protection. Extracted
/// from `revenuecat-webhook` and `strava-webhook` so they can be unit-
/// tested without booting the function host or the Supabase stack.
///
/// Keep this file pure — no `Deno.env`, no `serve`, no network. It must
/// stay importable from a `deno test` that runs in milliseconds.

/// HMAC-SHA256 over `body` with `secret`, returned as lowercase hex.
/// Uses the runtime's built-in Web Crypto API — replaces the
/// `deno.land/x/hmac@v2.0.1` library that revenuecat-webhook used to
/// pull (deno.land/x tags aren't immutable, so a tag rewrite would
/// silently substitute the digest). FIPS-aligned, zero supply-chain
/// surface. /audit/all edge-functions Medium 2026-05-07.
///
/// Accepts string or Uint8Array for both inputs. The string branch
/// UTF-8 encodes via TextEncoder (lossless round-trip for valid UTF-8
/// — every RevenueCat / Strava webhook body is JSON, so the string
/// path is correct for every production caller). Tests that need to
/// pin against byte-exact RFC reference vectors pass Uint8Array so
/// non-ASCII bytes like 0xcd don't get UTF-8-expanded into two bytes.
export async function hmacHex(
  secret: string | Uint8Array,
  body: string | Uint8Array,
): Promise<string> {
  const enc = new TextEncoder();
  const keyBytes =
    typeof secret === 'string' ? enc.encode(secret) : secret;
  const bodyBytes =
    typeof body === 'string' ? enc.encode(body) : body;
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, bodyBytes);
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/// Constant-time string compare. Returns false on length mismatch
/// without short-circuiting on content. The length check itself is
/// observable, but the digest length is fixed (sha256 hex = 64 chars,
/// URL secrets are a known length too) and is not new information.
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

export type FreshnessOutcome = 'ok' | 'too_old' | 'too_future';

/// Bound an event's wall-clock to a (REPLAY_WINDOW, CLOCK_SKEW) window.
///
/// Both webhooks need the same gate: a captured POST replayed weeks
/// later must be rejected even though its HMAC / URL-secret still
/// validates. The window has to be:
///   - wider than the upstream provider's retry envelope (Strava and
///     RevenueCat both retry for ~3 days), so a delivery that failed
///     for a long-ish outage still ingests cleanly,
///   - narrower than the dedupe-row TTL (30 days, set by the
///     cleanup-stale-webhook-events cron in 20260623_001), so a
///     replay can't slip past the dedupe table's pruning horizon.
///
/// Default 7 days threads both. CLOCK_SKEW handles a future-dated
/// event_timestamp from clock drift on the provider side.
export function validateFreshness(
  eventTsMs: number,
  nowMs: number,
  windowMs: number = 7 * 24 * 60 * 60 * 1000,
  clockSkewMs: number = 60 * 1000,
): FreshnessOutcome {
  const ageMs = nowMs - eventTsMs;
  if (ageMs > windowMs) return 'too_old';
  if (ageMs < -clockSkewMs) return 'too_future';
  return 'ok';
}

/// RFC 4122 v1-v5 UUID shape (8-4-4-4-12 hex). RevenueCat's app_user_id
/// should be the Supabase user id, but a misconfiguration could ship
/// their internal Customer-ID format here. Without this guard the
/// downstream `.eq('id', userId)` lookup raises Postgres
/// `22P02 invalid_input_syntax`, which bubbles as a 500 and sends RC
/// into retry storms.
export function isValidUuid(s: string): boolean {
  if (typeof s !== 'string') return false;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

/// RevenueCat assigns `$RCAnonymousID:<random>` to users who haven't
/// signed in. We can't map them to a Supabase profile until they alias,
/// at which point RC fires another event. Returning a 200-skipped here
/// stops RC from retrying.
export function isAnonymousAppUserId(s: string): boolean {
  return typeof s === 'string' && s.startsWith('$RCAnonymousID');
}
