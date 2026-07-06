/**
 * Fail-closed feature gate for server-side route generation (a Pro perk —
 * decisions §204).
 *
 * The real server gate is env presence: with GRAPH_CYCLE_URL + GRAPHHOPPER_URL
 * unset the generate endpoint answers 501 before it ever checks the caller's
 * tier, and the client quietly falls back to its in-browser heuristic. This
 * flag is the client half — it stops the UI *advertising* the perk (the
 * /routes/new upsell, the Pro-card bullet, the storefront's sellable state)
 * on a deploy whose engines are deferred (rock-bottom AND Lean both defer
 * them, deployment_lean.md). Unset / empty / "false" / "0" → off. Mirrors
 * coach_flag.ts; set PUBLIC_ROUTE_GEN_ENABLED=true only once the engines are
 * actually standing.
 */
import { env } from '$env/dynamic/public';

export function routeGenEnabled(): boolean {
	const raw = (env.PUBLIC_ROUTE_GEN_ENABLED ?? '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
}
