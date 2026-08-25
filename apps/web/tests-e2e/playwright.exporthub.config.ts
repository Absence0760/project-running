import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

/**
 * Dedicated Playwright config for the QUEUED Art 20 export rail
 * (decisions.md § 717 / § 724).
 *
 * Why separate from playwright.config.ts:
 *   - The main suite runs every export spec against the `export-data`
 *     Edge Function fallback (PUBLIC_EXPORT_HUB_URL unset). Setting the
 *     hub URL there would flip all twelve of them onto a transport they
 *     do not mock. This config flips ONE spec onto the real Go rail by
 *     booting the worker AND a dev server that has the hub URL set.
 *   - The main suite shards across 14 jobs; wiring the Go worker into
 *     every shard would pay the build+boot cost 14×. This config runs
 *     as ONE unsharded CI job (e2e-web-exporthub) so the cost is paid
 *     once. Same shape as playwright.livehub.config.ts.
 *
 * The single spec it owns is excluded from the main config via
 * testIgnore so it never runs without the worker.
 *
 * Prereqs (same as the main config): local Supabase up + Go toolchain
 * on PATH. Both webServers below are auto-started:
 *   1. start-exporthub.sh — builds + runs the job_worker on :8098 with
 *      auth ON and a service key (health probe gates readiness). The
 *      same process drains the `data_export` queue, so there is no
 *      second thing to boot.
 *   2. a third vite dev server on :7779 with PUBLIC_EXPORT_HUB_URL set
 *      so the account page takes the enqueue-and-poll branch.
 *
 * Local run: `pnpm test:e2e:exporthub` from apps/web.
 */
const HERE = import.meta.dirname;
const WEB_DIR = resolve(HERE, '..');

const HUB_PORT = process.env.EXPORTHUB_E2E_PORT ?? '8098';
const HUB_URL = `http://127.0.0.1:${HUB_PORT}`;
// :7777 belongs to the main config and :7778 to the live-hub one.
const DEV_PORT = '7779';

export default defineConfig({
	testDir: '.',
	testMatch: ['settings/export_job.spec.ts'],

	// Unlike the live-hub lane, this one is signed in: an Art 20 export
	// is the caller's own data, so the spec needs USER_A's session.
	// globalSetup signs the seeded users in against THIS lane's dev
	// server and writes their storage state.
	globalSetup: './fixtures/auth.ts',

	// An export is a real build against a real Storage stack, and the
	// worker claims off a 2-second poll — generous next to the main
	// suite's 30s, which never waits on a background job.
	timeout: 180_000,
	expect: { timeout: 15_000 },
	retries: process.env.CI ? 1 : 0,
	forbidOnly: !!process.env.CI,
	workers: 1,
	fullyParallel: false,
	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	webServer: [
		{
			// Build + boot the Go worker. First build can take a beat,
			// hence the generous timeout. Health endpoint gates readiness.
			command: `bash ${HERE}/scripts/start-exporthub.sh`,
			cwd: HERE,
			url: `${HUB_URL}/health`,
			reuseExistingServer: !process.env.CI,
			timeout: 180_000,
			stdout: 'pipe',
			stderr: 'pipe',
			env: { EXPORTHUB_E2E_PORT: HUB_PORT }
		},
		{
			// A dev server of its own with the export hub URL set.
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
			// `.env.development` localhost dev services off so this e2e dev
			// server doesn't chase services the runner never boots (same
			// guard as the main and live-hub configs). § 137.
			env: {
				PUBLIC_EXPORT_HUB_URL: HUB_URL,
				PUBLIC_TILE_STYLE_URL: '',
				OSRM_URL: ''
			}
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
