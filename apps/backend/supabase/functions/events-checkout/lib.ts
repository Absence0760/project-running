/// Pure helpers for the buyer checkout Edge Function (events-checkout).
/// Extracted so the sales-window / fee / capacity / idempotency logic can
/// be unit-tested without Stripe or the Supabase stack.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`, no
/// `fetch`, no Stripe import. The Stripe Checkout.Session create call
/// lives in index.ts; this file only shapes its params and decides.
///
/// `capacityDecision` is the SINGLE source of capacity math, shared with
/// stripe-events-webhook/lib.ts (it re-exports from here). The precheck
/// at session-create and the recheck at confirm MUST use identical math
/// or the soft-reservation invariant (never oversell) drifts between the
/// two paths — divergence here is a correctness bug, not a style nit.

/// Is the sales window still open? A buyer may register until
/// `salesCloseOffsetMinutes` before the instance start. Offset 0 means
/// "until the class starts". Closed exactly at the boundary (>=) so a
/// 0-offset class is un-buyable the instant it begins.
export function isSalesWindowOpen(
  startsAtMs: number,
  salesCloseOffsetMinutes: number,
  nowMs: number,
): boolean {
  const closeAtMs = startsAtMs - salesCloseOffsetMinutes * 60 * 1000;
  return nowMs < closeAtMs;
}

/// The platform's application fee in cents. Floor (never charge a
/// fractional cent), clamped so it can never exceed the amount (a
/// misconfigured 10000 bps = 100% would otherwise leave the host $0; we
/// still cap at the amount, never above). bps = basis points (1/100th of
/// a percent), so 250 bps = 2.5%.
export function computeApplicationFeeCents(
  amountCents: number,
  platformFeeBps: number,
): number {
  if (amountCents <= 0 || platformFeeBps <= 0) return 0;
  const fee = Math.floor((amountCents * platformFeeBps) / 10000);
  return Math.min(fee, amountCents);
}

/// When a pending order's soft reservation lapses. Matches Stripe's
/// Checkout Session TTL so the slot release lines up with the session
/// expiring (default 15 min — Stripe's minimum expires_at is 30 min from
/// now, but we hold the local reservation for the tighter window and let
/// the webhook's checkout.session.expired release it definitively).
export function reservationExpiry(nowMs: number, ttlMinutes = 15): Date {
  return new Date(nowMs + ttlMinutes * 60 * 1000);
}

export type CapacityOutcome = 'available' | 'full';

/// The one capacity decision. `capacity === null` means unlimited.
/// `goingCount` = confirmed attendees; `pendingNonExpiredCount` = pending
/// orders still holding a soft reservation. A seat is available only when
/// the sum is strictly below capacity.
export function capacityDecision(
  goingCount: number,
  pendingNonExpiredCount: number,
  capacity: number | null,
): CapacityOutcome {
  if (capacity === null) return 'available';
  return goingCount + pendingNonExpiredCount >= capacity ? 'full' : 'available';
}

/// Stripe request-idempotency key for the Checkout Session create call.
/// A buyer double-click or a retried events-checkout must reuse the SAME
/// session instead of opening a second hold — so the key is a stable
/// function of (buyer, event, instance). Different buyer / event /
/// instance → different key.
export function checkoutIdempotencyKey(
  buyerId: string,
  eventId: string,
  instanceStartIso: string,
): string {
  return `events-checkout:${buyerId}:${eventId}:${instanceStartIso}`;
}

export interface CheckoutSessionMetadata {
  event_id: string;
  instance_start: string;
  buyer_user_id: string;
  order_id: string;
}

export interface BuildCheckoutSessionArgs {
  amountCents: number;
  currency: string;
  productName: string;
  applicationFeeCents: number;
  hostAccountId: string;
  successUrl: string;
  cancelUrl: string;
  metadata: CheckoutSessionMetadata;
  expiresAtUnix: number;
}

/// Shape the `stripe.checkout.sessions.create` params for a DESTINATION
/// charge: the buyer's card is charged on the platform account,
/// `application_fee_amount` is the platform's cut, and
/// `transfer_data.destination` routes the rest to the host's connected
/// account — making the HOST the merchant of record, not the platform.
/// `mode: 'payment'` is a one-off charge (not a subscription).
export function buildCheckoutSessionParams(args: BuildCheckoutSessionArgs) {
  return {
    mode: 'payment' as const,
    line_items: [
      {
        price_data: {
          currency: args.currency,
          unit_amount: args.amountCents,
          product_data: { name: args.productName },
        },
        quantity: 1,
      },
    ],
    payment_intent_data: {
      application_fee_amount: args.applicationFeeCents,
      transfer_data: { destination: args.hostAccountId },
    },
    success_url: args.successUrl,
    cancel_url: args.cancelUrl,
    expires_at: args.expiresAtUnix,
    metadata: args.metadata,
  };
}
