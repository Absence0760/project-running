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
  /// A `paid` order whose policy allows a refund: initiate the Stripe refund.
  | 'refund'
  /// A `paid` order whose policy denies a refund (e.g. inside the no-refund
  /// window): nothing to do — the buyer keeps the seat (we don't free a seat
  /// without refunding their money), the caller reports policy_no_refund.
  | 'policy_no_refund'
  /// Terminal / not-cancelable (already refunded, canceled, failed): no-op.
  | 'noop';

/// Decide what the cancel EF should do, given the order's current status and
/// (for a paid order) its refund eligibility. Pure so the branch logic is
/// unit-tested independently of Stripe.
///   pending                         -> release_reservation
///   paid + eligible                 -> refund
///   paid + not eligible             -> policy_no_refund
///   anything else (terminal status) -> noop
export function cancelAction(
  status: string,
  refundEligible: boolean,
): CancelAction {
  if (status === 'pending') return 'release_reservation';
  if (status === 'paid') return refundEligible ? 'refund' : 'policy_no_refund';
  return 'noop';
}
