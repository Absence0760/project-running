import { expect, test } from '@playwright/test';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Static source-level guards for the hash-based CSP (audit-xss M2 /
 * decisions §70). These don't drive a browser — the CSP `<meta>` is
 * injected by SvelteKit's `kit.csp` at BUILD/prerender time, so it never
 * appears under the `vite dev` server the e2e suite runs against. Instead
 * they pin the two things that, if regressed, silently reopen the
 * `script-src 'unsafe-inline'` gap:
 *
 *   1. The `kit.csp` hash config must stay in `svelte.config.js`, scoped to
 *      `script-src` with no `'unsafe-inline'`. SvelteKit then SHA-256-hashes
 *      every inline script it emits and ships a per-page `<meta http-equiv>`
 *      CSP — the binding `script-src` layer enforced alongside the CloudFront
 *      header.
 *   2. No prerendered page may use a server `redirect()` in its load. The
 *      prerenderer turns that into a redirect STUB containing an un-hashed
 *      inline `location.href` script (the one page the hash CSP couldn't
 *      cover). Redirects must be client-side `+page.svelte` (onMount → goto +
 *      <meta refresh>), which stay normal hash-covered pages. `/settings`,
 *      `/clubs`, `/feed`, `/explore` all follow that shape.
 */

const ROUTES_DIR = 'src/routes';

function listPageLoads(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			out.push(...listPageLoads(full));
		} else if (entry === '+page.ts' || entry === '+page.server.ts') {
			out.push(full);
		}
	}
	return out;
}

test.describe('hash-based CSP guards (no browser)', () => {
	test('svelte.config.js keeps the script-src hash CSP with no unsafe-inline', () => {
		const cfg = readFileSync('svelte.config.js', 'utf-8');
		// The csp block must exist in hash mode.
		expect(cfg, 'kit.csp must be configured').toMatch(/csp\s*:/);
		expect(cfg, "csp.mode must be 'hash' (nonces are impossible for a fully prerendered site)").toMatch(
			/mode\s*:\s*['"]hash['"]/,
		);
		expect(cfg, "csp.directives must lock down 'script-src'").toMatch(/['"]script-src['"]\s*:/);

		// The configured script-src directive must not re-introduce
		// 'unsafe-inline' (that's the whole point — the hash list replaces it).
		const block = cfg.slice(cfg.indexOf('csp'));
		const scriptSrc = block.match(/['"]script-src['"]\s*:\s*\[([^\]]*)\]/);
		expect(scriptSrc, 'script-src directive array must be present').not.toBeNull();
		expect(scriptSrc![1], "script-src must not allow 'unsafe-inline'").not.toMatch(/unsafe-inline/);
	});

	test('no prerendered page uses a server redirect() (would emit an un-hashed stub)', () => {
		const offenders = listPageLoads(ROUTES_DIR).filter((f) => {
			const src = readFileSync(f, 'utf-8');
			if (!/\bredirect\s*\(/.test(src)) return false;
			// A server redirect only produces a stub when the route is
			// prerendered. The global default is prerender=true, so a load that
			// redirects is a stub unless it explicitly opts out.
			const optsOut = /export\s+const\s+prerender\s*=\s*false/.test(src);
			return !optsOut;
		});
		expect(
			offenders,
			'these page loads server-redirect while prerendered → un-hashed inline-script stub; '
				+ 'use a client-side +page.svelte redirect (onMount→goto + <meta refresh>) instead',
		).toEqual([]);
	});
});
