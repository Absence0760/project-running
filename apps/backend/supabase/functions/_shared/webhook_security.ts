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
  // Force a fresh Uint8Array<ArrayBuffer> view rather than the
  // Uint8Array<ArrayBufferLike> TextEncoder returns, which fails strict
  // BufferSource type-checking under recent Deno/TS lib versions even
  // though the runtime accepts both. /audit/all round-7 2026-05-24.
  const keyBytes: BufferSource =
    typeof secret === 'string' ? enc.encode(secret) : new Uint8Array(secret);
  const bodyBytes: BufferSource =
    typeof body === 'string' ? enc.encode(body) : new Uint8Array(body);
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

/// Header a sender may carry a shared webhook secret in, instead of the
/// URL query string. A query-string secret is recorded verbatim in the
/// platform's request log on every delivery; a header is not, so this is
/// the path to prefer wherever the sender can be configured to use it.
/// Kept here (rather than per-function) so the Edge Function and the Go
/// worker's twin endpoint cannot drift on the name.
export const WEBHOOK_SECRET_HEADER = 'x-webhook-secret';

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
  // A timestamp that is not a number has no age, and every comparison
  // against NaN is false — so the two gates below both fell through to
  // 'ok' and the replay window opened for anything a caller could make
  // unparseable. Both live callers happen to type-check their field
  // first, which is why nothing had noticed; the gate itself must not
  // depend on that. `too_old` rather than a fourth outcome: the callers
  // answer 400 on anything but 'ok', and an unusable stamp is at least
  // as suspect as a stale one.
  if (!Number.isFinite(eventTsMs) || !Number.isFinite(nowMs)) return 'too_old';
  const ageMs = nowMs - eventTsMs;
  if (ageMs > windowMs) return 'too_old';
  if (ageMs < -clockSkewMs) return 'too_future';
  return 'ok';
}

/// RevenueCat assigns `$RCAnonymousID:<random>` to users who haven't
/// signed in. We can't map them to a Supabase profile until they alias,
/// at which point RC fires another event. Returning a 200-skipped here
/// stops RC from retrying.
export function isAnonymousAppUserId(s: string): boolean {
  return typeof s === 'string' && s.startsWith('$RCAnonymousID');
}

/// Whether a dispatched handler's response means the insert-first dedupe row
/// must be given back before returning.
///
/// The dedupe row is written BEFORE the side effect so two concurrent
/// deliveries of one event can't both act. The cost is that a handler which
/// fails owes the row back: every provider here retries on a non-2xx, and the
/// retry would otherwise hit the 23505 path, answer 200 `duplicate_event`, and
/// close the delivery permanently. For `checkout.session.completed` that
/// leaves a charged card with the order stuck `pending`, no seat issued, and no
/// corrective event coming — nothing sweeps a lapsed reservation. For a
/// RevenueCat `NON_RENEWING_PURCHASE` it leaves a paid-for lifetime tier
/// ungranted, and unlike a subscription there is no later renewal to correct
/// it.
///
/// Keyed on 5xx specifically: the handlers return 200 for every outcome that
/// is genuinely final (unknown donation, missing metadata, already-terminal
/// status, an anonymous app user), and reserve 5xx for "we could not complete
/// this — try again".
///
/// It lives beside `validateFreshness` rather than in one webhook's lib
/// because it is the same rule for all three insert-first dedupers, and the
/// one that did not have it is the one that grants a paid tier.
export function shouldReleaseDedupe(status: number): boolean {
  return status >= 500;
}
