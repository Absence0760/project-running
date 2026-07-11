/**
 * Fail-closed feature gate for charity fundraising / donations.
 *
 * The fundraising feature (public /fundraisers/[id] pages, the donate flow, and
 * the "Create fundraiser" affordance attached to runs + club events) can only
 * take money once Stripe Connect is configured AND the owner/CISO/counsel
 * sign-off has landed — see docs/features/fundraising.md + decisions §167/§222.
 * The Stripe keys are server-only, so this flag is the client-visible mirror:
 * when `PUBLIC_FUNDRAISING_ENABLED` is not explicitly truthy every donation
 * surface hides (FundraiserSection renders nothing; the public fundraiser page
 * shows its not-found state) so a user never hits a donate button that would
 * dead-end on the fail-closed Edge Function (503 `stripe_not_configured`).
 *
 * Unset / empty / "false" / "0" → off. Mirrors the coach_flag.ts pattern; local
 * dev + e2e turn it on via `PUBLIC_FUNDRAISING_ENABLED=true` in .env.development.
 */
import { env } from '$env/dynamic/public';

export function fundraisingEnabled(): boolean {
	const raw = (env.PUBLIC_FUNDRAISING_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
