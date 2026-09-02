/**
 * Production build-env guard — sibling of `env_isolation.mjs`. Where
 * that script refuses dev environments configured against prod
 * endpoints, this one refuses production builds configured against
 * placeholder or local endpoints. Both rules exist because the
 * default value for missing env vars in CI is "empty string", which
 * silently bakes a broken config into the static artifact.
 *
 * Rules enforced for a production build:
 *   - PUBLIC_SUPABASE_URL must PARSE as an https URL on a public host.
 *     Empty, unparseable, plaintext http, `placeholder.supabase.co`,
 *     and any loopback / private / link-local / dotless host all abort
 *     the build. Without this guard, a missing secret in the release
 *     workflow would deploy a static site whose `entries()` calls
 *     return [] (the og:image + share-page prerender then ships
 *     without any prerendered ids), and our handleUnseenRoutes: 'warn'
 *     config quietly accepts the empty set rather than failing loud.
 *
 *     This rule used to be written as "a real https://*.supabase.co
 *     URL" and implemented as two deny-lists, which let through every
 *     misconfiguration that was not on them: a bare project ref, a
 *     `postgresql://user:password@…` connection string (Vite inlines
 *     PUBLIC_* into every client bundle, so that one publishes a
 *     database password), plaintext `http://…supabase.co`, a Docker
 *     service host like `http://kong:8000`, a LAN address, and the
 *     literal `TODO-set-me`. All six are refused now (decisions § 774).
 *     `*.supabase.co` is deliberately NOT required — a self-hosted
 *     Supabase behind a custom domain is a legitimate prod config, and
 *     a guard has to enforce the rule it can actually state.
 *   - PUBLIC_SUPABASE_ANON_KEY must be non-empty.
 *   - PUBLIC_MAPTILER_KEY must be non-empty. Used by the og:image
 *     PNG renderer at prerender time and by the maplibre tile
 *     source at runtime; an empty key bakes broken map / share-
 *     image URLs into every public route + run page.
 *   - PUBLIC_REVENUECAT_WEB_CHECKOUT_URL must be non-empty — but only
 *     when Pro is sellable, i.e. PUBLIC_COACH_ENABLED or
 *     PUBLIC_ROUTE_GEN_ENABLED is truthy (Pro's two perks, decisions
 *     §204). With both flags off (the rock-bottom tier,
 *     deployment_lean.md) /settings/upgrade deliberately shows the
 *     "coming soon" teaser instead of selling, so an empty checkout
 *     link is the intended config, not a broken one.
 *
 * NOT enforced (intentional):
 *   - PUBLIC_REVENUECAT_WEB_PORTAL_URL — the manage-subscription portal
 *     is optional. An empty value degrades the "Manage subscription"
 *     button to a "manage where you started it" hint rather than
 *     breaking the page.
 *   - PUBLIC_SENTRY_DSN — error reporting is optional. An empty DSN
 *     disables Sentry rather than breaking anything; small projects
 *     ship without it deliberately.
 *
 * The CLI below is invoked by the release-web.yml workflow as a
 * pre-build step, and only there: it asserts about a RELEASE env, and
 * CI has placeholders by design (`build-web` compiles against
 * `placeholder.supabase.co`, which this guard exists to refuse). What
 * the required `CI gate` holds is the `check_production_env.test.mjs`
 * suite — it covers the matcher and spawns this CLI against crafted
 * envs — from the `env-isolation` job of ci.yml (decisions § 862).
 */

import { isTruthyFlagValue } from '../src/lib/core/env_flag.ts';

const PLACEHOLDER_HOST_RE = /\bplaceholder\.supabase\.co\b/i;

/// Hosts that exist only inside a developer's machine or network. A production
/// bundle is served to browsers on the public internet, so any of them means
/// the release picked up a dev value.
const PRIVATE_HOST_RE =
	/^(?:localhost|.*\.localhost|.*\.local|.*\.internal|host\.docker\.internal|127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|169\.254\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|\[?::1\]?)$/i;

/**
 * Why this value cannot be a production Supabase URL, or null if it can be.
 *
 * @param {string} url
 * @returns {string | null}
 */
export function productionUrlProblem(url) {
	/** @type {URL} */
	let parsed;
	try {
		parsed = new URL(url);
	} catch {
		return 'Not a URL. A bare project ref or a placeholder string inlines into every client bundle as a broken endpoint.';
	}
	// Host before scheme: a dev value is far more often `http://127.0.0.1` than
	// a plaintext public host, and "points at a loopback host" is the diagnosis
	// that names what the operator actually did.
	if (PLACEHOLDER_HOST_RE.test(parsed.hostname)) {
		return 'Looks like the CI bundle-budget placeholder (`placeholder.supabase.co`). The release workflow needs the real prod URL.';
	}
	if (PRIVATE_HOST_RE.test(parsed.hostname)) {
		return 'Points at a loopback / private / emulator host. Production builds must use a remotely reachable Supabase URL.';
	}
	if (!parsed.hostname.includes('.')) {
		return 'Host has no dot, so it resolves only inside a container network (a Docker service name such as `kong`). Production builds must use a publicly resolvable host.';
	}
	if (parsed.protocol !== 'https:') {
		return `Scheme is \`${parsed.protocol}\`, not https. Vite inlines PUBLIC_* into the client bundle, so a plaintext endpoint ships to every browser — and a \`postgresql://\` connection string would publish the database password with it.`;
	}
	return null;
}

/// What a finding may print. The guard reports the value it refused, and one
/// of the values it now refuses is a `postgresql://user:password@…` connection
/// string pasted into the wrong secret — which must not be echoed into a CI
/// log on its way to being rejected.
/**
 * @param {string} url
 * @returns {string}
 */
export function redactCredentials(url) {
	try {
		const parsed = new URL(url);
		if (!parsed.username && !parsed.password) return url;
		if (parsed.username) parsed.username = '***';
		if (parsed.password) parsed.password = '***';
		return parsed.toString();
	} catch {
		return url;
	}
}

/**
 * @typedef {{ envVar: string; value: string; reason: string }} Finding
 * @typedef {{ ok: boolean; findings: Finding[] }} GuardResult
 */

/**
 * @param {Record<string, string | undefined>} env
 * @returns {GuardResult}
 */
export function checkProductionEnv(env) {
	/** @type {Finding[]} */
	const findings = [];

	const url = String(env.PUBLIC_SUPABASE_URL ?? '').trim();
	if (!url) {
		findings.push({
			envVar: 'PUBLIC_SUPABASE_URL',
			value: '<empty>',
			reason: 'Missing / empty. Production builds must inline a real Supabase URL or every share-page / og-image prerender ships empty.',
		});
	} else {
		const problem = productionUrlProblem(url);
		if (problem) {
			findings.push({
				envVar: 'PUBLIC_SUPABASE_URL',
				value: redactCredentials(url),
				reason: problem,
			});
		}
	}

	const anonKey = String(env.PUBLIC_SUPABASE_ANON_KEY ?? '').trim();
	if (!anonKey) {
		findings.push({
			envVar: 'PUBLIC_SUPABASE_ANON_KEY',
			value: '<empty>',
			reason: 'Missing / empty. PostgREST + Auth calls baked into the static bundle would 401 on every request.',
		});
	}

	const mapTilerKey = String(env.PUBLIC_MAPTILER_KEY ?? '').trim();
	if (!mapTilerKey) {
		findings.push({
			envVar: 'PUBLIC_MAPTILER_KEY',
			value: '<empty>',
			reason: 'Missing / empty. The og:image prerender + every maplibre tile request would ship as broken URLs in the static bundle.',
		});
	}

	const proSellable =
		isTruthyFlagValue(env.PUBLIC_COACH_ENABLED) || isTruthyFlagValue(env.PUBLIC_ROUTE_GEN_ENABLED);
	const revenueCatCheckout = String(env.PUBLIC_REVENUECAT_WEB_CHECKOUT_URL ?? '').trim();
	if (proSellable && !revenueCatCheckout) {
		findings.push({
			envVar: 'PUBLIC_REVENUECAT_WEB_CHECKOUT_URL',
			value: '<empty>',
			reason: 'Missing / empty while a Pro perk flag (PUBLIC_COACH_ENABLED / PUBLIC_ROUTE_GEN_ENABLED) is on. A sellable Pro with no hosted-checkout link silently disables the purchase flow on /settings/upgrade.',
		});
	}

	return { ok: findings.length === 0, findings };
}

/**
 * @param {GuardResult} result
 * @returns {string}
 */
export function formatGuardError(result) {
	const banner = '========================================';
	const lines = [
		'',
		banner,
		'[check-production-env] release-web build refuses to start.',
		'',
		"Production builds must have real PUBLIC_SUPABASE_* secrets — without",
		"them the static artifact ships with broken share pages + a 401-on-",
		"every-request anon key.",
		'',
		'Findings:',
		'',
	];
	for (const f of result.findings) {
		lines.push(`  - ${f.envVar} = ${f.value}`);
		lines.push(`      ${f.reason}`);
		lines.push('');
	}
	lines.push('Check that the release workflow has the required repo secrets set:');
	lines.push('  - PUBLIC_SUPABASE_URL');
	lines.push('  - PUBLIC_SUPABASE_ANON_KEY');
	lines.push('  - PUBLIC_MAPTILER_KEY');
	lines.push('  - PUBLIC_REVENUECAT_WEB_CHECKOUT_URL');
	lines.push('');
	lines.push(banner);
	lines.push('');
	return lines.join('\n');
}

// CLI entry. Invoked as `node apps/web/scripts/check_production_env.mjs`
// from the release-web.yml workflow before `npm run build`.
if (import.meta.url === `file://${process.argv[1]}`) {
	const result = checkProductionEnv(process.env);
	if (!result.ok) {
		process.stderr.write(formatGuardError(result));
		process.exit(1);
	}
	process.stdout.write('[check-production-env] PUBLIC_SUPABASE_URL + ANON_KEY look real — proceeding.\n');
}
