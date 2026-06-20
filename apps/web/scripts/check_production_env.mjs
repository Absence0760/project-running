/**
 * Production build-env guard — sibling of `env_isolation.mjs`. Where
 * that script refuses dev environments configured against prod
 * endpoints, this one refuses production builds configured against
 * placeholder or local endpoints. Both rules exist because the
 * default value for missing env vars in CI is "empty string", which
 * silently bakes a broken config into the static artifact.
 *
 * Rules enforced for a production build:
 *   - PUBLIC_SUPABASE_URL must be a real https://*.supabase.co URL.
 *     Empty, `placeholder.supabase.co`, or `http://127.0.0.1:54321`
 *     all abort the build. Without this guard, a missing secret in
 *     the release workflow would deploy a static site whose
 *     `entries()` calls return [] (the og:image + share-page
 *     prerender then ships without any prerendered ids), and our
 *     handleUnseenRoutes: 'warn' config quietly accepts the empty
 *     set rather than failing loud.
 *   - PUBLIC_SUPABASE_ANON_KEY must be non-empty.
 *   - PUBLIC_MAPTILER_KEY must be non-empty. Used by the og:image
 *     PNG renderer at prerender time and by the maplibre tile
 *     source at runtime; an empty key bakes broken map / share-
 *     image URLs into every public route + run page.
 *   - PUBLIC_REVENUECAT_WEB_CHECKOUT_URL must be non-empty. The hosted
 *     Web Paywall Link `/settings/upgrade` redirects to; an empty value
 *     disables the Pro purchase flow silently.
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
 * The check is invoked by `npm run check:prod-env` (CLI entry below)
 * and by the release-web.yml workflow as a pre-build step. The
 * `check_production_env.test.mjs` suite covers the matcher.
 */

const LOCAL_HOST_RE = /^https?:\/\/(127\.0\.0\.1|localhost|10\.0\.2\.2|host\.docker\.internal)(?::\d+)?(?:\/|$)/;
const PLACEHOLDER_HOST_RE = /\bplaceholder\.supabase\.co\b/i;

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
	} else if (PLACEHOLDER_HOST_RE.test(url)) {
		findings.push({
			envVar: 'PUBLIC_SUPABASE_URL',
			value: url,
			reason: 'Looks like the CI bundle-budget placeholder (`placeholder.supabase.co`). The release workflow needs the real prod URL.',
		});
	} else if (LOCAL_HOST_RE.test(url)) {
		findings.push({
			envVar: 'PUBLIC_SUPABASE_URL',
			value: url,
			reason: 'Points at a loopback / emulator host. Production builds must use a remote Supabase URL.',
		});
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

	const revenueCatCheckout = String(env.PUBLIC_REVENUECAT_WEB_CHECKOUT_URL ?? '').trim();
	if (!revenueCatCheckout) {
		findings.push({
			envVar: 'PUBLIC_REVENUECAT_WEB_CHECKOUT_URL',
			value: '<empty>',
			reason: 'Missing / empty. The Pro purchase flow on /settings/upgrade silently disables itself when the hosted-checkout link is unset.',
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
