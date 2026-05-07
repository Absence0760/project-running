/// Pure helpers for the RevenueCat tier-mapping logic, extracted so
/// they can be unit-tested without booting Supabase. Keep this file
/// dependency-free — no `Deno.env`, no `createClient`, no I/O.

export type Tier = 'free' | 'pro' | 'lifetime';

/// Activating events from RevenueCat's taxonomy
/// (https://www.revenuecat.com/docs/integrations/webhooks/event-types).
export const ACTIVATING_EVENTS = [
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'PRODUCT_CHANGE',
] as const;

/// Deactivating events. CANCELLATION fires at the end of the billing
/// period (entitlement still active until then), but RC sends both
/// CANCELLATION and EXPIRATION at that point — handling either is fine.
export const DEACTIVATING_EVENTS = [
  'EXPIRATION',
  'CANCELLATION',
] as const;

/// Decide what `billing_issue_at` should become for the given event.
/// Returns:
///   - a Date string when the renewal payment failed (set the flag).
///   - `null` when the payment story resolved one way or the other
///     (clear the flag — recovered via RENEWAL / UNCANCELLATION, or
///     ended via EXPIRATION / CANCELLATION; in either case the flag
///     is no longer informative).
///   - `undefined` for events that don't move the billing-issue
///     dimension (no write).
///
/// This is decoupled from `mapEventToTier` because BILLING_ISSUE
/// must NOT change the tier — RC's grace period keeps the user on
/// Pro until EXPIRATION fires. The two functions answer two
/// independent questions; pinning that separation in code (and in
/// tests) prevents a future refactor from accidentally collapsing
/// them and downgrading users mid-grace-period.
export function mapEventToBillingIssue(
  eventType: string,
  now: Date = new Date(),
): string | null | undefined {
  if (eventType === 'BILLING_ISSUE') return now.toISOString();
  if (
    eventType === 'RENEWAL' ||
    eventType === 'UNCANCELLATION' ||
    eventType === 'EXPIRATION' ||
    eventType === 'CANCELLATION'
  ) {
    return null;
  }
  return undefined;
}

/// Decide what tier (if any) an event should drive the user to.
///
/// `currentTier` is the user's tier at the time the event arrives —
/// matters for deactivating events because a `lifetime` holder might
/// also have had a monthly sub for another entitlement; cancelling that
/// shouldn't reset them. `null` / `undefined` means "we don't know yet"
/// and is treated as not-lifetime (the conservative default — if a
/// fetch fails the safest thing is to apply the deactivation).
///
/// Returns `null` when no tier change should be applied.
export function mapEventToTier(
  eventType: string,
  productId: string | null | undefined,
  currentTier: string | null | undefined,
): Tier | null {
  if ((ACTIVATING_EVENTS as readonly string[]).includes(eventType)) {
    const pid = productId ?? '';
    return pid.includes('lifetime') ? 'lifetime' : 'pro';
  }
  if ((DEACTIVATING_EVENTS as readonly string[]).includes(eventType)) {
    if (currentTier === 'lifetime') return null;
    return 'free';
  }
  return null;
}
