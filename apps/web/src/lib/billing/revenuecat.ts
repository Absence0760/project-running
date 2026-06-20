/// RevenueCat hosted-checkout wrapper.
///
/// Pro checkout and subscription management both run through RevenueCat's
/// HOSTED redirect surfaces — a Web Paywall Link for purchase and the
/// no-code customer portal for management — rather than the embedded
/// `@revenuecat/purchases-js` SDK. The SDK shipped ~178 KB gzipped into
/// the `/settings/upgrade` bundle for two one-shot redirects; a hosted
/// link does the same job with zero client JS. See
/// docs/features/paywall.md § "Client → RevenueCat SDK" + decisions.md.
///
/// The CTA on `/settings/upgrade` calls `proCheckoutUrl()`; if the link
/// isn't configured (local dev, previews, CI), the wrapper reports
/// `configured = false` and the caller falls back to a "coming soon"
/// toast. Keeps the settings page usable end-to-end without a real RC
/// account.
///
/// Production flow:
///   1. The buyer is redirected to the Web Paywall Link with their
///      Supabase user id appended, so RevenueCat keys the purchase to the
///      same identity the webhook sees (`app_user_id`).
///   2. On success RevenueCat redirects back to `/settings/upgrade`; the
///      `revenuecat-webhook` Edge Function flips `subscription_tier`
///      server-side, and the page refetches the profile on load.
///   3. Management routes to the hosted customer portal (active-sub
///      lookup by email), so no per-user SDK `getCustomerInfo()` call is
///      needed to derive a management URL.
///
/// URL construction lives in the `$env`-free `revenuecat_links.ts` so it
/// stays unit-testable; this module is the thin env-reading shell.

import { env } from '$env/dynamic/public';

import { buildCheckoutUrl } from './revenuecat_links';

// Read via `$env/dynamic/public` rather than `static/public` so an
// unconfigured build returns an empty string and the wrapper reports
// `configured = false`, instead of failing the SvelteKit build with a
// 500.
//
// The checkout base is the project's Web Paywall Link of the form
// `https://pay.rev.cat/<token>`; `<token>` is a public, per-project value
// from the RevenueCat dashboard. The portal base is the no-code customer
// portal link. Both are public by design (they're URLs a browser is
// redirected to), so the PUBLIC_ prefix is correct.
const CHECKOUT_BASE = env.PUBLIC_REVENUECAT_WEB_CHECKOUT_URL ?? '';
const PORTAL_URL = env.PUBLIC_REVENUECAT_WEB_PORTAL_URL ?? '';

export function isRevenueCatConfigured(): boolean {
	return Boolean(CHECKOUT_BASE.trim());
}

/// Build the Pro hosted-checkout URL for a specific Supabase user id.
/// Returns `null` when the checkout link isn't configured on this build,
/// so the caller can fail closed to the "coming soon" placeholder.
export function proCheckoutUrl(userId: string, returnUrl?: string): string | null {
	return buildCheckoutUrl(CHECKOUT_BASE, userId, returnUrl);
}

/// The hosted subscription-management URL. RevenueCat's no-code customer
/// portal authenticates the user by email at the portal itself, so no
/// per-user SDK call is needed. Returns `null` when unconfigured.
export function managementUrl(): string | null {
	return PORTAL_URL.trim() || null;
}
