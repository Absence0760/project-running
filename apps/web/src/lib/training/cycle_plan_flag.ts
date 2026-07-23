/**
 * Fail-closed feature gate for the Art 9 cycle/pregnancy-aware plan-adjust UI
 * (persona runner-woman, decisions §231).
 *
 * The whole surface — the reproductive-health inputs on Settings → Account and
 * the "Adjust for cycle / pregnancy" action on the plan-detail page — is hidden
 * unless `PUBLIC_CYCLE_PLANS_ENABLED` is explicitly truthy. Unset / empty /
 * "false" / "0" → off, so this special-category data can't be collected or
 * acted on until owner + CISO + counsel sign-off flips the flag at deploy time.
 *
 * Defence-in-depth: the inputs are ALSO gated on the existing explicit
 * health-data consent (`user_profiles.health_data_consent_at`), so a granted
 * flag alone never collects data without consent.
 */
import { env } from '$env/dynamic/public';

export function isCyclePlansEnabled(): boolean {
	const raw = (env.PUBLIC_CYCLE_PLANS_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
