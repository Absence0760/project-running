/// Pure helpers for the donation checkout Edge Function (donations-checkout).
/// Extracted so the amount-bounds / fee / idempotency / param-shaping logic can
/// be unit-tested without Stripe or the Supabase stack.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`, no
/// `fetch`, no Stripe import. The Stripe Checkout.Session create call lives in
/// index.ts; this file only shapes its params and decides.
///
/// A donation is the thinner cousin of an event checkout: no capacity, no sales
/// window, no seat — a donor (who may be anonymous / logged-out) pays any
/// amount within sane bounds, and the money settles to the fundraiser owner's
/// connected account via the SAME destination charge.

import { computeApplicationFeeCents } from '../events-checkout/lib.ts';

// Re-export so the donation checkout uses the ONE fee math (single source —
// see events-checkout/lib.ts). A charity donation defaults to 0 bps, but the
// plumbing is identical to a paid event.
export { computeApplicationFeeCents };

/// Sane donation bounds in cents. Floor avoids dust charges Stripe would
/// reject; ceiling is a fat-finger / abuse guard ($10,000). A request outside
/// the band is rejected before the Stripe call.
export const MIN_DONATION_CENTS = 100;
export const MAX_DONATION_CENTS = 10_000_00;

/// Donor-supplied free-text caps. The display_name + message are rendered on
/// the public feed; bound their length here so a single donation can't bloat
/// the feed payload or smuggle a wall of text. (XSS is handled at render —
/// the web feed never uses raw {@html}.)
export const MAX_DISPLAY_NAME_LEN = 80;
export const MAX_MESSAGE_LEN = 280;

export type AmountOutcome = 'ok' | 'too_small' | 'too_large' | 'invalid';

/// Validate a requested donation amount against the bounds. Integer cents only
/// — a fractional or non-finite amount is `invalid`.
export function validateDonationAmount(amountCents: unknown): AmountOutcome {
  if (typeof amountCents !== 'number' || !Number.isFinite(amountCents)) return 'invalid';
  if (!Number.isInteger(amountCents)) return 'invalid';
  if (amountCents < MIN_DONATION_CENTS) return 'too_small';
  if (amountCents > MAX_DONATION_CENTS) return 'too_large';
  return 'ok';
}

/// Clamp + trim a donor-supplied free-text field to its cap. Returns null for a
/// missing / blank value so the column stays NULL rather than an empty string.
export function clampText(value: unknown, maxLen: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  return trimmed.slice(0, maxLen);
}

/// Stripe request-idempotency key for the donation Checkout Session create.
///
/// Load-bearing only because the donation id it is built from is now STABLE
/// across a retry: `resolveDonationIntent` resolves the caller's own
/// per-attempt key to the pending donation the first attempt opened, and the
/// second call rebuilds byte-identical params against that same row — so
/// Stripe replays the original session instead of opening a second one.
///
/// It was not stable before (decisions § 769): the id was minted by
/// `crypto.randomUUID()` inside the request, so no later invocation could
/// resolve to the same key and the guard covered the SDK's retry of one HTTP
/// request and nothing more. decisions § 776.
export function donationIdempotencyKey(donationId: string): string {
  return `donations-checkout:${donationId}`;
}

/// The pending donation a client idempotency key may resolve to, as read back
/// from the ledger.
export interface DonationIntentRow {
  id: string;
  status: string;
  fundraiser_id: string;
  amount_cents: number;
  donor_user_id: string | null;
}

/// What this request is asking for, in the terms the resolution compares.
export interface DonationIntentRequest {
  fundraiserId: string;
  amountCents: number;
  donorUserId: string | null;
}

export type DonationIntent =
  | { action: 'open'; }
  | { action: 'resume'; donationId: string }
  | { action: 'conflict'; reason: 'params_changed' | 'already_used' };

/// Decide what a donation checkout carrying a client idempotency key should do.
///
/// The three answers are Stripe's own semantics for a reused key, because this
/// is the same instrument one layer down:
///
///   * no row for the key            -> `open` a new donation,
///   * a PENDING row, same request   -> `resume` it (rebuild the same Stripe
///                                      params against the same donation id, so
///                                      Stripe replays the session already
///                                      open and the donor cannot be charged
///                                      twice),
///   * a row for a DIFFERENT request -> `conflict: params_changed`,
///   * a row that is no longer pending -> `conflict: already_used`.
///
/// The comparison is what makes the key safe to accept from a client. A guessed
/// or replayed key that does not also match the fundraiser, the amount AND the
/// donor resolves to nothing rather than handing the caller someone else's
/// open Checkout Session; guessing a v4 UUID is already infeasible, and this
/// makes the consequence of guessing one nil rather than small.
///
/// `already_used` is deliberately a refusal and not a fresh donation. A key
/// whose row is already `paid` means the donor's client is retrying an attempt
/// that in fact completed — opening a new donation there would charge them a
/// second time, which is the exact failure this whole mechanism exists to
/// prevent. A genuinely new donation carries a genuinely new key.
export function resolveDonationIntent(
  existing: DonationIntentRow | null,
  request: DonationIntentRequest,
): DonationIntent {
  if (existing === null) return { action: 'open' };
  if (
    existing.fundraiser_id !== request.fundraiserId ||
    existing.amount_cents !== request.amountCents ||
    (existing.donor_user_id ?? null) !== request.donorUserId
  ) {
    return { action: 'conflict', reason: 'params_changed' };
  }
  if (existing.status !== 'pending') {
    return { action: 'conflict', reason: 'already_used' };
  }
  return { action: 'resume', donationId: existing.id };
}

/// A type ALIAS, not an interface. Stripe's `MetadataParam` is an index
/// signature (`{ [k: string]: string | number | null }`), and TypeScript
/// gives an object-literal type alias an implicit index signature while
/// an interface gets none — so as an interface this was not assignable
/// to the `metadata` field of the params it is built into, the same
/// shape decisions § 762 found on `delete-account`'s `ThirdPartyOutcomes`.
/// Nothing about the values changed; they were always four strings.
export type DonationCheckoutMetadata = {
  kind: 'donation';
  donation_id: string;
  fundraiser_id: string;
};

export interface BuildDonationSessionArgs {
  amountCents: number;
  currency: string;
  productName: string;
  applicationFeeCents: number;
  ownerAccountId: string;
  successUrl: string;
  cancelUrl: string;
  metadata: DonationCheckoutMetadata;
}

/// Shape the `stripe.checkout.sessions.create` params for a destination-charge
/// donation: the donor's card is charged on the platform account,
/// `application_fee_amount` is the platform's cut (0 for a charity donation by
/// default), and `transfer_data.destination` routes the rest to the fundraiser
/// owner's connected account. `mode: 'payment'` is a one-off charge. No
/// `expires_at` — unlike a seat, a donation holds no reservation that must
/// lapse.
export function buildDonationSessionParams(args: BuildDonationSessionArgs) {
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
      transfer_data: { destination: args.ownerAccountId },
    },
    success_url: args.successUrl,
    cancel_url: args.cancelUrl,
    metadata: args.metadata,
  };
}
