/**
 * Dev/prod isolation guard — shared between the Vite dev server,
 * Playwright globalSetup, and any CI sweep.
 *
 * The rule: if you're running locally (vite dev / playwright /
 * pnpm test:e2e), every external endpoint configured in env must
 * point at a loopback or emulator alias. Anything that smells like
 * prod (https:// + a real domain) aborts the process with a clear
 * fix-it message.
 *
 * Escape hatch for power users: set `ALLOW_PROD_URL_IN_DEV=true`.
 * That bypasses every check and prints a loud one-line warning. Do
 * not commit a setup that depends on the escape hatch.
 */

const LOCAL_HOST_RE = /^https?:\/\/(127\.0\.0\.1|localhost|10\.0\.2\.2|host\.docker\.internal)(?::\d+)?(?:\/|$)/;

const KNOWN_ENV_VARS = [
	'PUBLIC_SUPABASE_URL',
	'SUPABASE_URL',
	'OPENAI_BASE_URL',
	'LIVE_HUB_URL',
	// Bundled into the client at build time and read by routing.ts /
	// RouteBuilder.svelte. The legacy `OSRM_URL` is kept in the
	// allow-list below for any external tooling that still uses it.
	'PUBLIC_OSRM_URL',
	'OSRM_URL',
	'PUBLIC_SITE_URL',
];

const KEY_PATTERNS = [
	{
		envVar: 'STRIPE_SECRET_KEY',
		bad: /^sk_live_/,
		good: 'sk_test_…',
		message: 'STRIPE_SECRET_KEY is a live key (sk_live_…). Local must use a test-mode key (sk_test_…).',
	},
	{
		envVar: 'PUBLIC_STRIPE_KEY',
		bad: /^pk_live_/,
		good: 'pk_test_…',
		message: 'PUBLIC_STRIPE_KEY is a live publishable key (pk_live_…). Local must use a test-mode key (pk_test_…).',
	},
];

/** @type {Record<string, string>} */
const SCOPE_LABEL = {
	vite: 'Vite dev server',
	playwright: 'Playwright e2e',
	ci: 'CI env-isolation sweep',
};

/**
 * @typedef {{ envVar: string; value: string; rule: string; fix: string }} Finding
 * @typedef {{ ok: boolean; override: boolean; findings: Finding[] }} GuardResult
 */

/**
 * @param {Record<string, string | undefined>} env
 * @param {{ scope?: string }} [_opts]
 * @returns {GuardResult}
 */
export function checkEnvIsolation(env, _opts = {}) {
	/** @type {Finding[]} */
	const findings = [];
	if (env.ALLOW_PROD_URL_IN_DEV === 'true') {
		return { ok: true, override: true, findings };
	}

	for (const varName of KNOWN_ENV_VARS) {
		const raw = env[varName];
		if (!raw) continue;
		const trimmed = String(raw).trim();
		if (!trimmed) continue;
		if (LOCAL_HOST_RE.test(trimmed)) continue;
		findings.push({
			envVar: varName,
			value: trimmed,
			rule: 'remote-host-in-dev',
			fix: `Set ${varName} to a loopback URL (e.g. http://127.0.0.1:54321) or unset it.`,
		});
	}

	for (const k of KEY_PATTERNS) {
		const raw = env[k.envVar];
		if (!raw) continue;
		if (k.bad.test(String(raw).trim())) {
			findings.push({
				envVar: k.envVar,
				value: '<redacted live key>',
				rule: 'live-key-in-dev',
				fix: `${k.message} Replace with ${k.good}.`,
			});
		}
	}

	return { ok: findings.length === 0, override: false, findings };
}

/**
 * @param {GuardResult} result
 * @param {{ scope?: 'vite' | 'playwright' | 'ci' }} [opts]
 * @returns {string}
 */
export function formatGuardError(result, { scope = 'vite' } = {}) {
	const banner = '========================================';
	const lines = [
		'',
		banner,
		`[env-isolation guard] ${SCOPE_LABEL[scope]} refuses to start.`,
		'',
		'Local dev must not be configured against production endpoints.',
		'Found:',
		'',
	];
	for (const f of result.findings) {
		lines.push(`  - ${f.envVar} = ${f.value}`);
		lines.push(`      rule: ${f.rule}`);
		lines.push(`      fix:  ${f.fix}`);
		lines.push('');
	}
	lines.push('Power-user override (NOT for daily use):');
	lines.push('  ALLOW_PROD_URL_IN_DEV=true');
	lines.push('');
	lines.push('See docs/dev_prod_isolation.md for the full policy.');
	lines.push(banner);
	lines.push('');
	return lines.join('\n');
}
