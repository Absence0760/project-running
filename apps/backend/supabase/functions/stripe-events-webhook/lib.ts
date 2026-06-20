/// Pure helpers for the Stripe Connect events webhook
/// (stripe-events-webhook). Extracted so signature verification, the
/// idempotent order-state machine, and envelope parsing can be unit-
/// tested without the Stripe SDK or the Supabase stack.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`, no
/// `fetch`, no Stripe import. It reuses `hmacHex` + `timingSafeEqual`
/// from _shared/webhook_security.ts (Web Crypto, zero supply-chain
/// surface) so the verifier is testable against constructed fixtures.

import { hmacHex, timingSafeEqual } from '../_shared/webhook_security.ts';
import {
  type CapacityOutcome,
  capacityDecision,
} from '../events-checkout/lib.ts';

// Re-export so callers that only import from the webhook lib get the one
// shared capacity decision (single source of math — see events-checkout/lib.ts).
export { capacityDecision };
export type { CapacityOutcome };

/// Verify a Stripe webhook signature.
///
/// Stripe signs with the `Stripe-Signature` header in the form
/// `t=<unix-seconds>,v1=<hex hmac-sha256>` (there can be multiple v1
/// schemes during a secret rotation, and a `v0` for older schemes which
/// we ignore). The signed payload is the literal string
/// `${t}.${rawBody}`, keyed by the endpoint's signing secret (whsec_…).
///
/// Verification runs on the RAW request bytes — NOT a JSON.parse'd and
/// re-stringified body, which won't round-trip whitespace/key-order and
/// would break every signature.
///
/// Two gates, both required:
///   1. signature — recompute HMAC over `${t}.${rawBody}`, constant-time
///      compare against each `v1` value (any match passes — covers the
///      dual-signature rotation window).
///   2. freshness — reject if `|now - t|` exceeds the tolerance (default
///      5 min, Stripe's recommended default). This is the replay gate: a
///      captured POST replayed later fails even though its HMAC is valid.
export async function verifyStripeSignature(
  rawBody: string,
  sigHeader: string | null,
  secret: string,
  nowMs: number,
  toleranceSec = 300,
): Promise<boolean> {
  if (!sigHeader || !secret) return false;

  const parts = sigHeader.split(',');
  let timestamp: number | null = null;
  const v1Sigs: string[] = [];
  for (const part of parts) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (key === 't') {
      const n = Number.parseInt(value, 10);
      if (Number.isFinite(n)) timestamp = n;
    } else if (key === 'v1') {
      v1Sigs.push(value);
    }
  }

  if (timestamp === null || v1Sigs.length === 0) return false;

  // Freshness — reject a stale (replayed) or wildly future-dated event.
  const ageSec = Math.abs(nowMs / 1000 - timestamp);
  if (ageSec > toleranceSec) return false;

  const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
  for (const candidate of v1Sigs) {
    if (timingSafeEqual(candidate, expected)) return true;
  }
  return false;
}

export interface StripeEventEnvelope {
  id: string;
  type: string;
  data: { object: Record<string, unknown> };
}

/// Parse the Stripe event envelope from the raw body. Returns null on
/// malformed JSON or a missing id/type/data — the caller maps null to a
/// 400 rather than throwing.
export function parseStripeEventEnvelope(rawBody: string): StripeEventEnvelope | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null) return null;
  const obj = parsed as Record<string, unknown>;
  const id = obj.id;
  const type = obj.type;
  const data = obj.data;
  if (typeof id !== 'string' || typeof type !== 'string') return null;
  if (typeof data !== 'object' || data === null) return null;
  const dataObj = (data as Record<string, unknown>).object;
  if (typeof dataObj !== 'object' || dataObj === null) return null;
  return { id, type, data: { object: dataObj as Record<string, unknown> } };
}

export type OrderStatus =
  | 'pending'
  | 'paid'
  | 'refunded'
  | 'partially_refunded'
  | 'failed'
  | 'canceled';

/// The legal compare-and-swap order-status transitions, keyed on the
/// Stripe event type. This is the idempotency backbone: a replayed
/// `checkout.session.completed` finds the order already `paid` (not
/// `pending`) and gets `null` — so it cannot re-grant a slot or
/// double-count revenue even if the webhook_events dedupe were bypassed.
///
///   pending  + checkout.session.completed -> paid
///   pending  + checkout.session.expired   -> canceled
///   paid     + charge.refunded            -> refunded
///   everything else                       -> null (no transition)
///
/// Only `pending` (the unpaid states) and `paid` (the refund) transition;
/// every terminal state (refunded / canceled / failed) is immovable. The
/// paid->refunded arm is the P2 automated-refund coupling: the
/// events-cancel EF initiates the Stripe refund, and this webhook — still
/// the sole, idempotent status writer — flips the order on charge.refunded
/// and releases the seat. A replayed charge.refunded finds the order
/// already `refunded` and gets `null`, so it cannot double-release a seat.
export function orderStatusTransition(
  currentStatus: string,
  eventType: string,
): OrderStatus | null {
  if (currentStatus === 'pending') {
    if (eventType === 'checkout.session.completed') return 'paid';
    if (eventType === 'checkout.session.expired') return 'canceled';
    return null;
  }
  if (currentStatus === 'paid' && eventType === 'charge.refunded') return 'refunded';
  return null;
}

/// Is this Checkout Session a donation (vs a paid-event seat)? The
/// donations-checkout EF stamps metadata.kind='donation'; events-checkout does
/// not set `kind`. One webhook, one secret — the branch is keyed on this.
export function isDonationSession(session: Record<string, unknown>): boolean {
  const md = session.metadata;
  if (typeof md !== 'object' || md === null) return false;
  return (md as Record<string, unknown>).kind === 'donation';
}

/// Extract the donation id from a Checkout Session's metadata (set by
/// donations-checkout). Returns null if absent — the caller treats that as a
/// malformed session it can't confirm.
export function donationIdFromSession(session: Record<string, unknown>): string | null {
  const md = session.metadata;
  if (typeof md !== 'object' || md === null) return null;
  const id = (md as Record<string, unknown>).donation_id;
  return typeof id === 'string' ? id : null;
}

export type DonationStatus = 'pending' | 'paid' | 'refunded' | 'failed' | 'canceled';

/// The legal CAS transitions for a donation, keyed on the Stripe event type.
/// The idempotency backbone (mirrors orderStatusTransition): a replayed
/// `checkout.session.completed` finds the donation already `paid` and gets
/// `null`, so it cannot double-count. A `paid` donation may move to `refunded`
/// (charge.refunded); a still-`pending` donation expires to `canceled`.
///
///   pending + checkout.session.completed -> paid
///   pending + checkout.session.expired   -> canceled
///   paid    + charge.refunded            -> refunded
///   everything else                      -> null
export function donationStatusTransition(
  currentStatus: string,
  eventType: string,
): DonationStatus | null {
  if (currentStatus === 'pending') {
    if (eventType === 'checkout.session.completed') return 'paid';
    if (eventType === 'checkout.session.expired') return 'canceled';
    return null;
  }
  if (currentStatus === 'paid' && eventType === 'charge.refunded') return 'refunded';
  return null;
}

export interface AttendeeRow {
  event_id: string;
  user_id: string;
  instance_start: string;
  order_id: string;
}

/// Extract the attendee row from a Checkout Session's metadata (set by
/// events-checkout). Returns null if any required key is missing — the
/// caller treats that as a malformed session it can't seat.
export function attendeeRowFromSession(
  session: Record<string, unknown>,
): AttendeeRow | null {
  const md = session.metadata;
  if (typeof md !== 'object' || md === null) return null;
  const m = md as Record<string, unknown>;
  const event_id = m.event_id;
  const user_id = m.buyer_user_id;
  const instance_start = m.instance_start;
  const order_id = m.order_id;
  if (
    typeof event_id !== 'string' ||
    typeof user_id !== 'string' ||
    typeof instance_start !== 'string' ||
    typeof order_id !== 'string'
  ) {
    return null;
  }
  return { event_id, user_id, instance_start, order_id };
}
