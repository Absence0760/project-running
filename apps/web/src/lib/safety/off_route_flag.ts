/**
 * Fail-closed deploy gate for the off-route → auto-notify-contact safety
 * tie-in (docs/features/safety.md, persona-woman).
 *
 * The whole surface — the "Off-route alert" toggle on `/settings/safety` and
 * (on mobile) the run-screen trigger that calls `escalate_run_off_route` — is
 * hidden/inert unless `PUBLIC_OFF_ROUTE_ESCALATION_ENABLED` is explicitly
 * truthy. Unset / empty / "false" / "0" → off, so a runner's off-route
 * departure can't auto-email a contact until owner + CISO + counsel sign-off
 * flips the flag at deploy time.
 *
 * Defence-in-depth: the escalation ALSO requires the user's explicit
 * `safety_off_route_alerts` opt-in pref (default off) AND ≥1 confirmed safety
 * contact AND an active live broadcast — so a granted flag alone never
 * notifies anyone who hasn't opted in.
 */
import { env } from '$env/dynamic/public';
import { offRouteEscalationEnabled } from './off_route_alert';

export function isOffRouteEscalationEnabled(): boolean {
	return offRouteEscalationEnabled(env.PUBLIC_OFF_ROUTE_ESCALATION_ENABLED);
}
