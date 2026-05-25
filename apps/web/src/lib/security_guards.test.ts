// Source-level guards that pin in place the security invariants for
// thumbnail rendering on the web app. Each test reads a source file as
// text and asserts a pattern is present, with a reason a future editor
// can read before deciding it's safe to break.
//
// Mirrors the `thumbnail privacy-zone clipping` group in
// `apps/mobile_android/test/architecture_guards_test.dart` — the two
// rules must stay in lockstep.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('RunTrackPreview routes non-owner fetches through clip-public-track EF', () => {
	// Reason: feed thumbnails are shown to non-owner viewers. The pre-
	// 20260619_001 pattern was "fetchTrackByPath then clipTrackForUser
	// client-side" but that leaked the unclipped blob via direct
	// Storage download. Non-owner thumbnails must now go through
	// fetchClippedTrackForRun (which calls the clip-public-track Edge
	// Function — server-side download + clip). Owners keep the direct
	// path since the per-user-folder Storage policy still gates them.
	const source = read('src/lib/components/RunTrackPreview.svelte');
	assert.match(
		source,
		/fetchClippedTrackForRun/,
		'RunTrackPreview must use fetchClippedTrackForRun for non-owner viewers — direct Storage download leaks the unclipped blob. See decisions §33.',
	);
});

test('every RunTrackPreview on /u/[id] threads runId + ownerUserId', () => {
	// Reason: the EF non-owner clip path needs the run id (server
	// resolves track_url + clips inline). Without the prop,
	// RunTrackPreview can't reach the EF and renders a placeholder
	// instead of the clipped polyline. The activity feed lives as
	// the Feed tab AND the Runs tab on /u/[id]; both surfaces render
	// other users' runs and both must clip. The earlier "any one
	// mount has the prop" form of this test let the Runs tab silently
	// regress (audit/privacy-zones, May 2026). Iterate every mount.
	const source = read('src/routes/u/[id]/+page.svelte');
	const mounts = [
		...source.matchAll(/<RunTrackPreview\b[^/>]*\/?>/gs),
	];
	assert.ok(
		mounts.length >= 2,
		'expected at least two RunTrackPreview mounts on /u/[id] ' +
			'(Feed tab + Runs tab); got ' +
			mounts.length +
			' — refactor probably collapsed them.',
	);
	for (const m of mounts) {
		const tag = m[0];
		assert.match(
			tag,
			/runId=/s,
			'RunTrackPreview on /u/[id] missing runId prop:\n' + tag,
		);
		assert.match(
			tag,
			/ownerUserId=/s,
			'RunTrackPreview on /u/[id] missing ownerUserId prop ' +
				'(privacy-zone clip is skipped without it):\n' +
				tag,
		);
	}
});

test('RunTrackPreview cache is bounded (LRU)', () => {
	// Reason: without the cap a long session through 1000+ runs holds
	// every deserialised track in memory until reload. JS Map preserves
	// insertion order so dropping `keys().next()` evicts the oldest.
	const source = read('src/lib/components/RunTrackPreview.svelte');
	assert.match(
		source,
		/CACHE_MAX/,
		'RunTrackPreview cache must have a bounded size — see the CACHE_MAX constant.',
	);
	assert.match(
		source,
		/CACHE\.keys\(\)\.next\(\)/,
		'LRU eviction must drop the oldest entry when the cache is full.',
	);
});

test('routes/[id] page reads through the owner-aware fetchRouteById', () => {
	// Reason: pre-prod privacy-zones + public-rows audits found this
	// surface rendered `<RunMap track={route.waypoints} />` with no clip
	// step. Bookmarked, public, and club routes were leaking the unclipped
	// polyline to non-owners. The fix dropped the bare-table public-anyone
	// SELECT (migration 20260703_001) and reshaped fetchRouteById to be
	// owner-aware: bare `routes` first (RLS gates owners + active club
	// members), `public_routes` view + clip_route_for_viewer fallback for
	// everyone else. The page must read through that gateway — not from
	// the bare table directly. See decisions §33.
	const source = read('src/routes/routes/[id]/+page.svelte');
	assert.match(
		source,
		/fetchRouteById/,
		'/routes/[id] must read through fetchRouteById — bypassing it (e.g. supabase.from("routes")) skips the public_routes view + clip overlay for non-owners. See decisions §33.',
	);
	assert.doesNotMatch(
		source,
		/from\(['"]routes['"]\)/,
		'/routes/[id] must not read from the bare `routes` table — go through fetchRouteById, which is owner-aware.',
	);
});

test('fetchRouteById is owner-aware (bare-table first, public_routes view fallback)', () => {
	// Reason: closes the audit/public-rows + audit/privacy-zones High
	// finding from /audit/all on 2026-05-03. Owners (and active club
	// members) hit `routes` directly under RLS — the unclipped polyline
	// is theirs to see. Anon and non-owner viewers must fall back to the
	// `public_routes` view (which strips waypoints/geom/start_point/
	// is_starred and conditionally nulls club_id) and overlay
	// fetchClippedRouteForViewer so the polyline respects the runner's
	// privacy zones. See migration 20260703_001_public_routes_view.sql.
	const source = read('src/lib/data.ts');
	const fnMatch = source.match(
		/export async function fetchRouteById[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate fetchRouteById body — rename?');
	const body = fnMatch![0];
	assert.match(
		body,
		/from\(['"]routes['"]\)/,
		'fetchRouteById must try the bare `routes` table first — RLS gates owners + active club members.',
	);
	assert.match(
		body,
		/from\(['"]public_routes['"]\)/,
		'fetchRouteById must fall back to the public_routes view for non-owner viewers.',
	);
	assert.match(
		body,
		/fetchClippedRouteForViewer/,
		'fetchRouteById must overlay fetchClippedRouteForViewer for non-owner viewers — the public_routes view ships no waypoints.',
	);
});

test('routes list + clubs Routes tab use RouteTrackPreview', () => {
	// Reason: same audit. Both list-view surfaces had bare
	// <TrackPreview points={route.waypoints} /> — fine for owned rows
	// but leaks bookmarked / club / public rows. RouteTrackPreview wraps
	// the raw thumbnail with the same lazy clip + cache pattern as
	// RunTrackPreview so non-owner viewers see clipped output.
	const routesList = read('src/routes/routes/+page.svelte');
	assert.match(
		routesList,
		/<RouteTrackPreview/,
		'My Routes list must use <RouteTrackPreview> rather than bare <TrackPreview> — bookmarked others-routes leak otherwise. See decisions §33.',
	);
	const clubsPage = read('src/routes/clubs/[slug]/+page.svelte');
	assert.match(
		clubsPage,
		/<RouteTrackPreview/,
		'Clubs page Routes tab must use <RouteTrackPreview> — club-route thumbnails (other admins / members) need the clip pass for non-owner viewers.',
	);
});

test('RouteTrackPreview routes non-owner fetches through clip_route_for_viewer', () => {
	// Reason: the clip RPC is the only path that returns clipped
	// waypoints without first leaking the row's `waypoints` column to
	// the wire. Owner reads use the row directly; non-owner reads must
	// call fetchClippedRouteForViewer.
	const source = read('src/lib/components/RouteTrackPreview.svelte');
	assert.match(
		source,
		/fetchClippedRouteForViewer/,
		'RouteTrackPreview must use fetchClippedRouteForViewer for non-owner viewers — bare route.waypoints render leaks the unclipped polyline. See decisions §33.',
	);
	assert.match(
		source,
		/CACHE_MAX/,
		'RouteTrackPreview must have a bounded cache — see RunTrackPreview for the LRU shape.',
	);
});

test('fetchClippedRouteForViewer fails closed on RPC error', () => {
	// Reason: same as clipTrackForUser. Returning the input on RPC
	// error would defeat the helper. The empty-input early-return is
	// not relevant here (the helper takes only an id), so we only
	// assert that the error branch returns [].
	const source = read('src/lib/data.ts');
	const fnMatch = source.match(
		/export async function fetchClippedRouteForViewer[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate fetchClippedRouteForViewer body — rename?');
	const body = fnMatch![0];
	const errBranch = body.match(/if \(error\) \{[\s\S]*?\}/);
	assert.ok(errBranch, 'fetchClippedRouteForViewer must have an explicit error branch');
	assert.match(
		errBranch![0],
		/return \[\];/,
		'fetchClippedRouteForViewer must return [] on RPC failure — see decisions §33.',
	);
});

test('public-runs readers go through the public_runs view', () => {
	// Reason: pre-prod public-rows audit found that `select * from runs
	// where is_public = true` exposes external_id, training-plan-linkage
	// metadata, sync-state metadata, and link-existence to private
	// routes/events. The public_runs view (migration 20260626_001)
	// strips these. Every public-runs reader must read from the view,
	// not the base table.
	const source = read('src/lib/data.ts');

	// Slice the source between two known landmarks per function. Each
	// helper ends well before the next public-export so we can scan a
	// reasonable window. We don't try to perfectly delimit a function
	// body (nested type literals trip a naive `^}` regex); we just need
	// a window that contains the .from() call and nothing else.
	function bodyAfter(needle: string, until: string): string {
		const start = source.indexOf(needle);
		assert.ok(start >= 0, `Could not locate '${needle}' — rename?`);
		const end = source.indexOf(until, start + needle.length);
		assert.ok(
			end > start,
			`Could not locate landmark '${until}' after '${needle}'`,
		);
		return source.slice(start, end);
	}
	const fetchPublicRunBody = bodyAfter(
		'export async function fetchPublicRun(',
		'export async function deleteRun(',
	);
	const fetchFollowingFeedBody = bodyAfter(
		'export async function fetchFollowingFeed(',
		'export async function clipTrackForUser(',
	);
	const fetchPublicRunsByUserBody = bodyAfter(
		'export async function fetchPublicRunsByUser(',
		'// ─────────────────────── Kudos',
	);

	for (const [name, body] of [
		['fetchPublicRun', fetchPublicRunBody],
		['fetchFollowingFeed', fetchFollowingFeedBody],
		['fetchPublicRunsByUser', fetchPublicRunsByUserBody],
	] as const) {
		assert.match(
			body,
			/\.from\(['"]public_runs['"]\)/,
			`${name} must read from the public_runs view rather than the runs table — see decisions §33 and migration 20260626_001.`,
		);
		assert.doesNotMatch(
			body,
			/\.from\(['"]runs['"]\)/,
			`${name} must NOT read from the bare runs table — that path leaks external_id, training-plan-linkage metadata, etc.`,
		);
	}
});

test('clipTrackForUser fails closed on RPC error', () => {
	// Reason: returning the unclipped input on RPC error was the
	// privacy leak this helper exists to prevent. Fail-closed (return
	// []) so a transient outage renders an empty map for non-owner
	// viewers instead of leaking the full track. The empty-input
	// early-return is fine — it returns the empty input which is the
	// same shape as `[]`.
	const source = read('src/lib/data.ts');
	const fnMatch = source.match(
		/export async function clipTrackForUser[\s\S]*?^}/m,
	);
	assert.ok(fnMatch, 'Could not locate clipTrackForUser body — rename?');
	const body = fnMatch![0];
	// The `if (error) { ... }` branch must return [], not points.
	const errBranch = body.match(/if \(error\) \{[\s\S]*?\}/);
	assert.ok(errBranch, 'clipTrackForUser must have an explicit error branch');
	assert.match(
		errBranch![0],
		/return \[\];/,
		'clipTrackForUser must return [] on RPC failure — see decisions §33.',
	);
	assert.doesNotMatch(
		errBranch![0],
		/return points/,
		'clipTrackForUser must not fall back to the input track on RPC error — that is the leak this helper exists to prevent.',
	);
});

test('KMS Decrypt principal ARN matches the Lambda role name', () => {
	// Reason: the kms_secrets policy in infra/modules/web-stack/main.tf
	// builds the Lambda role ARN as a deterministic string
	// (`${prefix}-coach-lambda`) instead of referencing aws_iam_role.lambda
	// — the reference would create a key→role→key cycle. Audit pass 3
	// caught a regression where the policy said `-lambda` but the actual
	// role is named `-coach-lambda`, leaving the running Lambda unable
	// to decrypt secrets at cold-start. Pin the suffix on both sides so
	// a future rename of the role forces a deliberate edit on the
	// policy too.
	const source = read('../../infra/modules/web-stack/main.tf');
	const policySuffixMatch = source.match(
		/identifiers\s*=\s*compact\(\[[\s\S]*?role\/\$\{local\.resource_prefix\}-([a-z0-9-]+)/m,
	);
	assert.ok(
		policySuffixMatch,
		'Could not extract the role-name suffix from the kms_secrets policy in infra/modules/web-stack/main.tf — has the AllowLambdaAndDeployRolesToDecrypt statement moved?',
	);
	const policySuffix = policySuffixMatch![1];
	const roleNameMatch = source.match(
		/resource\s+"aws_iam_role"\s+"lambda"\s*\{[\s\S]*?name\s*=\s*"\$\{local\.resource_prefix\}-([a-z0-9-]+)"/m,
	);
	assert.ok(
		roleNameMatch,
		'Could not extract the Lambda role name from infra/modules/web-stack/main.tf — has aws_iam_role.lambda moved?',
	);
	const roleSuffix = roleNameMatch![1];
	assert.equal(
		policySuffix,
		roleSuffix,
		`KMS policy ARN suffix (${policySuffix}) must match aws_iam_role.lambda name suffix (${roleSuffix}). A mismatch leaves the Lambda unable to call kms:Decrypt at cold-start. See infra/modules/web-stack/main.tf and the audit-pass-3 commit ${'8424dec'}.`,
	);
});

test('CoachChat DOMPurify config disallows the `class` attribute', () => {
	// Reason: an LLM-emitted `<span class="modal-backdrop">` would
	// otherwise pick up the global app.css class and overlay the page,
	// a clickjacking vector flagged in audit pass-2 (commit a2ea656).
	// `class` must NOT appear in COACH_ALLOWED_ATTR; ALLOW_DATA_ATTR
	// must be false. The afterSanitizeAttributes hook must force
	// target=_blank + rel=noopener on every <a> so an LLM-emitted link
	// can't reach back into window.opener (reverse-tab phishing).
	const source = read('src/lib/coach/markdown.ts');
	const attrMatch = source.match(/COACH_ALLOWED_ATTR\s*=\s*\[([^\]]*)\]/);
	assert.ok(
		attrMatch,
		'Could not locate COACH_ALLOWED_ATTR — has it been renamed? See coach/markdown.ts.',
	);
	assert.doesNotMatch(
		attrMatch![1],
		/['"]class['"]/,
		'COACH_ALLOWED_ATTR must NOT include "class" — LLM-controlled class names can hijack global app.css selectors. See decisions audit pass-2.',
	);
	assert.match(
		source,
		/ALLOW_DATA_ATTR\s*:\s*false/,
		'CoachChat sanitiser must set ALLOW_DATA_ATTR=false — data-* attributes are a class-equivalent escape hatch.',
	);
	assert.match(
		source,
		/afterSanitizeAttributes[\s\S]{0,400}target['"\s,:=]+_blank/,
		'CoachChat sanitiser must force target=_blank on every <a> via afterSanitizeAttributes.',
	);
	assert.match(
		source,
		/afterSanitizeAttributes[\s\S]{0,400}noopener/,
		'CoachChat sanitiser must force rel="noopener" on every <a> — closes the window.opener reverse-tab phishing vector.',
	);
});

test('CoachChat DOMPurify config locks ALLOWED_URI_REGEXP to https/http/mailto', () => {
	// Reason: DOMPurify's default URI regexp is permissive — it accepts
	// `tel:`, `sms:`, `xmpp:`, `cid:`, `matrix:`, `callto:` on hrefs.
	// A coach response containing `[call](tel:+1...)` would otherwise
	// open the OS dialer on mobile browsers. This guard pins the
	// allow-list to the same scheme set as the mobile `_onCoachLinkTap`
	// (http, https, mailto). /audit/all xss Medium 2026-05-07.
	const source = read('src/lib/coach/markdown.ts');
	assert.match(
		source,
		/ALLOWED_URI_REGEXP\s*:\s*\/\^[^/]*https?[^/]*mailto[^/]*\//i,
		'CoachChat sanitiser must set ALLOWED_URI_REGEXP to /^(?:https?|mailto):/i. Removing it re-opens the tel:/sms:/xmpp: surface.',
	);
});

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
	// Reason: the client-side bypass in `$lib/features.ts::bypassEnabled`
	// mirrors the server gate in `/api/coach/+server.ts`. Loosening any
	// one of (vite dev, local Supabase URL, literal 'true' env var) to
	// `||` re-opens the gate in production builds — a vendored
	// PUBLIC_BYPASS_PAYWALL=true env in a misbuilt artefact would
	// silently unlock Pro screens for free users.
	const source = read('src/lib/features.ts');
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

test('isLocked() fails closed on unknown tier (default = locked)', () => {
	// Reason: a transient auth-store load shouldn't briefly unlock a
	// Pro-only screen. `isLocked(feature)` reads `auth.isPro`, which is
	// false during loading; the implementation must return `!isPro()` so
	// the gate stays armed until the profile lands. Pinned because a
	// subtle refactor (e.g. checking `auth.user.tier === 'free'`)
	// inverts to "default unlocked" when `auth.user` is null.
	const source = read('src/lib/features.ts');
	const block = source.match(/export function isLocked[\s\S]*?\n\}/);
	assert.ok(block, 'Could not locate isLocked() in features.ts.');
	assert.match(
		block![0],
		/!isPro\(\)/,
		'isLocked() must return !isPro() for Pro-only keys so an unknown tier defaults to locked.',
	);
});

test('Mobile coach screen sends `x-supabase-authorization`, not `Authorization`', () => {
	// Reason: production Lambda's Function URL is AWS_IAM-auth — CloudFront
	// signs `Authorization` via sigv4, so forwarding the viewer JWT in
	// that slot collides with the signature. The pass-2 fix (commit
	// 46ea5b5) flipped the mobile client to send `x-supabase-authorization`
	// matching the dev SvelteKit endpoint. Pinned because reverting to
	// `Authorization` fails for every production user with no local-dev
	// signal.
	for (const path of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const source = read(path);
		assert.match(
			source,
			/['"]x-supabase-authorization['"]/,
			`${path} must send the user JWT in the x-supabase-authorization header — production Lambda OAC signs Authorization.`,
		);
	}
});

test('Mobile coach markdown allowlists http(s) + mailto schemes only', () => {
	// Reason: flutter_markdown's default onTapLink calls url_launcher on
	// every URI including `javascript:`, `file:`, `data:`. The web path
	// strips those via DOMPurify; mobile didn't until pass-2 (commit
	// 54ef7ce). The allowlist must include http + https + mailto only —
	// adding `tel:` etc. would silently widen the surface.
	for (const path of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const source = read(path);
		const allowMatch = source.match(/allowedSchemes\s*=\s*\{([^}]*)\}/);
		assert.ok(
			allowMatch,
			`${path} must declare an explicit allowedSchemes set for the coach onTapLink handler.`,
		);
		const set = allowMatch![1];
		assert.match(set, /['"]http['"]/, `${path}: allowedSchemes must include 'http'.`);
		assert.match(set, /['"]https['"]/, `${path}: allowedSchemes must include 'https'.`);
		assert.match(set, /['"]mailto['"]/, `${path}: allowedSchemes must include 'mailto'.`);
		// Hard rules — none of these may appear.
		for (const banned of ['javascript', 'file', 'data', 'tel']) {
			assert.doesNotMatch(
				set,
				new RegExp(`['"]${banned}['"]`),
				`${path}: allowedSchemes must NOT include '${banned}' — see audit pass-2 commit 54ef7ce.`,
			);
		}
	}
});

test('Watch clients carry no hardcoded SUPABASE_ANON_KEY default', () => {
	// Reason: pass-2 hardening (commit 51046c2) cleared the local-stack
	// publishable key out of both watch fallbacks. The literal still
	// lives in git history, so a reverted "convenience default" lets
	// an unprovisioned debug build silently authenticate against
	// whichever stack the literal pointed at — including production
	// after the value rotates. Empty defaults fail the network call
	// loudly, which is the desired behaviour for a misconfigured build.
	//
	// Wear OS: build.gradle.kts must default SUPABASE_ANON_KEY to "".
	// watchOS: SupabaseService.swift's `private var anonKey` must
	// default to "".
	const wearGradle = read('../watch_wear/android/app/build.gradle.kts');
	assert.match(
		wearGradle,
		/SUPABASE_ANON_KEY['"\s)]+as\s+String\?\)\s*\n?\s*\?\:\s*""/,
		'Wear OS build.gradle.kts must default SUPABASE_ANON_KEY to "" — see audit pass-2 commit 51046c2.',
	);
	// And no JWT-shaped literal anywhere in the file (catches a
	// drive-by paste that re-introduces the hardcoded key).
	assert.doesNotMatch(
		wearGradle,
		/eyJ[A-Za-z0-9_-]{20,}/,
		'Wear OS build.gradle.kts must not contain any JWT-shaped literal — that pattern is a hardcoded supabase anon key.',
	);
	const watchSwift = read('../watch_ios/WatchApp/SupabaseService.swift');
	assert.match(
		watchSwift,
		/private\s+var\s+anonKey\s*=\s*""/,
		'watchOS SupabaseService.swift must default `anonKey` to "" — see audit pass-2 commit 51046c2.',
	);
	assert.doesNotMatch(
		watchSwift,
		/eyJ[A-Za-z0-9_-]{20,}/,
		'watchOS SupabaseService.swift must not contain any JWT-shaped literal — that pattern is a hardcoded supabase anon key.',
	);
});

test('CloudFront CSP drops unsafe-eval and bounds XSS gadget surface', () => {
	// Reason: pass-2 hardening (commit 624bc00) tightened the CSP on
	// the CloudFront response-headers policy. unsafe-eval is gone (the
	// static SvelteKit build does not eval); object-src 'none',
	// base-uri 'self', form-action 'self', frame-ancestors 'none' all
	// bound the surface an XSS gadget could reach. Reverting any one
	// reopens a class of attack:
	//   - object-src: SVG-embedded scripts via <object>/<embed>
	//   - base-uri: <base href> redirect of every relative URL
	//   - form-action: form data exfiltration to attacker-origin
	//   - frame-ancestors: clickjack via <iframe> embed
	const tf = read('../../infra/modules/web-stack/main.tf');
	// Find the content_security_policy block.
	const cspMatch = tf.match(
		/content_security_policy\s*=\s*join\([^)]*?\[([\s\S]*?)\]\s*\)/m,
	);
	assert.ok(
		cspMatch,
		'Could not locate content_security_policy in infra/modules/web-stack/main.tf — has it been restructured?',
	);
	const csp = cspMatch![1];
	assert.doesNotMatch(
		csp,
		/'unsafe-eval'/,
		"CSP must not include 'unsafe-eval' — the static SvelteKit build does not eval. Pass-2 commit 624bc00.",
	);
	for (const directive of [
		'object-src',
		'base-uri',
		'form-action',
		'frame-ancestors',
	]) {
		assert.match(
			csp,
			new RegExp(directive),
			`CSP must include the ${directive} directive — pass-2 commit 624bc00.`,
		);
	}
	// Sentry browser SDK posts errors here — without this connect-src
	// entry, every Sentry breadcrumb is silently CSP-blocked
	// (regression caught by /audit/infra M2).
	assert.match(
		csp,
		/\*\.ingest\.sentry\.io/,
		'CSP connect-src must include https://*.ingest.sentry.io — Sentry browser SDK posts errors there.',
	);
});

test('CloudFront Permissions-Policy disables sensors / payment / FLoC + Privacy Sandbox', () => {
	// Reason: pass-2 commit 624bc00 added a Permissions-Policy header
	// disabling APIs the app doesn't use. An XSS-injected
	// `document.browsingTopics()` would otherwise execute and leak the
	// user's interest cohort; same for accelerometer / geolocation
	// (cross-origin contexts) / payment-request-API-driven phishing.
	const tf = read('../../infra/modules/web-stack/main.tf');
	const ppMatch = tf.match(
		/header\s*=\s*"Permissions-Policy"[\s\S]*?value\s*=\s*"([^"]+)"/m,
	);
	assert.ok(
		ppMatch,
		'Could not locate the Permissions-Policy custom header in infra/modules/web-stack/main.tf.',
	);
	const policy = ppMatch![1];
	for (const directive of [
		'accelerometer',
		'attribution-reporting',
		'browsing-topics',
		'camera',
		'gyroscope',
		'interest-cohort',
		'magnetometer',
		'microphone',
		'payment',
		'usb',
	]) {
		assert.match(
			policy,
			new RegExp(`${directive}=\\(\\)`),
			`Permissions-Policy must disable ${directive} — pass-2 commit 624bc00.`,
		);
	}
});

test('Coach Lambda Function URL is AWS_IAM-auth + CloudFront-only', () => {
	// Reason: pass-1 /audit/infra H3 (commit 6614d89) flipped the
	// Function URL from authorization_type=NONE to AWS_IAM and added
	// a CloudFront OAC of type "lambda" that signs every request.
	// Reverting any of these makes the .lambda-url.* hostname directly
	// reachable by anyone — bypasses CloudFront, the WAF tier, and
	// every CSP / per-IP guard the distribution applies.
	const tf = read('../../infra/modules/web-stack/main.tf');
	assert.match(
		tf,
		/aws_lambda_function_url[\s\S]*?authorization_type\s*=\s*"AWS_IAM"/,
		'Lambda Function URL must use authorization_type=AWS_IAM — pass-1 /audit/infra H3.',
	);
	assert.match(
		tf,
		/aws_cloudfront_origin_access_control[\s\S]*?origin_access_control_origin_type\s*=\s*"lambda"/,
		'CloudFront must have an origin_access_control of type "lambda" so it sigv4-signs every Function URL request.',
	);
	assert.match(
		tf,
		/aws_lambda_permission[\s\S]*?principal\s*=\s*"cloudfront\.amazonaws\.com"/,
		'aws_lambda_permission must restrict principal to cloudfront.amazonaws.com (was * before pass-1 /audit/infra H3).',
	);
	assert.match(
		tf,
		/aws_lambda_permission[\s\S]*?function_url_auth_type\s*=\s*"AWS_IAM"/,
		'aws_lambda_permission must declare function_url_auth_type=AWS_IAM.',
	);
});

test('S3 site bucket lifecycle aborts incomplete multipart uploads', () => {
	// Reason: pass-2 commit 624bc00 added an abort-incomplete-multipart
	// lifecycle rule. Without it an interrupted deploy (CI killed
	// mid-upload) leaks storage forever — multipart parts don't show
	// in `aws s3 ls` so they're invisible to operators but accrue cost.
	const tf = read('../../infra/modules/web-stack/main.tf');
	assert.match(
		tf,
		/abort_incomplete_multipart_upload[\s\S]*?days_after_initiation\s*=\s*\d+/,
		'site bucket must have an abort_incomplete_multipart_upload lifecycle rule — pass-2 commit 624bc00.',
	);
});

test('OIDC deploy roles carry default Project / Stack / ManagedBy tags', () => {
	// Reason: pass-2 commit 624bc00 synthesised default tags via a
	// `oidc_tags` local so callers don't have to remember to set them.
	// Cost-allocation reports + blast-radius audits depend on every
	// resource in the OIDC stack carrying these — silent drift is the
	// regression to catch.
	const tf = read('../../infra/github-oidc/main.tf');
	const localsMatch = tf.match(/locals\s*\{[\s\S]*?oidc_tags\s*=\s*merge\(\s*\{([\s\S]*?)\}/);
	assert.ok(localsMatch, 'Could not locate oidc_tags merge() in infra/github-oidc/main.tf.');
	const tags = localsMatch![1];
	for (const key of ['Project', 'Stack', 'ManagedBy']) {
		assert.match(
			tags,
			new RegExp(`${key}\\s*=`),
			`oidc_tags local must include the ${key} default — pass-2 commit 624bc00.`,
		);
	}
	// Each deploy role must apply Environment via merge so prod /
	// preview spend is distinguishable.
	assert.match(
		tf,
		/aws_iam_role"\s+"deploy_prod"[\s\S]*?tags\s*=\s*merge\(local\.oidc_tags,\s*\{\s*Environment\s*=\s*"prod"/,
		'deploy_prod role must merge oidc_tags with Environment="prod".',
	);
	assert.match(
		tf,
		/aws_iam_role"\s+"deploy_preview"[\s\S]*?tags\s*=\s*merge\(local\.oidc_tags,\s*\{\s*Environment\s*=\s*"preview"/,
		'deploy_preview role must merge oidc_tags with Environment="preview".',
	);
});

test('Coach endpoint enforces a 256 KB body cap on both wrappers', () => {
	// Reason: pass-2 commit a2ea656 originally added COACH_BODY_LIMIT_BYTES
	// at both wrappers — SvelteKit dev /api/coach/+server.ts AND the
	// production Lambda lambda/coach/src/index.ts.
	//
	// audit/auth (May 2026) flagged that the Lambda was checking
	// `bodyStr.length` (UTF-16 code units), letting multi-byte UTF-8
	// payloads ~3x the cap sail through. The two wrappers diverged.
	//
	// Fix: a single $lib/coach/body.ts owns the constant + the
	// size-check helper, and both wrappers import + call it. This
	// guard now pins the import-and-use shape so the constant can't
	// be re-inlined per-wrapper (which is what allowed the drift in
	// the first place).
	const body = read('src/lib/coach/body.ts');
	assert.match(
		body,
		/COACH_BODY_LIMIT_BYTES\s*=\s*256\s*\*\s*1024/,
		'$lib/coach/body.ts must declare COACH_BODY_LIMIT_BYTES = 256 * 1024.',
	);
	for (const path of [
		'src/routes/api/coach/+server.ts',
		'lambda/coach/src/index.ts',
	]) {
		const source = read(path);
		// SvelteKit dev path can use the $lib alias; the Lambda can't
		// (the alias is resolved by Vite, not by the esbuild bundler
		// used for the Lambda artifact). Accept either form.
		assert.match(
			source,
			/from\s+['"](?:\$lib\/coach\/body|\.\.\/+(?:\.\.\/+)*src\/lib\/coach\/body)['"]/,
			`${path} must import the body helper from $lib/coach/body — ` +
				'not re-inline the constant (re-inlining is what allowed ' +
				'the audit/auth May 2026 drift).',
		);
		assert.match(
			source,
			/COACH_BODY_LIMIT_BYTES/,
			`${path} must reference COACH_BODY_LIMIT_BYTES so the size ` +
				'check is wired to the shared cap.',
		);
		assert.match(
			source,
			/(decodeLambdaBody|checkBodyByteLimit)\s*\(/,
			`${path} must call decodeLambdaBody (Lambda) or ` +
				'checkBodyByteLimit (SvelteKit) — these are byte-counted, ' +
				'unlike bodyStr.length which counts UTF-16 code units.',
		);
	}
});

test('Coach 401 / 503 error responses don\'t leak provider / GoTrue internals', () => {
	// Reason: pass-2 commits 2d2a24a + a2ea656 stripped operator hints
	// from the user-visible 401 / 503 messages. The 503 used to echo
	// the raw COACH_PROVIDER env-var name to any unauthenticated
	// caller; the 401 used to return GoTrue's error string which can
	// carry JWT-shape details an attacker can use as a probe oracle.
	// Both are now generic on the wire and verbose only in
	// console.error / CloudWatch.
	const handler = read('src/lib/coach/handler.ts');
	// 503: must NOT contain a string-template that interpolates the
	// provider name into the user-facing error.
	assert.doesNotMatch(
		handler,
		/jsonError\(503,\s*[`'"][^'"`]*\$\{[^}]*provider[^}]*\}/,
		'503 user-facing message must not interpolate the provider value (operator hint goes to console.error).',
	);
	// 401: the user-facing string must be the static "not
	// authenticated" — no GoTrue error spread into the body.
	assert.match(
		handler,
		/jsonError\(401,\s*['"]not authenticated['"]\s*\)/,
		'401 must return the static "not authenticated" — pass-2 commit a2ea656 closed the GoTrue oracle.',
	);
});

test('Coach pre-handshake daily-limit placeholder matches the server free cap', () => {
	// Reason: pass-2 commit a2ea656 fixed a drift where the web placeholder
	// said "10 of 10 remaining" while the server returned "5". The
	// placeholder matters because users see it for the half-second
	// before the SSE meta event lands. Pinned so a future tier change
	// (5→8) updates both surfaces in lockstep with the server.
	// Source of truth: TIER_LIMITS.free.dailyLimit in coach/types.ts.
	const types = read('src/lib/coach/types.ts');
	const tierMatch = types.match(/free:\s*\{[^}]*dailyLimit:\s*(\d+)/);
	assert.ok(tierMatch, 'Could not extract TIER_LIMITS.free.dailyLimit from coach/types.ts.');
	const serverCap = tierMatch![1];
	assert.equal(serverCap, '5', 'Free dailyLimit should be 5 (audit cost-controls baseline).');
	// Web placeholder.
	const chat = read('src/lib/components/CoachChat.svelte');
	assert.match(
		chat,
		new RegExp(`DEFAULT_DAILY_LIMIT\\s*=\\s*${serverCap}\\b`),
		`CoachChat.svelte DEFAULT_DAILY_LIMIT must match the server cap (${serverCap}) — pass-2 commit a2ea656.`,
	);
	// Mobile placeholder, both Dart twins.
	for (const p of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const dart = read(p);
		assert.match(
			dart,
			new RegExp(`_defaultDailyLimit\\s*=\\s*${serverCap}\\b`),
			`${p} _defaultDailyLimit must match the server cap (${serverCap}).`,
		);
	}
});

test('clip-public-track rate-limit calls fail closed on RPC error', () => {
	// Reason: pass-3 commit d10deeb flipped both buckets (per-user and
	// per-IP-anon) to failClosed: true. The anon path is the abuse
	// surface — a transient DB blip on the rate-limit RPC must not
	// remove the only IP-level guard. fail-open here would let an
	// attacker bypass the cap during any DB hiccup.
	const ef = read('../backend/supabase/functions/clip-public-track/index.ts');
	// Find every checkRateLimit call and assert each carries
	// failClosed: true. Use a regex that captures the option block.
	const calls = [...ef.matchAll(/checkRateLimit\([\s\S]*?\)/g)];
	assert.ok(
		calls.length >= 2,
		'Expected at least two checkRateLimit calls in clip-public-track (per-user + anon).',
	);
	for (const m of calls) {
		assert.match(
			m[0],
			/failClosed:\s*true/,
			'Every checkRateLimit call in clip-public-track must pass failClosed: true — pass-3 commit d10deeb.',
		);
	}
});

test('export-data validates track_url against the canonical Storage path', () => {
	// Reason: pass-2 commit 978b4c9 added a runtime backstop ahead of
	// the service-role Storage download. RLS already prevents cross-
	// user reads, but a corrupt or legacy row would have fed an
	// unconstrained string into the downloader (path traversal via
	// `../../other-user/...` if the bucket-prefix policy regressed).
	// 20260621_001 added a CHECK constraint on the column shape — this
	// assertion is the runtime backstop that catches a row that
	// somehow bypasses the CHECK.
	const ef = read('../backend/supabase/functions/export-data/index.ts');
	assert.match(
		ef,
		/expectedTrackUrl\s*=\s*`\$\{[^}]*user_id[^}]*\}\/\$\{[^}]*\.id[^}]*\}\.json\.gz`/,
		'export-data must build expectedTrackUrl as `${user_id}/${run_id}.json.gz` — pass-2 commit 978b4c9.',
	);
	assert.match(
		ef,
		/track_url\s*!==\s*expectedTrackUrl/,
		'export-data must skip rows whose track_url does not match the canonical pattern.',
	);
});

test('release-web.yml runs the production-env guard before npm run build', () => {
	// Reason: the guard exists to fail loud on a missing PUBLIC_* secret
	// rather than ship a static artifact whose share / og pages all
	// resolve to empty. The workflow MUST invoke
	// `apps/web/scripts/check_production_env.mjs` ahead of the build
	// step, and it MUST thread every secret the helper enforces
	// (SUPABASE_URL, SUPABASE_ANON_KEY, MAPTILER_KEY,
	// REVENUECAT_WEB_API_KEY) into the step's env block — otherwise the
	// helper sees empty strings and fails the release on every tag.
	const wf = read('../../.github/workflows/release-web.yml');
	const guardIdx = wf.indexOf('check_production_env.mjs');
	const buildIdx = wf.indexOf('npm run build --workspace=apps/web');
	assert.ok(guardIdx >= 0, 'release-web.yml must invoke check_production_env.mjs.');
	assert.ok(buildIdx >= 0, 'release-web.yml must run `npm run build --workspace=apps/web`.');
	assert.ok(
		guardIdx < buildIdx,
		'release-web.yml must invoke check_production_env.mjs BEFORE `npm run build` — failing after build defeats the guard.',
	);
	// Locate the guard step's env block. Match from the `node` line
	// backward to the nearest `env:` keyword.
	const guardStep = wf.match(
		/env:\s*\n([\s\S]*?)\n\s*run:\s*node apps\/web\/scripts\/check_production_env\.mjs/,
	);
	assert.ok(
		guardStep,
		'Could not locate the env: block immediately preceding `node apps/web/scripts/check_production_env.mjs` in release-web.yml.',
	);
	const env = guardStep![1];
	for (const key of [
		'PUBLIC_SUPABASE_URL',
		'PUBLIC_SUPABASE_ANON_KEY',
		'PUBLIC_MAPTILER_KEY',
		'PUBLIC_REVENUECAT_WEB_API_KEY',
	]) {
		assert.match(
			env,
			new RegExp(`${key}:\\s*\\$\\{\\{\\s*secrets\\.${key}\\s*\\}\\}`),
			`release-web.yml guard step must pass ${key} from the repo secret. Adding a new required key to check_production_env.mjs without wiring the secret here fails the release on every tag.`,
		);
	}
});

test('createClub + saveRoute + submitReport all translate P0001 via the shared helper', () => {
	// Reason: every P0001 rate-limit bucket on the web client must route
	// through `rateLimitErrorMessage` so users see a "wait N minutes" line
	// instead of the raw `rate limit exceeded for <bucket>, retry in Ns`
	// postgres exception. Previously each call-site carried its own ad-hoc
	// translation (e.g. submitReport's old "Too many reports — please wait
	// a few minutes"); centralising the rule means a future bucket lands
	// in one place + behaves identically across clubs / routes / reports.
	// Twin path on Dart is enforced by mobile_android's architecture-guard
	// suite.
	const source = read('src/lib/data.ts');
	assert.match(
		source,
		/import\s+\{\s*rateLimitErrorMessage\s*\}\s+from\s+['"]\.\/rate_limit_errors['"]/,
		'data.ts must import rateLimitErrorMessage from ./rate_limit_errors.',
	);
	// Slice each function body and assert the helper appears with the
	// "throw new Error(friendly)" follow-up. Using the same bodyAfter
	// landmark approach as the public-runs test above so a nested type
	// literal can't trip a naive `^}` regex.
	function bodyAfter(needle: string, until: string): string {
		const start = source.indexOf(needle);
		assert.ok(start >= 0, `Could not locate '${needle}' — rename?`);
		const end = source.indexOf(until, start + needle.length);
		assert.ok(
			end > start,
			`Could not locate landmark '${until}' after '${needle}'`,
		);
		return source.slice(start, end);
	}
	const saveRouteBody = bodyAfter(
		'export async function saveRoute(',
		'export async function deleteRoute(',
	);
	const createClubBody = bodyAfter(
		'export async function createClub(',
		'function genToken(',
	);
	const submitReportBody = bodyAfter(
		'export async function submitReport(',
		// submitReport returns `data as string` and ends — the next
		// landmark after the function is the closing semicolon's newline.
		// Anchor on the helper's RETURN statement so the slice is bounded.
		'return data as string;',
	);
	for (const [name, body] of [
		['saveRoute', saveRouteBody],
		['createClub', createClubBody],
		['submitReport', submitReportBody],
	] as const) {
		assert.match(
			body,
			/rateLimitErrorMessage\(/,
			`${name} must call rateLimitErrorMessage — every P0001 bucket goes through the shared helper.`,
		);
		assert.match(
			body,
			/if\s*\(friendly\)\s*throw\s+new\s+Error\(friendly\)/,
			`${name} must throw the friendly string when the helper recognises the bucket. Skipping the throw drops back to the raw postgres exception.`,
		);
	}
});

test('/cookie-notice carries a Manage-cookie-preferences button wired to consent.reset', () => {
	// Reason: audit/cookie-consent (May 2026). Pre-fix the page told
	// users to use a "Cookie settings" link in the footer that did
	// not exist anywhere in the app. GDPR Art 7(3) requires withdrawal
	// to be as easy as giving consent; a missing UI is an illusory
	// right that a DPA audit would reject.
	const source = read('src/routes/cookie-notice/+page.svelte');
	assert.match(
		source,
		/consent\.reset\(\)/,
		'/cookie-notice must call consent.reset() to clear the stored choice',
	);
	assert.match(
		source,
		/data-testid="manage-cookie-preferences"/,
		'/cookie-notice must surface a manage-cookie-preferences button so ' +
			'the GDPR Art 7(3) withdrawal path has a discoverable test handle',
	);
	// Strip the <script> block so the doesNotMatch check fires on
	// rendered copy only — the comment in the script intentionally
	// references the old phrasing for history.
	const renderedOnly = source.replace(/<script\b[\s\S]*?<\/script>/g, '');
	assert.doesNotMatch(
		renderedOnly,
		/"Cookie settings" link in the footer/,
		"/cookie-notice rendered copy must not point users at a footer " +
			"'Cookie settings' link that does not exist " +
			'(audit/cookie-consent pre-fix wording)',
	);
});

test('routing helpers refuse to fall back to router.project-osrm.org in prod', () => {
	// Reason: audit/third-party-data-flows (May 2026). Pre-fix, the
	// `OSRM_BASE_URL = (publicEnv.PUBLIC_OSRM_URL || 'https://router.project-osrm.org')`
	// fallback meant a missing env var silently shipped user waypoints
	// + IPs to a community endpoint with no DPA. assertOsrmConfiguredForProd
	// throws when dev=false and the env var resolves to the demo URL.
	const source = read('src/lib/routing.ts');
	assert.match(
		source,
		/export function assertOsrmConfiguredForProd/,
		'routing.ts must declare assertOsrmConfiguredForProd',
	);
	for (const fn of ['snapToRoad', 'fetchRoute', 'fetchFullRoute']) {
		const body = source.match(
			new RegExp(`async function ${fn}\\b[\\s\\S]*?\\n\\}`),
		)?.[0];
		assert.ok(body, `routing.ts missing function ${fn}`);
		assert.match(
			body!,
			/assertOsrmConfiguredForProd\(\)/,
			`${fn} must call assertOsrmConfiguredForProd() before issuing ` +
				'an OSRM fetch — silent fallback to the demo endpoint is a ' +
				'GDPR Art 28 violation.',
		);
	}

	// RouteBuilder.svelte builds OSRM URLs inline (custom retry +
	// batching + radius / version cancellation) instead of going
	// through the helper functions. The self-audit caught that the
	// assertion above was therefore not reachable for the route-
	// builder code path. Both call sites in the component now
	// assert too.
	const rb = read('src/lib/components/RouteBuilder.svelte');
	const rbMatches = rb.match(/assertOsrmConfiguredForProd\(\)/g) ?? [];
	assert.ok(
		rbMatches.length >= 2,
		'RouteBuilder.svelte must call assertOsrmConfiguredForProd() at ' +
			'each OSRM-fetch entry point (snapWaypointsToRoads + ' +
			'recalculateRoute). Found ' +
			rbMatches.length +
			' call sites.',
	);
});

test('fetchRunGear enumerates only public-safe columns on the gear join', () => {
	// Reason: audit/public-rows (May 2026). When run_gear visibility
	// extends to non-owners of public runs (the SELECT policy is
	// is_run_visible_to-gated), a `gear:gear_id(*)` join would
	// stream owner-private columns (`notes`, `purchased_at`,
	// `retired_at`, `target_distance_m`) to any viewer of the public
	// run if the underlying `gear` RLS ever drifts. Pin the
	// enumerated allowlist to prevent the column set from regressing
	// back to `*`.
	const source = read('src/lib/data.ts');
	assert.match(
		source,
		/PUBLIC_GEAR_COLUMNS\s*=\s*['"]id,\s*kind,\s*name,\s*brand,\s*model['"]/,
		'data.ts must declare PUBLIC_GEAR_COLUMNS limited to ' +
			'(id, kind, name, brand, model) — the gear join in fetchRunGear ' +
			'is reachable from non-owner viewers of public runs.',
	);
	assert.doesNotMatch(
		source,
		/\.select\(['"`]gear:gear_id\(\*\)['"`]\)/,
		'fetchRunGear must not select gear:gear_id(*) — use ' +
			'PUBLIC_GEAR_COLUMNS instead (audit/public-rows).',
	);
});

test('backup restore strips server-managed profile fields', () => {
	// Reason: 20260718_001 INSERT WITH CHECK + 20260624_001 UPDATE
	// trigger reject any write that touches subscription_tier /
	// subscription_at / parkrun_number from a non-service-role context.
	// Without an explicit strip, the upsert in restoreBackup silently
	// errors and the rest of the profile (display_name, avatar_url,
	// preferred_unit) never lands. Pinned because the strip is invisible
	// happy-path behaviour — a future writer that drops it won't see a
	// failed test, just a silent restore regression.
	for (const path of [
		'src/lib/backup.ts',
		'../mobile_android/lib/backup.dart',
		'../mobile_ios/lib/backup.dart',
	]) {
		const source = read(path);
		for (const field of [
			'subscription_tier',
			'subscription_at',
			'parkrun_number',
		]) {
			assert.match(
				source,
				new RegExp(field),
				`${path} must reference ${field} (the restore strip) — the 20260718_001 / 20260624_001 server-side rejects fail silently otherwise.`,
			);
		}
	}
});
