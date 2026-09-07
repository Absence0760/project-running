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
 * this is the client half of a defence-in-depth pair, not the sole guard. That
 * other half is measured by
 * `apps/backend/supabase/tests/weigh_in_health_gate_test.sql`, which covers all
 * four health columns and the merge branch no client can reach; naming it here
 * is the point, because a claim about a guard nobody can find is a claim that
 * goes unpinned (decisions §1497).
 *
 * The mobile twin `apps/mobile_android/lib/weigh_in_flag.dart` reads
 * `WEIGH_IN_GATE`, NOT the dropped-prefix `WEIGH_IN_ENABLED` the other three
 * deploy gates would lead you to expect. The stems differ, so an operator who
 * has set this key has NOT flipped the phone's Art 9 surface, and vice versa;
 * `deploy_gate_names_test.dart` re-measures both the exception and the fact
 * that both headers state it (decisions §1354).
 */
import { env } from '$env/dynamic/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function isWeighInEnabled(): boolean {
	return isTruthyFlagValue(env.PUBLIC_WEIGH_IN_ENABLED);
}
