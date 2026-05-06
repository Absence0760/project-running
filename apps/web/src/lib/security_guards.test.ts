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

test('feed page passes runId + ownerUserId to RunTrackPreview', () => {
	// Reason: the EF non-owner clip path needs the run id (server
	// resolves track_url + clips inline). Without the prop,
	// RunTrackPreview can't reach the EF and renders a placeholder
	// instead of the clipped polyline.
	const source = read('src/routes/feed/+page.svelte');
	assert.match(
		source,
		/<RunTrackPreview[^>]*runId=/s,
		'Feed page must thread the run id into RunTrackPreview so the clip-public-track EF can resolve it.',
	);
	assert.match(
		source,
		/<RunTrackPreview[^>]*ownerUserId=/s,
		'Feed page must thread the run owner id into RunTrackPreview so the privacy-zone clip kicks in.',
	);
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
