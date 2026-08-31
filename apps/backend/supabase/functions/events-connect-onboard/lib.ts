/// Pure helpers for the Stripe Connect onboarding Edge Function
/// (events-connect-onboard). Extracted so the param-building +
/// redirect-pinning logic can be unit-tested without booting the
/// Supabase stack or importing the Stripe SDK.
///
/// Keep this file dependency-free — no `Deno.env`, no `createClient`,
/// no `fetch`, no Stripe import. It must stay importable from a
/// `deno test` that runs in milliseconds. All actual Stripe calls live
/// in index.ts; this file only shapes the request params.

/// Params for `stripe.accounts.create`. We onboard hosts as Express
/// accounts (Stripe-hosted dashboard + KYC, the P1 assumption — open
/// question #4 in club_events.md leaves Express-vs-Standard open).
/// `transfers` is the capability destination charges need; `card_payments` is
/// the capability an account must hold to be named as the settlement merchant
/// at all. It does not by itself make the host one — that is `on_behalf_of` on
/// the charge, which events-checkout does not send (see its
/// `buildCheckoutSessionParams`).
export interface AccountCreateParams {
  type: 'express';
  country?: string;
  default_currency?: string;
  capabilities: {
    transfers: { requested: true };
    card_payments: { requested: true };
  };
}

export function buildAccountCreateParams(
  country?: string | null,
  defaultCurrency?: string | null,
): AccountCreateParams {
  const params: AccountCreateParams = {
    type: 'express',
    capabilities: {
      transfers: { requested: true },
      card_payments: { requested: true },
    },
  };
  // Stripe rejects an explicit `undefined`/empty country, so only set
  // the optional fields when the caller supplied a real value.
  if (country) params.country = country;
  if (defaultCurrency) params.default_currency = defaultCurrency;
  return params;
}

/// Params for `stripe.accountLinks.create`. `account_onboarding` is the
/// hosted KYC/bank/tax flow. The buyer never sees this — only the host
/// during their one-time payout setup.
export interface AccountLinkParams {
  account: string;
  type: 'account_onboarding';
  return_url: string;
  refresh_url: string;
}

export function buildAccountLinkParams(
  accountId: string,
  returnUrl: string,
  refreshUrl: string,
): AccountLinkParams {
  return {
    account: accountId,
    type: 'account_onboarding',
    return_url: returnUrl,
    refresh_url: refreshUrl,
  };
}

/// A URL with no origin of its own — a custom scheme, `data:`, `blob:`,
/// `javascript:` — serialises its opaque origin as the literal string `null`,
/// and every such URL serialises to the SAME string. Comparing the
/// serialisations therefore makes any one opaque-origin entry in the allowlist
/// admit every opaque-origin URL there is, including `javascript:`. The
/// sibling `STRAVA_ALLOWED_REDIRECTS` really does carry a custom scheme
/// (`threkir://strava-callback`), and this gate's own comment points an
/// operator at that convention, so the configuration that opens it is one an
/// operator would reach for. `return_url` is caller-supplied and this is the
/// only thing standing between it and Stripe's hosted onboarding page, so a
/// candidate carrying no origin is refused before the allowlist is consulted —
/// which also makes an opaque ENTRY inert, since no origin an allowed URL can
/// have is the string `null`.
const OPAQUE_ORIGIN = 'null';

/// Pin a redirect/return URL against an allowlist of origins, the way
/// strava-import pins STRAVA_ALLOWED_REDIRECTS. `account_onboarding`
/// return/refresh URLs are operator-configured, but routing them through
/// the same gate as the checkout success/cancel URLs keeps the
/// open-redirect defence in one place and fails closed on an empty
/// allowlist (a missed `supabase secrets set` must not silently allow
/// any host).
///
/// Match is by *origin* (scheme + host + port) — a configured origin
/// allows any path under it, which is what return_url needs
/// (`https://app.example.com/settings/payouts?...`). Returns true only
/// when the URL parses and its origin is in the allowlist.
export function validateReturnUrl(url: string, allowlist: readonly string[]): boolean {
  if (allowlist.length === 0) return false;
  let origin: string;
  try {
    origin = new URL(url).origin;
  } catch {
    return false;
  }
  if (origin === OPAQUE_ORIGIN) return false;
  for (const entry of allowlist) {
    let allowedOrigin: string;
    try {
      allowedOrigin = new URL(entry).origin;
    } catch {
      continue;
    }
    if (origin === allowedOrigin) return true;
  }
  return false;
}
