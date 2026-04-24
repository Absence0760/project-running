import { auth } from './stores/auth.svelte';

/// Registry of gated / tier-aware features. Two kinds of entries live
/// here today:
///
/// - **Feature gates** (`isLocked`). Today none of these are truly locked
///   behind Pro — every feature is available to every signed-in user.
///   The registry + gate infrastructure stays in place so a feature can
///   be re-gated by flipping a single return.
///
/// - **Pro perks** — benefits that aren't hidden behind a gate but change
///   shape based on tier. The current perks are **unlimited AI coach
///   messages** (free is capped at 10 / day, enforced server-side in
///   `/api/coach/+server.ts`) and **priority processing** (routing
///   preference during heavy load; marketing claim with per-endpoint
///   enforcement landing over time). These are not keyed in this
///   registry because they're behaviour changes, not gated screens.
///
/// To add a new gated feature:
///   1. Add an entry to this object with a human-readable label + desc.
///   2. Flip `isLocked` so it returns `!isPro()` for the key (or a more
///      specific check).
///   3. Server-side: check `is_user_pro()` via RPC before the expensive
///      work, returning `{ error: 'pro_required', feature: '<key>' }` on
///      403.
///   4. Client-side: wrap the UI entry point with
///      `{#if !isLocked('ai_coach')} ... {:else} <ProGate feature="ai_coach" /> {/if}`
///   5. Add the feature to `docs/paywall.md`.

export const GATED_FEATURES: Record<
	string,
	{ label: string; description: string }
> = {
	ai_coach: {
		label: 'AI Coach',
		description:
			'Personalised training advice from Claude, grounded in your plan and runs. Free users get 10 messages per day; Pro users get unlimited.',
	},
	priority_processing: {
		label: 'Priority Processing',
		description:
			'Faster response times when the service is under heavy load. Pro requests are routed ahead of the free queue at the rate-limit boundary.',
	},
};

/// Returns true when the UI should hide the feature behind a `<ProGate>`.
/// No feature is hidden today — the Pro perks (unlimited coach cap,
/// priority processing) change shape per-tier but don't gate any screen.
/// If a future feature is Pro-only, flip this to return `!isPro()` for
/// that specific key.
export function isLocked(_feature: string): boolean {
	return false;
}

/// Whether the signed-in user is on a paying tier. Reads from the auth
/// store's cached profile — callers do not need to await anything.
/// Returns `false` when signed out or when the profile hasn't loaded
/// yet. Server-side code should use the `is_user_pro(uid)` RPC instead.
export function isPro(): boolean {
	return auth.isPro;
}

export function featureLabel(feature: string): string {
	return GATED_FEATURES[feature]?.label ?? feature;
}

export function featureDescription(feature: string): string {
	return GATED_FEATURES[feature]?.description ?? '';
}
