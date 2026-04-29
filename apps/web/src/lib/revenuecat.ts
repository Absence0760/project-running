/// RevenueCat web-SDK wrapper.
///
/// The CTA on `/settings/upgrade` calls `startProCheckout()`; if the
/// public RevenueCat key isn't configured (local dev, previews, CI),
/// the wrapper reports `configured = false` and the caller falls back
/// to a "coming soon" toast. Keeps the settings page compilable and
/// testable without a real RC account.
///
/// Production flow:
///   1. `configure()` runs once, keyed by the signed-in Supabase user
///      id so the subscription is portable across browsers / mobile.
///   2. `getOfferings()` pulls the current offerings. We assume a
///      single "default" offering with one package, the monthly Pro
///      plan. Matching the paywall copy on the page.
///   3. `purchase()` presents RC's hosted purchase sheet; on success
///      we tell the caller to refetch the user profile — the
///      `revenuecat-webhook` Edge Function flips `subscription_tier`
///      server-side in the same round trip.

import { env } from '$env/dynamic/public';
import { Purchases, type CustomerInfo, type Package } from '@revenuecat/purchases-js';

// Read via `$env/dynamic/public` rather than `static/public` so an
// unconfigured build (no `PUBLIC_REVENUECAT_WEB_API_KEY`) returns an
// empty string and the wrapper reports `configured = false`, instead
// of failing the SvelteKit build with a 500.
const PUBLIC_REVENUECAT_WEB_API_KEY = env.PUBLIC_REVENUECAT_WEB_API_KEY ?? '';

let instance: Purchases | null = null;
let configuredUserId: string | null = null;

export function isRevenueCatConfigured(): boolean {
	return Boolean(PUBLIC_REVENUECAT_WEB_API_KEY);
}

/// Idempotently configure the SDK for a specific Supabase user id. A
/// later call with a different user id re-configures so tokens don't
/// leak across sign-outs; the SDK supports this via `configure` being
/// called multiple times.
export function configureRevenueCat(userId: string): Purchases | null {
	if (!isRevenueCatConfigured()) return null;
	if (instance && configuredUserId === userId) return instance;
	instance = Purchases.configure(PUBLIC_REVENUECAT_WEB_API_KEY, userId);
	configuredUserId = userId;
	return instance;
}

/// Start the Pro checkout. Caller provides the Supabase user id so the
/// purchase is keyed to the same identity the webhook will see.
/// Returns `{ purchased: boolean }` — `true` means the RC sheet
/// reported a successful purchase; the tier flip on our side happens
/// asynchronously via the webhook, so callers typically refetch the
/// user profile a couple of seconds later.
export async function startProCheckout(userId: string): Promise<{ purchased: boolean }> {
	const rc = configureRevenueCat(userId);
	if (!rc) throw new Error('RevenueCat is not configured on this build');

	const offerings = await rc.getOfferings();
	const pkg = pickProPackage(offerings);
	if (!pkg) throw new Error('No Pro offering available');

	try {
		await rc.purchase({ rcPackage: pkg });
		return { purchased: true };
	} catch (err) {
		// RC surfaces user-cancelled purchases as thrown errors; treat
		// those as a benign "not purchased" so the UI doesn't show a
		// red error toast for a normal dismissal.
		const code = (err as { code?: string } | null)?.code;
		if (code === 'UserCancelledError' || code === 'PurchaseCancelledError') {
			return { purchased: false };
		}
		throw err;
	}
}

function pickProPackage(offerings: { current: { availablePackages: Package[] } | null }): Package | null {
	const current = offerings.current;
	if (!current) return null;
	// Prefer a monthly package if there is one; otherwise take the
	// first available. Matches the "$9.99 / month" copy on the page.
	return (
		current.availablePackages.find((p) => /monthly|month/i.test(p.identifier ?? '')) ??
		current.availablePackages[0] ??
		null
	);
}

/// Pull the management URL from the user's customer info (takes the
/// user to RevenueCat's billing portal where they can cancel or change
/// card). Returns `null` when there's no active subscription or when
/// the SDK isn't configured.
export async function managementUrl(userId: string): Promise<string | null> {
	const rc = configureRevenueCat(userId);
	if (!rc) return null;
	const info = (await rc.getCustomerInfo()) as CustomerInfo & { managementURL?: string | null };
	return info.managementURL ?? null;
}
