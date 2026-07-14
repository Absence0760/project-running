import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

/**
 * Dedicated Playwright config for the Go live-hub WebSocket path.
 *
 * Why separate from playwright.config.ts:
 *   - The main suite runs the spectator page against the Supabase
 *     Realtime fallback (PUBLIC_LIVE_HUB_URL unset). This config flips
 *     the page onto the real Go-hub WebSocket path by booting the hub
 *     AND a dev server that has PUBLIC_LIVE_HUB_URL set.
 *   - The main suite shards across 14 jobs; wiring the Go hub into
 *     every shard would pay the build+boot cost 14×. This config runs
 *     as ONE unsharded CI job (e2e-web-livehub) so the cost is paid
 *     once.
 *
 * The single spec it owns is excluded from the main config via
 * testIgnore so it never runs without the hub.
 *
 * Prereqs (same as the main config): local Supabase up + Go toolchain
 * on PATH. Both webServers below are auto-started:
 *   1. start-livehub.sh — builds + runs the job_worker live-hub on
 *      :8099 (health probe gates readiness).
 *   2. a second vite dev server on :7778 with PUBLIC_LIVE_HUB_URL set
 *      so the spectator page takes the WebSocket branch.
 *
 * Local run: `pnpm test:e2e:livehub` from apps/web.
 */
const HERE = import.meta.dirname;
const WEB_DIR = resolve(HERE, '..');

const HUB_PORT = process.env.LIVEHUB_E2E_PORT ?? '8099';
const DEV_PORT = '7778';

export default defineConfig({
	testDir: '.',
	testMatch: ['live/spectator_websocket.spec.ts'],

	timeout: 30_000,
	expect: { timeout: 15_000 },
	retries: process.env.CI ? 1 : 0,
	forbidOnly: !!process.env.CI,
	workers: 1,
	fullyParallel: false,
	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	webServer: [
		{
			// Build + boot the Go live-hub. First build can take a beat,
			// hence the generous timeout. Health endpoint gates readiness.
			command: `bash ${HERE}/scripts/start-livehub.sh`,
			cwd: HERE,
			url: `http://127.0.0.1:${HUB_PORT}/health`,
			reuseExistingServer: !process.env.CI,
			timeout: 180_000,
			stdout: 'pipe',
			stderr: 'pipe',
			env: { LIVEHUB_E2E_PORT: HUB_PORT }
		},
		{
			// A SECOND dev server (the main config owns :7777) with the
			// hub URL set so the spectator page takes the WebSocket path.
			// `localhost` (not 127.0.0.1) on purpose: vite binds to
			// localhost (::1) by default, so a 127.0.0.1 readiness probe
			// never connects — the main config hits the same gotcha.
			command: `pnpm exec vite dev --port ${DEV_PORT}`,
			cwd: WEB_DIR,
			url: `http://localhost:${DEV_PORT}`,
			reuseExistingServer: !process.env.CI,
			timeout: 120_000,
			stdout: 'ignore',
			stderr: 'pipe',
			// Empty PUBLIC_TILE_STYLE_URL + OSRM_URL force the committed
			// `.env.development` localhost dev services (tileserver :8080, OSRM
			// :5000) off so this e2e dev server falls through to MapTiler/OSM +
			// the dev osrm proxy's demo fallback instead of chasing services
			// the runner doesn't boot (same guard as the main config). § 137.
			env: { PUBLIC_LIVE_HUB_URL: `http://127.0.0.1:${HUB_PORT}`, PUBLIC_TILE_STYLE_URL: '', OSRM_URL: '' }
		}
	],

	use: {
		baseURL: `http://localhost:${DEV_PORT}`,
		trace: 'on-first-retry',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		locale: 'en-GB',
		timezoneId: 'UTC'
	},

	projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }]
});
