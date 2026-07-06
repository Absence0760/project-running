/**
 * Fail-closed feature gate for the AI Coach and its half of the Pro storefront.
 *
 * The Coach perks (higher daily cap, bigger token/context budget, AI route
 * descriptions/requests — see docs/features/paywall.md) all hinge on a live
 * Anthropic key. This flag is the client-visible signal for "AI is live": when
 * `PUBLIC_COACH_ENABLED` is not explicitly truthy every Coach entry point hides
 * and the Pro card drops its Coach bullets. Pro itself is sellable when EITHER
 * this flag or route_gen_flag.ts (`PUBLIC_ROUTE_GEN_ENABLED`, the server
 * route-generation perk — decisions §204) is on; with both off the storefront
 * shows a "coming soon" teaser and leads with donations instead. Unset / empty /
 * "false" / "0" → off, matching the rock-bottom deploy where `ANTHROPIC_API_KEY`
 * is unset and `/api/coach` returns 503.
 *
 * The real server gate is the unset key (the handler 503s regardless); this is
 * the client half — it stops the UI advertising a plan it can't deliver. Mirrors
 * the weigh_in_flag.ts fail-closed pattern.
 */
import { env } from '$env/dynamic/public';

export function coachEnabled(): boolean {
	const raw = (env.PUBLIC_COACH_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
