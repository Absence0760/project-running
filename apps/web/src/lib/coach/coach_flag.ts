/**
 * Fail-closed feature gate for the AI Coach and the purchasable Pro tier.
 *
 * Every Pro perk is a Coach feature (higher daily cap, bigger token/context
 * budget, AI route descriptions/requests — see docs/features/paywall.md), so
 * when the Coach is off there is nothing a Pro subscription delivers. This flag
 * is the client-visible signal for "AI is live": when `PUBLIC_COACH_ENABLED` is
 * not explicitly truthy the storefront must not sell Pro (it shows a
 * "coming soon" teaser and leads with donations instead). Unset / empty /
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
