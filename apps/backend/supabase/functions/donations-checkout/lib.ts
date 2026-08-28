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
/// Scoped to ONE invocation, and only that. The donation id it is built from is
/// minted by `crypto.randomUUID()` inside the request, so there is no "same
/// row" for a later call to resolve to: the key makes the SDK's own retry of
/// that single HTTP request safe and provides no dedupe across invocations,
/// which is what this was documented as doing. A donor double-click therefore
/// opens two sessions against two pending rows; the unpaid one lapses to
/// `canceled` on `checkout.session.expired`, but a donor who completes both is
/// charged twice. events-checkout avoids that by resolving a live hold first
/// (`resolveHold`) — a donation has no seat to hold and repeat giving is
/// legitimate, so the same treatment is a product decision rather than an
/// obvious fix. decisions § 769.
export function donationIdempotencyKey(donationId: string): string {
  return `donations-checkout:${donationId}`;
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
