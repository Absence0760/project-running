/**
 * Fail-closed feature gate for the Art 9 weigh-in / medical UI
 * (race_director_ops.md P3, decisions §150).
 *
 * The whole weigh-in surface — body-weight entry, medical-hold flag, and the
 * organiser consent action that lets `p_health_consent` reach the upsert RPC —
 * is hidden unless `PUBLIC_WEIGH_IN_ENABLED` is explicitly truthy. Unset /
 * empty / "false" / "0" → off, so health data can't be collected on the web
 * surface until owner + CISO + counsel sign-off flips the flag at deploy time.
 *
 * The DB enforces the real gate too (a crossing's health columns persist only
 * when the checkpoint requires_weigh_in AND the RPC caller passes consent), so
 * this is the client half of a defence-in-depth pair, not the sole guard.
 */
import { env } from '$env/dynamic/public';

export function isWeighInEnabled(): boolean {
	const raw = (env.PUBLIC_WEIGH_IN_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
