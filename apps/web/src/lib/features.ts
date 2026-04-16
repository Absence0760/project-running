import { auth } from './stores/auth.svelte';

/// Registry of gated features. When you add a new paywalled feature,
/// add an entry here and it's automatically gated in both the UI (via
/// `isLocked`) and the server (via the 403 `feature` field).
///
/// To add a new gated feature:
///   1. Add an entry to this object with a human-readable label + desc.
///   2. Server-side: check `subscription_tier` or call `is_pro()` RPC
///      before the expensive work, returning `{ error: 'pro_required',
///      feature: '<key>' }` on 403.
///   3. Client-side: wrap the UI entry point with
///      `{#if !isLocked('ai_coach')} ... {:else} <ProGate feature="ai_coach" /> {/if}`
///   4. Add the feature to `docs/paywall.md`.

export const GATED_FEATURES: Record<
	string,
	{ label: string; description: string }
> = {
	ai_coach: {
		label: 'AI Coach',
		description:
			'Get personalised training advice powered by Claude, grounded in your actual runs and plan.',
	},
	// Future gated features go here. Examples:
	// training_plans: { label: 'Training Plans', description: '...' },
	// live_spectator: { label: 'Live Spectator', description: '...' },
	// advanced_analytics: { label: 'Advanced Analytics', description: '...' },
};

/// Returns true when the feature requires a subscription the user
/// doesn't have. Always returns false when `BYPASS_PAYWALL` is active
/// on the server (but that's a server check — client-side we just
/// read the user's tier).
export function isLocked(feature: string): boolean {
	if (!(feature in GATED_FEATURES)) return false;
	return !auth.isPro;
}

export function featureLabel(feature: string): string {
	return GATED_FEATURES[feature]?.label ?? feature;
}

export function featureDescription(feature: string): string {
	return GATED_FEATURES[feature]?.description ?? '';
}
