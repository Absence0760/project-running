import { expect, test } from '@playwright/test';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Static source-level guards — same shape as
 * `apps/mobile_android/test/architecture_guards_test.dart` but for
 * the web app. These tests don't drive a browser; they grep the
 * Svelte source and assert that load-bearing patterns can't silently
 * regress.
 *
 * Why this is here at all: the auth-race shape (a page's onMount
 * fetches before `auth.user` resolves, leading to wrong fallback
 * data or no-op clicks) has bitten us on 9 separate pages now. Each
 * incident was caught by an e2e flake, fixed with the same
 * `for (let i = 0; i < 20 && (auth.loading || !auth.user); i++)`
 * poll. Until we ship a single `auth.ready()` helper, the
 * architecture guard below stops the recurrence cold: any new
 * authed page that adds `await fetchX()` in onMount without the
 * poll fails the test immediately, instead of after a flaky CI run.
 */

const ROUTES_DIR = 'src/routes';

// Pages that are intentionally anon-readable or have no per-user
// fetch in onMount. The guard skips these.
const ALLOW_LIST = new Set<string>([
	// Anon by design — no auth.user dependency.
	'src/routes/+page.svelte',
	'src/routes/login/+page.svelte',
	'src/routes/auth/callback/+page.svelte',
	'src/routes/auth/reset/+page.svelte',
	'src/routes/share/run/[id]/+page.svelte',
	'src/routes/share/route/[id]/+page.svelte',
	'src/routes/live/[id]/+page.svelte',
	'src/routes/live/event/[id]/[instance]/+page.svelte',
	'src/routes/clubs/join/[token]/+page.svelte',
	'src/routes/explore/+page.svelte',
	// Anon-or-authed but uses public_runs / public_routes view, no
	// owner-gated fetch. Auth race exists but doesn't change the
	// data shape.
	'src/routes/u/[id]/+page.svelte',
	// Wrappers that delegate everything to a child component — the
	// child handles its own auth gating.
	'src/routes/runs/new/+page.svelte',
	'src/routes/routes/new/+page.svelte',
	'src/routes/plans/new/+page.svelte',
	// Period summary reads runs but its child does the gating.
	'src/routes/dashboard/period/[type]/[date]/+page.svelte',
	// Settings/upgrade is mostly anon-readable pricing copy.
	'src/routes/settings/upgrade/+page.svelte',
	'src/routes/settings/licenses/+page.svelte',
]);

function listSvelteFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		const st = statSync(full);
		if (st.isDirectory()) {
			out.push(...listSvelteFiles(full));
		} else if (entry === '+page.svelte') {
			out.push(full);
		}
	}
	return out;
}

test.describe('architecture guards', () => {
	test('every authed +page.svelte that fetches in onMount waits for auth.user before firing', () => {
		const files = listSvelteFiles(ROUTES_DIR);
		const violations: string[] = [];

		for (const file of files) {
			if (ALLOW_LIST.has(file)) continue;

			const src = readFileSync(file, 'utf-8');

			// Skip files that don't reference the auth store at all —
			// those are anon pages by definition.
			if (!src.includes("from '$lib/stores/auth.svelte'") &&
				!src.includes("from '$lib/stores/auth'")) {
				continue;
			}

			// Skip files that don't fetch in onMount.
			if (!/onMount\([^)]*async/.test(src) && !src.includes('onMount(async')) {
				continue;
			}

			// The poll-for-auth pattern. Allow either of the two
			// idioms we use: the canonical for-loop or any await on
			// an `auth.ready()` style helper if/when we add one.
			const hasPoll =
				/auth\.loading\s*\|\|\s*!auth\.user/.test(src) ||
				/auth\.ready\(\)/.test(src) ||
				/await\s+auth\.whenReady/.test(src);

			if (!hasPoll) {
				violations.push(file);
			}
		}

		expect(
			violations,
			`These authed +page.svelte files fetch in onMount without polling for auth.user.\n` +
				`The auth-race shape has caused 9 production bugs. Add the canonical 1s\n` +
				`poll loop (see apps/web/src/routes/runs/[id]/+page.svelte), or add the\n` +
				`page to the ALLOW_LIST in this test if it's intentionally anon-only.`
		).toEqual([]);
	});

	test('login page snapshots return_to at mount, not on every navigation', () => {
		// Regression guard: the login page used to read $page.url.searchParams
		// at navigation time, which let the post-sign-in $effect's
		// replaceState clobber the captured return_to. Snapshotting at
		// mount is the only way to make the explicit-goto + reactive-$effect
		// pair deterministic. Don't undo this without redesigning the
		// dual-trigger flow.
		const src = readFileSync('src/routes/login/+page.svelte', 'utf-8');
		expect(src).toContain('returnToOnMount');
		// Old shape returned `$page.url.searchParams.get('return_to')`
		// directly from inside `safeReturnTo`. New shape reads the
		// cached value. Pin the cache assignment lives in onMount —
		// check the ordering by index since multi-line regex
		// backtracking on Svelte sources is fragile.
		// The cache assignment INSIDE onMount (not the `let` declaration
		// at module scope) is what makes the snapshot deterministic.
		// Find onMount, walk to its closing brace, assert the
		// assignment + searchParams read both live in that block.
		const onMountIdx = src.indexOf('onMount(');
		expect(onMountIdx, 'onMount block must exist').toBeGreaterThanOrEqual(0);
		// Approximate the onMount body as the next ~600 chars after
		// `onMount(`. Sufficient for our small login page.
		const onMountBlock = src.slice(onMountIdx, onMountIdx + 600);
		expect(onMountBlock).toContain('returnToOnMount =');
		expect(onMountBlock).toContain("searchParams.get('return_to')");

		// The safeReturnTo function must NOT call searchParams.get
		// on every invocation — that's the regression we're guarding
		// against. The function body should just return the cached
		// value.
		const safeReturnToBody = src.match(
			/function safeReturnTo\(\)[^{]*\{([^}]*)\}/
		);
		expect(safeReturnToBody?.[1] ?? '').not.toContain('searchParams.get');
	});

	test('/live/[id] data path runs independently of map.on(load)', () => {
		// Regression guard for fix(web): /live/[id] decouples LIVE
		// badge + stat strip from MapTiler. If hydrateBacklog or
		// subscribeLive ever get pulled back inside map.on('load'),
		// a missing PUBLIC_MAPTILER_KEY (CI) or a slow style fetch
		// (real users on bad networks) hangs the entire page.
		const src = readFileSync('src/routes/live/[id]/+page.svelte', 'utf-8');

		// Find the onMount block.
		const onMountMatch = src.match(/onMount\(\(\)\s*=>\s*\{([\s\S]*?)\n\t\}\);/);
		expect(onMountMatch).not.toBeNull();
		const body = onMountMatch![1];

		// hydrateBacklog must be invoked from the onMount body itself
		// so the LIVE badge + stat strip render even when the MapTiler
		// init path hasn't fired (missing key in CI, slow style fetch,
		// or the user hasn't accepted the consent-gated tile load).
		expect(body).toContain('hydrateBacklog');

		// The map init was extracted into initMap() behind the
		// mapConsented gate, so `map.on('load'` no longer lives in
		// onMount. Assert the negative: the onMount body must NOT
		// register a load handler in-line, because anything stuffed
		// inside that handler is the regression we're guarding
		// against.
		expect(body).not.toContain("map.on('load'");
	});

	test('pushPing in /live/[id] guards every map.* call with `if (!map)` or optional chain', () => {
		// Companion guard: even with hydrateBacklog out of
		// map.on('load'), pushPing still calls map.jumpTo / panTo /
		// getSource. Pings can arrive (via subscribeLive's realtime
		// channel) before map readiness. Every map-touching line in
		// pushPing must be defensive.
		const src = readFileSync('src/routes/live/[id]/+page.svelte', 'utf-8');
		const pushPingMatch = src.match(
			/function pushPing\([\s\S]*?\n\t\}\n/
		);
		expect(pushPingMatch).not.toBeNull();
		const body = pushPingMatch![0];

		// Either an early `if (!map) return` OR every map.* call
		// must be guarded. Pin the early-return idiom since that's
		// what we actually shipped.
		expect(body).toMatch(/if\s*\(!map\)\s*return/);
	});

	test('column-grant lockdown discipline: no select(*) on clubs / events', () => {
		// Reason: `clubs.invite_token` and `events.meet_lat` /
		// `meet_lng` are revoked from anon + authenticated at the
		// column level (migrations 20260801_001 + 20260723_001 +
		// 20260806_001 + 20260818_001). PostgREST `select('*')`
		// expands to all columns at the SQL layer and raises 42501
		// because the role lacks SELECT on the revoked columns. A
		// nested `clubs(*)` / `events(*)` embed has the same problem
		// (the embed materialises every column of the joined row).
		//
		// CI surfaced this as widespread Playwright failure when the
		// audit migration landed without the call-site fix on `events`.
		// Pin the discipline statically: future regressions fail this
		// test instead of `clubs/event-create.spec.ts` flaking with
		// "Event not found".
		//
		// Fix at any failing call site is "enumerate columns via
		// `CLUB_SELECT_COLS` / `EVENT_SELECT_COLS` from data.ts", or
		// for nested embeds use `clubs(${CLUB_SELECT_COLS})`.
		const data = readFileSync('src/lib/core/data.ts', 'utf-8');
		// Strip block + line comments so doc strings can mention the
		// pattern without false-positive.
		const stripped = data
			.replace(/\/\*[\s\S]*?\*\//g, '')
			.replace(/\/\/.*$/gm, '');
		const banned = [
			/\.from\(['"]clubs['"]\)\.select\(['"]\*['"]\)/,
			/\.from\(['"]events['"]\)\.select\(['"]\*['"]\)/,
			// Post-insert / post-update `.select()` no-arg = `*` too.
			// Only flag when it follows from('clubs' | 'events').
			/\.from\(['"](clubs|events)['"]\)[\s\S]*?\.select\(\s*\)\.single\(\)/,
			/['"`]clubs\(\*\)/,
			/['"`]events\(\*\)/
		];
		for (const pat of banned) {
			expect(stripped).not.toMatch(pat);
		}
	});
});
