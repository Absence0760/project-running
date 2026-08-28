/// Pure helpers for buyer self-cancel of a paid event registration
/// (events-cancel, club_events.md slice P2). Extracted so the
/// refund-eligibility decision can be unit-tested without Stripe or the
/// Supabase stack.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`,
/// no `fetch`, no Stripe import. The Stripe refund + DB writes live in
/// index.ts; this file only decides.
///
/// The refund-eligibility rule mirrors the web pure helper
/// (apps/web/src/lib/social/paid_registration.ts resolveRefundEligibility)
/// — the same three policies, same cutoffs — so the client preview and the
/// server enforcement can't disagree on whether a cancel is refundable.
/// (Not a registered TS↔Dart parity pair: the Dart side lands with mobile
/// register, P3.)

export type RefundPolicy = 'full_until_start' | 'full_until_24h' | 'no_refund';

export interface RefundEligibility {
  /// Whether a Stripe refund is owed for this cancel.
  eligible: boolean;
  /// Full vs partial. P1/P2 refunds are full-or-nothing per policy (no
  /// proration), so this equals `eligible`; it's a distinct field so a
  /// future partial-refund policy can diverge without changing call sites.
  fullRefund: boolean;
}

/// Resolve whether a buyer self-cancel is refund-eligible, per the event's
/// refund policy.
///   - 'no_refund'        — never eligible.
///   - 'full_until_start' — eligible until the instance start.
///   - 'full_until_24h'   — eligible until 24h before the instance start.
/// Returns not-eligible on an unparseable instance start (fail closed: we
/// don't issue a refund we can't time-bound).
export function resolveRefundEligibility(
  policy: RefundPolicy,
  nowMs: number,
  instanceStartIso: string,
): RefundEligibility {
  const startMs = Date.parse(instanceStartIso);
  if (!Number.isFinite(startMs)) return { eligible: false, fullRefund: false };
  let cutoffMs: number;
  switch (policy) {
    case 'no_refund':
      return { eligible: false, fullRefund: false };
    case 'full_until_start':
      cutoffMs = startMs;
      break;
    case 'full_until_24h':
      cutoffMs = startMs - 24 * 60 * 60 * 1000;
      break;
    default:
      // Unknown policy -> fail closed (no refund) rather than guessing.
      return { eligible: false, fullRefund: false };
  }
  const eligible = nowMs < cutoffMs;
  return { eligible, fullRefund: eligible };
}

export type CancelAction =
  /// A still-`pending` order (no charge captured yet): release the soft
  /// reservation, no Stripe refund.
  | 'release_reservation'
  /// A charged order whose policy allows a refund: initiate the Stripe refund.
  | 'refund'
  /// A charged order whose policy denies a refund (e.g. inside the no-refund
  /// window): nothing to do — the buyer keeps the seat (we don't free a seat
  /// without refunding their money), the caller reports policy_no_refund.
  | 'policy_no_refund'
  /// Terminal / not-cancelable (already refunded, canceled, failed): no-op.
  | 'noop';

/// Decide what the cancel EF should do, given the order's current status and
/// (for a charged order) its refund eligibility. Pure so the branch logic is
/// unit-tested independently of Stripe.
///   pending                             -> release_reservation
///   paid | partially_refunded + eligible-> refund
///   paid | partially_refunded + not     -> policy_no_refund
///   anything else (terminal status)     -> noop
///
/// `partially_refunded` decides EXACTLY as `paid` does, because it is still a
/// held seat: `enforce_paid_order_for_priced_event` accepts it as backing a
/// registration (20270522_001) and the webhook keeps the seat on a partial
/// refund by design. Reading it as terminal instead was a silent money bug —
/// the caller's `.in('status', [...])` had already been widened to select such
/// an order, and the buyer policy in 20270522_001 widened to admit it, so a
/// buyer cancelling a partially-refunded registration reached here, was told
/// `noop`, and the web toast reported success while no refund was created and
/// the seat was never released (decisions § 769). A partial refund is not the
/// buyer giving up their place; it is money coming back on a place they kept.
export function cancelAction(
  status: string,
  refundEligible: boolean,
): CancelAction {
  if (status === 'pending') return 'release_reservation';
  if (status === 'paid' || status === 'partially_refunded') {
    return refundEligible ? 'refund' : 'policy_no_refund';
  }
  return 'noop';
}

/// Shape the `stripe.refunds.create` params for a DESTINATION-charge refund.
///
/// Both flags are load-bearing and Stripe couples them: "If you refund the
/// application fee for a destination charge, you must also reverse the
/// transfer."
///
///   - `reverse_transfer` pulls the host's share back out of their connected
///     account. Without it, "by default the destination account keeps the funds
///     that were transferred to it, leaving the platform account to cover the
///     negative balance from the refund" — so the buyer was made whole out of
///     the PLATFORM's balance and the host kept the whole ticket.
///   - `refund_application_fee` does NOT claw our cut back to us, which is what
///     this call was written believing: it "push[es] the application fee funds
///     back to the connected account". It is the half that leaves the host
///     whole once the transfer above has been reversed off them.
///
/// Together they net every party to zero on a full refund. Set alone, as it was
/// (decisions § 769), the second one pays the host our fee ON TOP of the ticket
/// they already kept, so a cancelled $50 class cost the platform the full $50
/// and paid the host $50 for a class nobody attended.
///
/// No `amount`: Stripe refunds the whole remaining unrefunded balance of the
/// charge, which is what both refundable statuses want — the entire ticket for
/// a `paid` order, and only what is still owed for a `partially_refunded` one.
export function buildRefundParams(paymentIntentId: string) {
  return {
    payment_intent: paymentIntentId,
    refund_application_fee: true,
    reverse_transfer: true,
  };
}
