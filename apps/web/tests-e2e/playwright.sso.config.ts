import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

/**
 * Dedicated Playwright config for the SSO / OAuth login lane.
 *
 * Why separate from playwright.config.ts:
 *   - It boots a mock OIDC provider (oauth2-mock-server, fronted by
 *     start-mock-oidc.mjs) so the real OAuth login path can run in CI,
 *     where real Google/Apple can't. GoTrue is configured (config.toml
 *     `[auth.external.keycloak]`) to point at the mock — keycloak is the
 *     generic OIDC provider GoTrue accepts with a custom url, since it
 *     special-cases google/apple against the real providers.
 *   - The browser is launched with a host-resolver rule mapping
 *     host.docker.internal -> 127.0.0.1. GoTrue (inside the Supabase
 *     auth container) reaches the mock on the host via
 *     host.docker.internal, and it sends the BROWSER to that same url in
 *     the authorize redirect. The host-resolver rule lets Chromium reach
 *     the mock the host actually publishes.
 *   - Kept out of the sharded main suite so the mock boot cost is paid
 *     once (mirrors e2e-web-livehub).
 *
 * The SSO specs live under tests-e2e/sso and are excluded from the main
 * config via testIgnore so they never run without the mock + provider.
 *
 * Prereqs: local Supabase up, started with the keycloak env vars set
 * (SSO_MOCK_OIDC_URL / _CLIENT_ID / _SECRET) so config.toml's env()
 * substitution wires GoTrue to the mock. Local run:
 * `bin/sso-e2e.sh` (or see tests-e2e/sso/README.md).
 */
const HERE = import.meta.dirname;
const WEB_DIR = resolve(HERE, '..');

const MOCK_PORT = process.env.SSO_MOCK_OIDC_PORT ?? '9888';
const DEV_PORT = '7779';

export default defineConfig({
	testDir: './sso',

	timeout: 30_000,
	expect: { timeout: 15_000 },
	retries: process.env.CI ? 1 : 0,
	forbidOnly: !!process.env.CI,
	workers: 1,
	fullyParallel: false,
	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	webServer: [
		{
			command: `node ${HERE}/scripts/start-mock-oidc.mjs`,
			cwd: WEB_DIR,
			// JWKS (mapped from the keycloak certs path) gates readiness —
			// the discovery doc errors by design (the mock validates the
			// issuer host, which differs from the probe host), so probe a
			// plain 200 endpoint instead.
			url: `http://127.0.0.1:${MOCK_PORT}/jwks`,
			reuseExistingServer: !process.env.CI,
			timeout: 30_000,
			stdout: 'pipe',
			stderr: 'pipe',
			env: {
				SSO_MOCK_OIDC_PORT: MOCK_PORT,
				SSO_MOCK_OIDC_URL: process.env.SSO_MOCK_OIDC_URL ?? `http://host.docker.internal:${MOCK_PORT}`
			}
		},
		{
			// A dedicated dev server (the main config owns :7777, livehub
			// :7778). `localhost` not 127.0.0.1: vite binds localhost (::1)
			// by default, so a 127.0.0.1 readiness probe never connects.
			// Empty PUBLIC_TILE_STYLE_URL + PUBLIC_OSRM_URL force the
			// committed .env.development localhost dev services off (same
			// guard the livehub config uses) — the SSO lane never renders a
			// map, but the dev server still boots cleaner without them.
			command: `pnpm exec vite dev --port ${DEV_PORT}`,
			cwd: WEB_DIR,
			url: `http://localhost:${DEV_PORT}`,
			reuseExistingServer: !process.env.CI,
			timeout: 120_000,
			stdout: 'ignore',
			stderr: 'pipe',
			env: { PUBLIC_TILE_STYLE_URL: '', PUBLIC_OSRM_URL: '' }
		}
	],

	use: {
		baseURL: `http://localhost:${DEV_PORT}`,
		trace: 'on-first-retry',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		locale: 'en-GB',
		timezoneId: 'UTC',
		launchOptions: {
			// GoTrue redirects the browser to the mock at
			// host.docker.internal:PORT (the url it shares with the auth
			// container). On the host that name doesn't resolve, so map it
			// to the loopback the mock actually listens on.
			args: [`--host-resolver-rules=MAP host.docker.internal 127.0.0.1`]
		}
	},

	projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }]
});
