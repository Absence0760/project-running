import { env } from '$env/dynamic/public';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';

import { auth } from './stores/auth.svelte';
import { TIER_LIMITS } from './coach/types';

/// Registry of gated / tier-aware features. Two kinds of entries live
/// here:
///
/// - **Feature gates** (`isLocked`). Pro-only screens — a free user
///   navigating there sees a `<ProGate>` lock-card instead of the
///   feature. None are currently gated this way; the AI Coach used to
///   be but was flipped back to a budget model (free users get
///   `TIER_LIMITS.free.dailyLimit` messages/day, then see the
///   limit-bar; not a hard screen lock) per [decisions.md § 23]
///   (../../../docs/architecture/decisions.md). The set is kept around so a future
///   Pro-only screen is a one-line addition.
///
/// - **Pro perks** — benefits that aren't hidden behind a gate but
///   change shape based on tier (e.g. priority processing, larger
///   context window, higher daily coach-message cap). Not keyed for
///   gating because they're behaviour changes, not screens.
///
/// To add a new gated feature:
///   1. Add an entry to `GATED_FEATURES` with a human-readable label.
///   2. Add the key to `PRO_ONLY_FEATURES`.
///   3. Server-side: check `is_pro()` via RPC before the expensive work,
///      returning `{ error: 'pro_required', feature: '<key>' }` on 403.
///   4. Client-side: wrap the UI entry point with
///      `{#if !isLocked('key')} ... {:else} <ProGate feature="key" /> {/if}`
///   5. Add the feature to `docs/features/paywall.md`.

export const GATED_FEATURES: Record<
	string,
	{ label: string; description: string }
> = {
	ai_coach: {
		label: 'AI Coach',
		// Build the daily-cap numbers from TIER_LIMITS so this string
		// can't drift from the server enforcement values (`handler.ts`
		// reads the same constants).
		description:
			`Personalised training advice from Claude, grounded in your plan and runs. Free users get ${TIER_LIMITS.free.dailyLimit} messages per day; Pro users get ${TIER_LIMITS.pro.dailyLimit}.`,
	},
	priority_processing: {
		label: 'Priority Processing',
		description:
			'Faster response times when the service is under heavy load. Pro requests are routed ahead of the free queue at the rate-limit boundary.',
	},
};

/// Feature keys that are Pro-only. A free user hitting one of these
/// surfaces sees the `<ProGate>` lock-card. Perk-tier keys (e.g.
/// `priority_processing`, `ai_coach`) stay out of this set — they
/// change behaviour, not access. Empty today because every feature is
/// reachable by free users; the AI Coach is rate-limited rather than
/// gated (see [decisions.md § 23]).
const PRO_ONLY_FEATURES = new Set<string>();

/// Client-side dev escape hatch for the UI gate. Mirrors the
/// server-side guard in `/api/coach/+server.ts` but with an independent
/// env var so leaking one doesn't leak the other:
///   1. `import.meta.env.DEV` must be true (vite dev mode, not a build).
///   2. `PUBLIC_SUPABASE_URL` must point at the local stack — bypassing
///      the gate against a real project would mask paywall regressions.
///   3. `PUBLIC_BYPASS_PAYWALL` must be the literal string 'true'.
/// All three AND. Any one falsy → gate stays armed.
///
/// `localStorage.paywall_force_locked === '1'` is an opt-in per-page
/// override used by e2e tests to exercise the locked path even on a
/// dev machine with the bypass on. Gated on `import.meta.env.DEV` so a
/// crafted localStorage entry in production is inert.
function bypassEnabled(): boolean {
	const isLocalSupabase =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') ||
		PUBLIC_SUPABASE_URL.includes('localhost');
	const envBypass =
		import.meta.env.DEV &&
		isLocalSupabase &&
		env.PUBLIC_BYPASS_PAYWALL === 'true';
	if (!envBypass) return false;
	if (
		import.meta.env.DEV &&
		typeof localStorage !== 'undefined' &&
		localStorage.getItem('paywall_force_locked') === '1'
	) {
		return false;
	}
	return true;
}

/// Returns true when the UI should hide the feature behind a `<ProGate>`.
/// Fail-closed: an unknown / loading tier returns true so a transient
/// auth-load doesn't briefly unlock a Pro screen. Dev sessions with
/// `PUBLIC_BYPASS_PAYWALL=true` against local Supabase return false
/// regardless so local iteration on Pro-only surfaces stays unblocked.
export function isLocked(feature: string): boolean {
	if (!PRO_ONLY_FEATURES.has(feature)) return false;
	if (bypassEnabled()) return false;
	return !isPro();
}

/// Whether the signed-in user is on a paying tier. Reads from the auth
/// store's cached profile — callers do not need to await anything.
/// Returns `false` when signed out or when the profile hasn't loaded
/// yet. Server-side code should use the no-arg `is_pro()` RPC instead.
export function isPro(): boolean {
	return auth.isPro;
}

export function featureLabel(feature: string): string {
	return GATED_FEATURES[feature]?.label ?? feature;
}

export function featureDescription(feature: string): string {
	return GATED_FEATURES[feature]?.description ?? '';
}
