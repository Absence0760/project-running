/// Pure URL-building helpers for the RevenueCat hosted-checkout flow,
/// split out of `revenuecat.ts` so they carry no `$env/dynamic/public`
/// import and stay node:test-runnable (the env-reading shell can't be
/// imported under `npx tsx --test`). Same split as
/// `live_hub.ts` ↔ `live_hub_helpers.ts`.

/// Build the Pro hosted-checkout URL from a Web Paywall Link base. The
/// Supabase user id is appended as the App User ID path segment
/// (URL-encoded; RevenueCat 404s without it) so the purchase keys to the
/// same identity the webhook sees. `redirect_url`, when supplied, brings
/// the buyer back to the upgrade page after purchase. Returns `null` when
/// the base is empty so the caller can fail closed.
export function buildCheckoutUrl(
	checkoutBase: string,
	userId: string,
	returnUrl?: string,
): string | null {
	const base = checkoutBase.trim().replace(/\/+$/, '');
	if (!base) return null;
	const url = `${base}/${encodeURIComponent(userId)}`;
	if (!returnUrl) return url;
	return `${url}?redirect_url=${encodeURIComponent(returnUrl)}`;
}
