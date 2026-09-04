// What unlocks Pro, and what may be sold. The bypass is three independent
// conditions on both tiers, an unknown tier is locked, and the storefront
// only offers Pro where a Pro perk is actually live.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('BYPASS_PAYWALL gate requires three independent conditions', () => {
	// Reason: BYPASS_PAYWALL is a dev-only escape hatch on the
	// /api/coach SvelteKit endpoint. Production runs in the AWS Lambda
	// wrapper which hardcodes false; this dev path is defence-in-depth
	// "in case the adapter changes." Each of the three conditions
	// closes a different shipped-bypass-by-mistake vector:
	//   1. NODE_ENV != 'production' guards a misbuilt prod artefact.
	//   2. Local Supabase URL guards a dev build pointed at prod.
	//   3. Literal 'true' guards an empty-string env var being truthy.
	// Loosening any one to "OR" rather than "AND" reintroduces the
	// risk and produces a release-build paywall bypass.
	const source = read('src/routes/api/coach/+server.ts');
	const fnMatch = source.match(
		/bypassPaywallEnabled\s*=\s*[^;]*?;/,
	);
	assert.ok(fnMatch, 'Could not locate bypassPaywallEnabled assignment in /api/coach/+server.ts.');
	const expr = fnMatch![0];
	assert.match(expr, /!isProdEnv/, 'BYPASS_PAYWALL must check NODE_ENV != production.');
	assert.match(expr, /isLocalSupabase/, 'BYPASS_PAYWALL must check the Supabase URL is local.');
	assert.match(
		expr,
		/BYPASS_PAYWALL\s*===\s*['"]true['"]/,
		'BYPASS_PAYWALL must check the env var is the literal string "true" — empty / "1" / "yes" must be off.',
	);
	// `&&` joins all three. Reject any `||` between the gates.
	assert.doesNotMatch(
		expr,
		/\|\|/,
		'BYPASS_PAYWALL gate must AND its three conditions, not OR — any single check passing alone is unsafe.',
	);
});

test('Client PUBLIC_BYPASS_PAYWALL gate requires three independent conditions', () => {
	// Reason: the client-side bypass in `$lib/settings/features.ts::bypassEnabled`
	// mirrors the server gate in `/api/coach/+server.ts`. Loosening any
	// one of (vite dev, local Supabase URL, literal 'true' env var) to
	// `||` re-opens the gate in production builds — a vendored
	// PUBLIC_BYPASS_PAYWALL=true env in a misbuilt artefact would
	// silently unlock Pro screens for free users.
	const source = read('src/lib/settings/features.ts');
	const block = source.match(/function bypassEnabled\([\s\S]*?\n\}/);
	assert.ok(block, 'Could not locate bypassEnabled() in features.ts.');
	const body = block![0];
	assert.match(body, /import\.meta\.env\.DEV/, 'bypassEnabled must check import.meta.env.DEV.');
	assert.match(body, /isLocalSupabase/, 'bypassEnabled must check the Supabase URL is local.');
	assert.match(
		body,
		/PUBLIC_BYPASS_PAYWALL\s*===\s*['"]true['"]/,
		'bypassEnabled must check the env var is the literal string "true".',
	);
	const envExpr = body.match(/envBypass\s*=\s*[\s\S]*?;/);
	assert.ok(envExpr, 'envBypass assignment not found.');
	assert.doesNotMatch(envExpr![0], /\|\|/, 'bypassEnabled gate must AND its three conditions, not OR.');
});

test('/settings/upgrade gates the Get Pro CTA on a live perk (never sells a hollow Pro)', () => {
	// Reason: Pro's flagged perks are the AI Coach (PUBLIC_COACH_ENABLED) and
	// server route generation (PUBLIC_ROUTE_GEN_ENABLED — decisions §204).
	// When both are off (rock-bottom deploy) a Pro subscription delivers
	// nothing. The storefront must not sell it: the purchasable "Get Pro" CTA
	// renders only under the proSellable (coachOn || routeGenOn) branch, else
	// a "coming soon" teaser — and each flagged perk's bullet is gated on its
	// own flag so the card never advertises a dead feature. Un-gating this
	// re-introduces a hollow-subscription (consumer-protection / chargeback)
	// risk. See docs/features/paywall.md.
	const page = read('src/routes/settings/upgrade/+page.svelte');
	assert.match(
		page,
		/import \{ coachEnabled \} from '\$lib\/coach\/coach_flag'/,
		'upgrade page must import coachEnabled from the fail-closed coach_flag gate.',
	);
	assert.match(
		page,
		/import \{ routeGenEnabled \} from '\$lib\/routes\/route_gen_flag'/,
		'upgrade page must import routeGenEnabled from the fail-closed route_gen_flag gate.',
	);
	assert.match(
		page,
		/const proSellable = coachOn \|\| routeGenOn/,
		'proSellable must require at least one live perk (coachOn || routeGenOn).',
	);
	assert.match(
		page,
		/\{:else if proSellable\}[\s\S]*?upgrade\.getPro/,
		'the "Get Pro" CTA must live under the {:else if proSellable} branch so it is hidden when every perk is off.',
	);
	assert.match(
		page,
		/\{:else\}[\s\S]*?upgrade\.proComingSoon/,
		'when no perk is live the Pro card must fall back to the upgrade.proComingSoon teaser.',
	);
	assert.match(
		page,
		/\{#if coachOn\}[\s\S]*?upgrade\.proFeatCoachTitle/,
		'the Coach perk bullet must be gated on coachOn so the card never advertises a dead Coach.',
	);
	assert.match(
		page,
		/\{#if routeGenOn\}[\s\S]*?upgrade\.proFeatRouteGenTitle/,
		'the route-generation perk bullet must be gated on routeGenOn so the card never advertises deferred engines.',
	);
	const flag = read('src/lib/coach/coach_flag.ts');
	assert.match(flag, /PUBLIC_COACH_ENABLED/, 'coach_flag must read PUBLIC_COACH_ENABLED.');
	const rgFlag = read('src/lib/routes/route_gen_flag.ts');
	assert.match(rgFlag, /PUBLIC_ROUTE_GEN_ENABLED/, 'route_gen_flag must read PUBLIC_ROUTE_GEN_ENABLED.');
});

test('/app-capabilities.json publishes the same two perk flags the storefront gates on', () => {
	// Reason: the native clients have no server-rendered env, so they learn
	// whether Pro is sellable by reading this prerendered manifest
	// (decisions §466). It must derive from the SAME fail-closed gates the
	// web card reads — a hand-rolled second source of truth would drift and
	// let mobile sell a hollow Pro after web stopped. Mobile fails closed on
	// a missing key, so dropping a field here disables selling rather than
	// enabling it, but the flags must stay wired.
	const manifest = read('src/routes/app-capabilities.json/+server.ts');
	assert.match(
		manifest,
		/import \{ coachEnabled \} from '\$lib\/coach\/coach_flag'/,
		'the capability manifest must derive `coach` from the shared coachEnabled() gate.',
	);
	assert.match(
		manifest,
		/import \{ routeGenEnabled \} from '\$lib\/routes\/route_gen_flag'/,
		'the capability manifest must derive `route_gen` from the shared routeGenEnabled() gate.',
	);
	assert.match(
		manifest,
		/coach: coachEnabled\(\)[\s\S]*?route_gen: routeGenEnabled\(\)/,
		'the manifest body must publish both flags under the `coach` / `route_gen` keys the mobile parser reads.',
	);
	assert.match(
		manifest,
		/export const prerender = true/,
		'the manifest must be prerendered — adapter-static drops any endpoint that is not.',
	);
	// The release workflow must keep it off the immutable-asset sync, or a
	// perk turned off would stay "on" in caches for a year.
	const workflow = read('../../.github/workflows/release-web.yml');
	assert.match(
		workflow,
		/--exclude "app-capabilities\.json"/,
		'app-capabilities.json must be excluded from the year-long immutable S3 sync.',
	);
	assert.match(
		workflow,
		/--include "app-capabilities\.json"/,
		'app-capabilities.json must ride the short-cache S3 sync so a disabled perk propagates.',
	);
});

test('isLocked() fails closed on unknown tier (default = locked)', () => {
	// Reason: a transient auth-store load shouldn't briefly unlock a
	// Pro-only screen. `isLocked(feature)` reads `auth.isPro`, which is
	// false during loading; the implementation must return `!isPro()` so
	// the gate stays armed until the profile lands. Pinned because a
	// subtle refactor (e.g. checking `auth.user.tier === 'free'`)
	// inverts to "default unlocked" when `auth.user` is null.
	const source = read('src/lib/settings/features.ts');
	const block = source.match(/export function isLocked[\s\S]*?\n\}/);
	assert.ok(block, 'Could not locate isLocked() in features.ts.');
	assert.match(
		block![0],
		/!isPro\(\)/,
		'isLocked() must return !isPro() for Pro-only keys so an unknown tier defaults to locked.',
	);
});
