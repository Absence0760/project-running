/// Pure helpers for the Stripe Connect events webhook
/// (stripe-events-webhook). Extracted so signature verification, the
/// idempotent order-state machine, and envelope parsing can be unit-
/// tested without the Stripe SDK or the Supabase stack.
///
/// Keep this file free of RUNTIME dependencies — no `Deno.env`, no
/// `createClient`, no `fetch`, no Stripe value import. It reuses `hmacHex`
/// + `timingSafeEqual` from _shared/webhook_security.ts (Web Crypto, zero
/// supply-chain surface) so the verifier is testable against constructed
/// fixtures.
///
/// The Stripe import below is TYPE-ONLY and is erased before anything is
/// bundled. That distinction is the whole of decisions § 785: a VALUE
/// import of the SDK takes this function's eszip from 761,148 to 3,373,077
/// bytes, and a type-only one takes it to 761,378 — the 230 bytes of source
/// text added here. Measured with `edge-runtime bundle`, both ways, on this
/// entrypoint. `wiring.test.ts` fails the moment it stops being type-only.

import type Stripe from '../_shared/stripe.ts';
import { hmacHex, timingSafeEqual } from '../_shared/webhook_security.ts';
import {
  type CapacityOutcome,
  capacityDecision,
} from '../events-checkout/lib.ts';

// Re-export so callers that only import from the webhook lib get the one
// shared capacity decision (single source of math — see events-checkout/lib.ts).
export { capacityDecision };
export type { CapacityOutcome };

/// A compile-time assertion that Stripe's own declared shape is assignable
/// to the narrow shape this webhook reads it as. Instantiating it with a
/// `From` that no longer fits reports a TS2344 naming both types — the same
/// negative-assertion mechanism `_shared/stripe.ts` uses, for the same
/// reason: nothing about a field that has been renamed, retyped or made
/// nullable produces a runtime error here. It reads as `undefined`, which on
/// this function means "not a full refund" or "no payment intent" — a
/// silently different order status, not a crash.
type AssertAssignable<From extends To, To> = From;

/// Exactly the Checkout Session fields this webhook reads, spelled with
/// Stripe's own names and types. This is not an approximation of the SDK
/// (decisions § 765 refused one of those for the whole 450-file surface):
/// it is three fields, and the assertion under it is what makes the compiler
/// re-derive it from the SDK on every check.
interface CheckoutSessionSource {
  metadata: Record<string, string> | null;
  payment_intent: string | { id: string } | null;
  payment_status: 'no_payment_required' | 'paid' | 'unpaid';
}
type CheckoutSessionSourceIsStripes = AssertAssignable<
  Stripe.Checkout.Session,
  CheckoutSessionSource
>;

interface ChargeSource {
  payment_intent: string | { id: string } | null;
  refunded: boolean;
  amount: number;
  amount_refunded: number;
}
type ChargeSourceIsStripes = AssertAssignable<Stripe.Charge, ChargeSource>;

/// Exactly the Refund fields the refund-lifecycle handler reads. `status` is
/// declared `string | null` by Stripe itself — not a union — so unlike
/// `payment_status` there is no compile-time check available here and the
/// accepted set has to be spelled out and enforced at runtime.
interface RefundSource {
  id: string;
  payment_intent: string | { id: string } | null;
  status: string | null;
  failure_reason?: string;
}
type RefundSourceIsStripes = AssertAssignable<Stripe.Refund, RefundSource>;

interface ConnectAccountSource {
  id: string;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
}
type ConnectAccountSourceIsStripes = AssertAssignable<Stripe.Account, ConnectAccountSource>;

/// The Stripe event types this webhook acts on, checked against Stripe's own
/// event union. A mistyped comparison string does not fail — it silently
/// matches nothing, and on the sole writer of `event_orders.status` that
/// means a charged card whose order never leaves `pending` and no corrective
/// event coming. Both the dispatcher and the transition tables spell the
/// types from here, so the two cannot drift apart either.
export const STRIPE_EVENT = {
  checkoutCompleted: 'checkout.session.completed',
  checkoutAsyncPaid: 'checkout.session.async_payment_succeeded',
  checkoutAsyncFailed: 'checkout.session.async_payment_failed',
  checkoutExpired: 'checkout.session.expired',
  chargeRefunded: 'charge.refunded',
  refundFailed: 'refund.failed',
  refundUpdated: 'refund.updated',
  chargeRefundUpdated: 'charge.refund.updated',
  accountUpdated: 'account.updated',
} as const satisfies Record<string, Stripe.Event.Type>;

/// The three event types that can carry the news that a refund did not
/// deliver. All three put a `Stripe.Refund` in `data.object`, which is why one
/// handler serves them, and none of them MEANS a failure on its own — that is
/// `refundReversed`'s job, keyed on the refund's own status.
///
///   refund.failed          — what Stripe's own "Handle failed refunds" guide
///                            says it notifies you with. Available on all
///                            refunds (including those with a charge) from API
///                            version 2024-10-28.acacia; the pinned SDK is
///                            stripe@17.5.0, past the 17.3.0 that version
///                            shipped with.
///   refund.updated         — the non-deprecated general refund-lifecycle
///                            event. Carries the `canceled` transition, which
///                            Stripe documents as "a type of refund failure",
///                            and also every benign update (an ARN reference,
///                            metadata) — hence the status gate.
///   charge.refund.updated  — DEPRECATED in Stripe's own refund-events table
///                            ("Listen to refund.updated ... instead"), and
///                            handled only because a webhook endpoint still
///                            pinned to a pre-2024-10-28 API version receives
///                            this one and not the other two. Which version an
///                            endpoint is on is dashboard configuration, not
///                            something this repo can read, so both eras are
///                            handled rather than assumed. decisions § 789.
export const REFUND_LIFECYCLE_EVENTS: readonly string[] = [
  STRIPE_EVENT.refundFailed,
  STRIPE_EVENT.refundUpdated,
  STRIPE_EVENT.chargeRefundUpdated,
];

export function isRefundLifecycleEvent(eventType: string): boolean {
  return REFUND_LIFECYCLE_EVENTS.includes(eventType);
}

/// Metadata as it can actually be read. Stripe declares it
/// `{ [name: string]: string }`, and TypeScript hands back `string` for a
/// key that is not there unless the read is typed to admit it — which is a
/// lie the four required seat keys are read through.
export type StripeMetadata = Readonly<Record<string, string | undefined>>;

export interface CheckoutSession {
  paymentIntentId: string | null;
  paymentStatus: CheckoutSessionSource['payment_status'] | null;
  metadata: StripeMetadata;
}

export interface Charge {
  paymentIntentId: string | null;
  refunded: boolean | null;
  amountCents: number | null;
  amountRefundedCents: number | null;
}

export interface Refund {
  id: string | null;
  paymentIntentId: string | null;
  status: string | null;
  failureReason: string | null;
}

export interface ConnectAccount {
  id: string | null;
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
}

/// Stripe serialises a reference either as the bare id or, when the webhook
/// endpoint is configured to expand it, as the whole object — which is what
/// the SDK's `string | Stripe.PaymentIntent | null` says and a
/// `typeof x === 'string'` read does not. Under the expanded form that read
/// yields null, and null on a refund is answered `missing_payment_intent`
/// with a 200: the refund is recorded at Stripe as delivered, the order keeps
/// its seat, and no retry comes.
function referenceId(value: unknown): string | null {
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && value !== null) {
    const id = (value as { id?: unknown }).id;
    if (typeof id === 'string') return id;
  }
  return null;
}

function metadataOf(value: unknown): StripeMetadata {
  if (typeof value !== 'object' || value === null) return {};
  const out: Record<string, string> = {};
  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    if (typeof entry === 'string') out[key] = entry;
  }
  return out;
}

const PAYMENT_STATUSES: readonly CheckoutSessionSource['payment_status'][] = [
  'no_payment_required',
  'paid',
  'unpaid',
];

/// Narrow one `data.object` from the wire into the fields above. The event
/// body is HMAC-verified, so it is FROM Stripe — but its shape is still
/// whatever arrived, so every field is checked rather than asserted. A value
/// that does not check reads as absent, never as a default that would move
/// money: an unreadable `payment_status` is null, and null is not settled.
export function readCheckoutSession(object: Record<string, unknown>): CheckoutSession {
  const status = object.payment_status;
  return {
    paymentIntentId: referenceId(object.payment_intent),
    paymentStatus: PAYMENT_STATUSES.find((known) => known === status) ?? null,
    metadata: metadataOf(object.metadata),
  };
}

export function readCharge(object: Record<string, unknown>): Charge {
  return {
    paymentIntentId: referenceId(object.payment_intent),
    refunded: typeof object.refunded === 'boolean' ? object.refunded : null,
    amountCents: typeof object.amount === 'number' ? object.amount : null,
    amountRefundedCents: typeof object.amount_refunded === 'number'
      ? object.amount_refunded
      : null,
  };
}

/// Narrow one refund-lifecycle `data.object` from the wire. Same rule as
/// `readCheckoutSession`: every field is checked, and a value that does not
/// check reads as absent. Absent here means "this body does not say the refund
/// failed", which is the direction that changes nothing.
export function readRefund(object: Record<string, unknown>): Refund {
  return {
    id: typeof object.id === 'string' ? object.id : null,
    paymentIntentId: referenceId(object.payment_intent),
    status: typeof object.status === 'string' ? object.status : null,
    failureReason: typeof object.failure_reason === 'string' ? object.failure_reason : null,
  };
}

/// The refund statuses that mean the money did NOT reach the payer and is back
/// with us. `canceled` is in the set because Stripe puts it there: "As
/// cancellations are a type of refund failure, the attributes `failure_reason`
/// and `failure_balance_transaction` are included on the Refund."
///
/// `requires_action` is deliberately absent even though it is one of the ways
/// a bank hands money back: Stripe re-emails the customer for corrected
/// details and the refund is still in flight. So is `pending`. Calling either
/// a failure would move a ledger that is about to settle on its own.
const REVERSED_REFUND_STATUSES: readonly string[] = ['failed', 'canceled'];

/// Whether a refund-lifecycle event says the refund returned no money.
///
/// Fails closed on anything else, INCLUDING a status this build has never
/// heard of. `refund.updated` fires for benign changes far more often than for
/// failures, so a handler that acted on the event type alone would walk a
/// correctly-refunded order back the moment Stripe attached an acquirer
/// reference number to it.
export function refundReversed(refund: Refund): boolean {
  return refund.status !== null && REVERSED_REFUND_STATUSES.includes(refund.status);
}

export function readConnectAccount(object: Record<string, unknown>): ConnectAccount {
  return {
    id: typeof object.id === 'string' ? object.id : null,
    chargesEnabled: object.charges_enabled === true,
    payoutsEnabled: object.payouts_enabled === true,
    detailsSubmitted: object.details_submitted === true,
  };
}

/// Whether the money behind a Checkout Session has actually arrived.
///
/// `checkout.session.completed` does NOT mean paid. Stripe fires it the
/// moment the Session completes, and for a delayed-notification payment
/// method the money is still in flight: `payment_status` is `unpaid` and the
/// outcome arrives days later as `checkout.session.async_payment_succeeded`
/// or `checkout.session.async_payment_failed`. The Checkout Sessions this
/// tier opens declare no `payment_method_types`, so the set is whatever the
/// account has enabled in its dashboard — the delayed methods are one
/// checkbox away and nothing in this repo would notice.
///
/// Fails closed on anything that is not an explicit settlement, including a
/// `payment_status` this build has never heard of: seating an attendee is
/// giving away a place, and giving one away for money that has not arrived
/// is the failure that cannot be undone from here. The CHECK on the other
/// side is `CheckoutSessionSourceIsStripes` — a fourth value added to
/// Stripe's own union fails the typecheck rather than reaching a runtime
/// default.
export function isPaymentSettled(status: CheckoutSession['paymentStatus']): boolean {
  return status === 'paid' || status === 'no_payment_required';
}

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
  | 'refund_failed'
  | 'failed'
  | 'canceled';

/// The legal compare-and-swap order-status transitions, keyed on the
/// Stripe event type. This is the idempotency backbone: a replayed
/// `checkout.session.completed` finds the order already `paid` (not
/// `pending`) and gets `null` — so it cannot re-grant a slot or
/// double-count revenue even if the webhook_events dedupe were bypassed.
///
///   pending            + checkout.session.completed              -> paid
///   pending            + checkout.session.async_payment_succeeded -> paid
///   pending            + checkout.session.expired                 -> canceled
///   pending            + checkout.session.async_payment_failed    -> failed
///   paid               + charge.refunded                          -> refunded
///   refunded           + refund.failed                    -> refund_failed
///   refund_failed      + charge.refunded (full)                   -> refunded
///   everything else                                               -> null
///
/// The two async arms are the delayed-notification half of Checkout: the
/// money behind a completed Session has not necessarily arrived, so a session
/// whose `payment_status` is `unpaid` transitions on nothing and the outcome
/// lands days later as one of those two events. Neither has an arm out of
/// `paid`: with `isPaymentSettled` gating the confirm, no paid order can be
/// waiting on an async outcome, and a paid->failed arm would owe a seat
/// release this table cannot perform.
///
/// Only `pending` (the unpaid states) and `paid` (the refund) transition;
/// every terminal state (refunded / canceled / failed) is immovable. The
/// paid->refunded arm is the P2 automated-refund coupling: the
/// events-cancel EF initiates the Stripe refund, and this webhook — still
/// the sole, idempotent status writer — flips the order on charge.refunded
/// and releases the seat. A replayed charge.refunded finds the order
/// already `refunded` and gets `null`, so it cannot double-release a seat.
///
/// `refund_failed` is the bank rejecting a refund we already acted on
/// (decisions § 789). `charge.refunded` fires when a refund is CREATED, so on a
/// delayed rail the seat is released days before the money's fate is known; if
/// the refund then fails, `refunded` is a claim about money that is provably
/// false. The arm is reachable ONLY from `refunded`, deliberately:
/// `partially_refunded` is a seat-BEARING status on both
/// `enforce_paid_order_for_priced_event` and the buyer-cancel RLS policy
/// (20270522_001), so moving a partly-refunded order out of it would take the
/// roster entry and the cancel affordance away from a buyer who is still
/// attending and lost nothing. That case is logged for reconciliation instead.
///
/// `refund.failed` is the CANONICAL key for "a refund returned no money": the
/// dispatcher normalises the other two refund-lifecycle events onto it once
/// `refundReversed` has read the refund's own status, because neither
/// `refund.updated` nor `charge.refund.updated` means a failure on its own.
export function orderStatusTransition(
  currentStatus: string,
  eventType: string,
  refund: RefundScope = 'full',
): OrderStatus | null {
  if (currentStatus === 'pending') {
    if (
      eventType === STRIPE_EVENT.checkoutCompleted ||
      eventType === STRIPE_EVENT.checkoutAsyncPaid
    ) {
      return 'paid';
    }
    if (eventType === STRIPE_EVENT.checkoutExpired) return 'canceled';
    if (eventType === STRIPE_EVENT.checkoutAsyncFailed) return 'failed';
    return null;
  }
  if (currentStatus === 'paid' && eventType === STRIPE_EVENT.chargeRefunded) {
    return refund === 'partial' ? 'partially_refunded' : 'refunded';
  }
  // A partially-refunded order still holds its seat, so it is NOT terminal: the
  // rest of the money can come back later, and that completing refund has to be
  // able to release the seat. Only a FULL refund moves it on — a second partial
  // returns null so the seat is not released by an instalment.
  if (currentStatus === 'partially_refunded' && eventType === STRIPE_EVENT.chargeRefunded) {
    return refund === 'full' ? 'refunded' : null;
  }
  // The bank reversed the refund: the money is ours again, and the seat this
  // order held is already gone. Reachable ONLY from `refunded` — see the note
  // above the function for why a failed PARTIAL refund transitions on nothing.
  if (currentStatus === 'refunded' && eventType === STRIPE_EVENT.refundFailed) {
    return 'refund_failed';
  }
  // Someone paid the buyer back another way and it landed. `refund_failed` is
  // terminal against everything except the refund actually succeeding, or the
  // ledger would be stuck denying a refund that has now happened. A PARTIAL
  // refund on this order returns null instead of resurrecting the seat-bearing
  // `partially_refunded`: there is no attendee row left to bear.
  if (currentStatus === 'refund_failed' && eventType === STRIPE_EVENT.chargeRefunded) {
    return refund === 'full' ? 'refunded' : null;
  }
  return null;
}

/// Whether a `charge.refunded` returned the WHOLE charge or only part of it.
///
/// Stripe emits `charge.refunded` for a partial refund too — the discriminator
/// is the charge's own `refunded` boolean (true only when fully refunded),
/// with `amount_refunded` vs `amount` as the arithmetic fallback. Treating
/// every `charge.refunded` as full meant a $5 goodwill refund on a $50
/// workshop flipped the order to `refunded` and DELETED the buyer's seat,
/// which `promote_event_waitlist` then handed to someone else — for a
/// registration that is still 90 % paid. `event_orders_status_check` has
/// carried `partially_refunded` since the table was created and nothing ever
/// wrote it.
///
/// Unknown / missing amounts fall back to `full`: that is the historical
/// behaviour, and it is the safe direction for the BUYER (they keep the money
/// and lose the seat) rather than for us.
export type RefundScope = 'full' | 'partial';

export function refundScopeOfCharge(charge: Charge): RefundScope {
  if (charge.refunded === true) return 'full';
  const amount = charge.amountCents;
  const refunded = charge.amountRefundedCents;
  if (charge.refunded === false) {
    // Explicitly not fully refunded. Only call it partial when some money
    // actually moved — a `refunded:false` with no refunded amount is not a
    // refund at all, and must not become a status change.
    return refunded !== null && refunded > 0 ? 'partial' : 'full';
  }
  if (amount === null || refunded === null || refunded <= 0) return 'full';
  return refunded < amount ? 'partial' : 'full';
}

/// Is this Checkout Session a donation (vs a paid-event seat)? The
/// donations-checkout EF stamps metadata.kind='donation'; events-checkout does
/// not set `kind`. One webhook, one secret — the branch is keyed on this.
export function isDonationSession(session: CheckoutSession): boolean {
  return session.metadata.kind === 'donation';
}

/// Extract the donation id from a Checkout Session's metadata (set by
/// donations-checkout). Returns null if absent — the caller treats that as a
/// malformed session it can't confirm.
export function donationIdFromSession(session: CheckoutSession): string | null {
  return session.metadata.donation_id ?? null;
}

export type DonationStatus =
  | 'pending'
  | 'paid'
  | 'partially_refunded'
  | 'refunded'
  | 'refund_failed'
  | 'failed'
  | 'canceled';

/// The legal CAS transitions for a donation, keyed on the Stripe event type.
/// The idempotency backbone (mirrors orderStatusTransition): a replayed
/// `checkout.session.completed` finds the donation already `paid` and gets
/// `null`, so it cannot double-count. A still-`pending` donation expires to
/// `canceled`.
///
///   pending             + checkout.session.completed              -> paid
///   pending             + checkout.session.async_payment_succeeded -> paid
///   pending             + checkout.session.expired                 -> canceled
///   pending             + checkout.session.async_payment_failed    -> failed
///   paid                + charge.refunded (partial)  -> partially_refunded
///   paid                + charge.refunded (full)     -> refunded
///   partially_refunded  + charge.refunded (partial)  -> partially_refunded
///   partially_refunded  + charge.refunded (full)     -> refunded
///   refunded            + refund.failed              -> refund_failed
///   refund_failed       + charge.refunded (full)     -> refunded
///   everything else                                  -> null
///
/// The last-but-one arm is a SELF-transition, and it is the one place this
/// deliberately diverges from `orderStatusTransition`, which returns null for
/// the same input. An order records only a seat, so a second instalment on an
/// already-partially-refunded order has nothing to write and must not release
/// the seat. A donation records an AMOUNT (`refunded_cents`, 20270620_001), so
/// the second instalment does have something to write, and returning null here
/// would leave the charity's thermometer overstating by the difference.
///
/// Before 20270620_001 a partial refund returned null outright, because
/// `fundraiser_totals` summed `amount_cents` filtered on `status = 'paid'` and
/// flipping a partly-returned donation to `refunded` removed its WHOLE amount
/// from the thermometer — a 5 USD goodwill refund on a 500 USD donation erased
/// 500 USD of it. That was the lesser of two lies, not an answer; the ledger
/// can now state the real one. decisions § 769, § 776.
///
/// `refund_failed` mirrors the order ledger and is reachable only from
/// `refunded` for a second reason of its own: `fundraiser_totals` sums
/// `amount_cents - refunded_cents` over ('paid', 'partially_refunded'), so a
/// `refund_failed` row drops out of the thermometer exactly as `refunded`
/// does — correct, because the money is owed back to the donor rather than
/// raised for the charity. Moving a `partially_refunded` donation there
/// instead would remove the WHOLE donation from the total including the part
/// that was never refunded, which is a larger error than the one it fixes; and
/// the only alternative — subtracting the failed instalment from
/// `refunded_cents` — is arithmetic on a running total, which is precisely
/// what § 769 avoided so that an at-least-once redelivery cannot double-apply.
/// decisions § 789.
export function donationStatusTransition(
  currentStatus: string,
  eventType: string,
  refund: RefundScope = 'full',
): DonationStatus | null {
  if (currentStatus === 'pending') {
    if (
      eventType === STRIPE_EVENT.checkoutCompleted ||
      eventType === STRIPE_EVENT.checkoutAsyncPaid
    ) {
      return 'paid';
    }
    if (eventType === STRIPE_EVENT.checkoutExpired) return 'canceled';
    if (eventType === STRIPE_EVENT.checkoutAsyncFailed) return 'failed';
    return null;
  }
  if (currentStatus === 'refunded' && eventType === STRIPE_EVENT.refundFailed) {
    return 'refund_failed';
  }
  if (eventType !== STRIPE_EVENT.chargeRefunded) return null;
  if (currentStatus === 'paid' || currentStatus === 'partially_refunded') {
    return refund === 'full' ? 'refunded' : 'partially_refunded';
  }
  if (currentStatus === 'refund_failed') {
    return refund === 'full' ? 'refunded' : null;
  }
  return null;
}

/// How many cents of a donation have come back in total, as a figure the
/// ledger can store — or null when the charge does not say.
///
/// `charge.amount_refunded` is CUMULATIVE across every refund on the charge,
/// not the size of the refund that raised this event. That is what makes the
/// write idempotent and order-insensitive: two instalments delivered out of
/// order carry 1000 and 3000, and the larger is always the true total.
///
/// A FULL refund is answered with the donation's own `amount_cents` rather
/// than with the charge's figure. `refunded` means the whole donation came
/// back, and the ledger's own column is the only amount the invariant
/// `refunded_cents <= amount_cents` is stated against — reading Stripe's
/// `amount` instead would let a charge whose total differs from ours (a
/// currency or capture discrepancy) write a refund larger than the donation.
///
/// Everything else fails closed to null: a non-integer, negative or absent
/// `amount_refunded` on a partial refund is not a number to put in a money
/// column, and the caller records nothing rather than guessing.
export function refundedCentsOfCharge(
  charge: Charge,
  amountCents: number,
  refund: RefundScope,
): number | null {
  if (!Number.isInteger(amountCents) || amountCents < 0) return null;
  if (refund === 'full') return amountCents;
  const refunded = charge.amountRefundedCents;
  if (refunded === null || !Number.isInteger(refunded) || refunded <= 0) return null;
  return Math.min(refunded, amountCents);
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
export function attendeeRowFromSession(session: CheckoutSession): AttendeeRow | null {
  const { event_id, buyer_user_id, instance_start, order_id } = session.metadata;
  if (!event_id || !buyer_user_id || !instance_start || !order_id) return null;
  return { event_id, user_id: buyer_user_id, instance_start, order_id };
}

/// Whether a dispatched handler's response means the insert-first dedupe row
/// must be given back before returning.
///
/// The dedupe row is written BEFORE the side effect so two concurrent
/// deliveries of one event can't both act. The cost is that a handler which
/// fails owes the row back: Stripe retries on a non-2xx, and the retry would
/// otherwise hit the 23505 path, answer 200 `duplicate_event`, and close the
/// delivery permanently. For `checkout.session.completed` that leaves a
/// charged card with the order stuck `pending`, no seat issued, and no
/// corrective event coming — nothing sweeps a lapsed reservation.
///
/// Keyed on 5xx specifically: the handlers return 200 for every outcome that
/// is genuinely final (unknown donation, missing metadata, already-terminal
/// status), and reserve 5xx for "we could not complete this — try again".
export function shouldReleaseDedupe(status: number): boolean {
  return status >= 500;
}
