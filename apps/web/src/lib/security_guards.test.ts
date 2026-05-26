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
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

function readFileSyncDeps(): { readdirSync: typeof readdirSync } {
	return { readdirSync };
}
const __dirname = dirname(fileURLToPath(import.meta.url));

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

test('Lambda /api/coach hardcodes bypassPaywallEnabled: false (no env read)', () => {
	// Reason: the SvelteKit `/api/coach/+server.ts` runs in local dev and
	// honours BYPASS_PAYWALL behind a three-condition AND gate (pinned
	// above). The production AWS Lambda wrapper at
	// `apps/web/lambda/coach/src/index.ts` is the only path that runs
	// against a real Supabase project, and it MUST hardcode the flag to
	// `false` regardless of any env var. A subtle regression — switching
	// to `process.env.BYPASS_PAYWALL === 'true'` to "match the SvelteKit
	// gate" — would let a stray Lambda env var unlock the daily cap for
	// every free user in production. The three-condition AND gate in the
	// SvelteKit handler is irrelevant in Lambda because the conditions
	// don't apply (Lambda is `NODE_ENV=production`, points at a real
	// Supabase URL), but the right defence is to never read the env at
	// all in the Lambda path.
	const source = read('lambda/coach/src/index.ts');
	const cfgMatch = source.match(/bypassPaywallEnabled\s*:\s*([^,\n]+)/);
	assert.ok(
		cfgMatch,
		'Could not locate bypassPaywallEnabled in lambda/coach/src/index.ts CoachConfig — has the field been renamed?',
	);
	const value = cfgMatch![1].trim();
	assert.strictEqual(
		value,
		'false',
		`Lambda CoachConfig.bypassPaywallEnabled must be the literal "false", was "${value}". ` +
			'Reading process.env or a runtime flag here lets a stray Lambda env var unlock the paywall for every prod user.',
	);
	// Belt-and-braces: no `process.env.BYPASS_PAYWALL` anywhere in the
	// Lambda source, even off the config object.
	assert.doesNotMatch(
		source,
		/process\.env\.[A-Z_]*BYPASS_PAYWALL/,
		'Lambda must not reference process.env.BYPASS_PAYWALL (or PUBLIC_BYPASS_PAYWALL) at all — there is no dev-mode condition that would safely guard it in a Lambda runtime.',
	);
});

test('run-photo delete sites sweep BOTH storage_path and thumb_512_path', () => {
	// Reason: the worker-generated 512-wide thumbnail (column
	// `thumb_512_path` added in migration 20260826_001) is a separate
	// Storage object from the original upload. Until the audit:storage
	// 2026-05-25 pass, both `deleteRun` (cascade-delete) and
	// `deleteRunPhoto` (single-photo) only swept `storage_path` — the
	// thumbnail blob persisted in the bucket indefinitely. The row
	// cascade-delete kills the run_photos row, so the Storage SELECT
	// policy hides the bytes (join through run_photos → empty), but the
	// blob continues to pay for storage cost + is a latent privacy
	// footprint. Pinning both call sites so a future "simplify the
	// select" refactor can't quietly reintroduce the orphan.
	const sources: Array<{ path: string; functionRe: RegExp; label: string }> = [
		{
			path: 'src/lib/data.ts',
			functionRe: /export async function deleteRun\(id: string\)[\s\S]*?\n\}/,
			label: 'deleteRun (web)',
		},
		{
			path: 'src/lib/data.ts',
			functionRe: /export async function deleteRunPhoto\(photoId: string\)[\s\S]*?\n\}/,
			label: 'deleteRunPhoto (web)',
		},
	];
	for (const { path, functionRe, label } of sources) {
		const source = read(path);
		const match = source.match(functionRe);
		assert.ok(match, `Could not locate ${label} in ${path} — has the function been renamed?`);
		const body = match![0];
		assert.match(
			body,
			/select\(['"`][^'"`]*storage_path[^'"`]*thumb_512_path/,
			`${label} must select both storage_path AND thumb_512_path from run_photos so the thumbnail blob is also swept. Without it, the 512-wide thumbnail orphans in the bucket indefinitely (audit:storage 2026-05-25 finding).`,
		);
		assert.match(
			body,
			/storage[\s\S]*?from\(['"]run-photos['"]\)[\s\S]*?\.remove\(/,
			`${label} must call storage.from('run-photos').remove(...) with the collected paths.`,
		);
	}

	// Mobile twin parity — same fix shape must land on api_client.dart
	// or the mobile path leaks orphans even when the web app cleans up.
	const apiClient = read('../../packages/api_client/lib/src/api_client.dart');
	assert.match(
		apiClient,
		/Future<void> deleteRun\(Run run\)[\s\S]*?colStoragePath[\s\S]*?colThumb512Path[\s\S]*?\}/,
		'api_client.dart#deleteRun must select both RunPhotoRow.colStoragePath AND RunPhotoRow.colThumb512Path — same orphan-cleanup contract as the web twin.',
	);
	assert.match(
		apiClient,
		/Future<void> deleteRunPhoto\(RunPhotoRow photo\)[\s\S]*?thumb512Path[\s\S]*?run-photos[\s\S]*?\.remove\(/,
		'api_client.dart#deleteRunPhoto must include photo.thumb512Path in the storage remove list.',
	);
});

test('Edge Functions do not log raw PostgrestError objects', () => {
  // Reason: PostgrestError objects carry `.message`, `.details`,
  // `.hint`, and `.code`. The `details` / `hint` fields can include
  // partial column values, constraint names, or row fragments. The
  // Supabase function-log aggregator is accessible to project
  // members (and exportable in some billing tiers), so a raw-object
  // log is schema/credential exposure even when the response to the
  // caller is clean. Pinned because audit:edge-functions 2026-05-25
  // caught four sites that had regressed from the .message pattern
  // used elsewhere in the same codebase.
  //
  // The check is conservative: it bans `console.error(..., name)` /
  // `console.error(..., nameErr)` where the trailing argument is a
  // bare identifier likely to be an error object. Allowed shapes:
  //   - `.message` / `?.message` accesses
  //   - `String(...)` wrappers
  //   - `e instanceof Error ? e.message : String(e)` ternaries
  //   - object literals (e.g. `{ status: ... }`)
  //   - string literals
  // — any of which scrubs the structured fields the leak relies on.
  const efDir = resolve(__dirname, '../../../backend/supabase/functions');
  const indexes = collectEdgeFunctionIndexes(efDir);
  assert.ok(
    indexes.length >= 6,
    `Expected at least 6 Edge Function index.ts files under ${efDir}, ` +
      `found ${indexes.length}. Has the directory layout moved?`,
  );

  const offenders: Array<{ path: string; line: number; call: string }> = [];
  // Match `console.error( … )` with a balanced-paren scan inside.
  const callRe = /console\.error\s*\(/g;
  for (const path of indexes) {
    const source = readFileSync(path, 'utf-8');
    let m: RegExpExecArray | null;
    while ((m = callRe.exec(source)) !== null) {
      const start = m.index + m[0].length;
      // Find the matching closing paren.
      let depth = 1;
      let i = start;
      while (depth > 0 && i < source.length) {
        const c = source[i];
        if (c === '(') depth++;
        else if (c === ')') depth--;
        i++;
      }
      const argText = source.slice(start, i - 1);
      // Split top-level by comma — only need the LAST arg (the error
      // value); commas inside string literals / template literals
      // are rare in console.error calls and over-counting just makes
      // the assertion stricter (false-positive direction is safe).
      const lastArg = lastTopLevelArg(argText).trim();
      if (looksLikeBareErrorIdentifier(lastArg)) {
        const lineNo = source.slice(0, m.index).split('\n').length;
        offenders.push({ path, line: lineNo, call: lastArg });
      }
    }
  }

  assert.strictEqual(
    offenders.length,
    0,
    'Edge Functions must not log raw error objects as the last arg ' +
      'of console.error — wrap with `.message`, `String(...)`, or ' +
      'the `e instanceof Error ? e.message : String(e)` pattern.\n' +
      `Offenders:\n${offenders.map((o) => `  ${o.path}:${o.line} → console.error(…, ${o.call})`).join('\n')}`,
  );
});

function collectEdgeFunctionIndexes(efDir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(efDir)) {
    if (name.startsWith('_')) continue; // _shared, etc.
    const candidate = resolve(efDir, name, 'index.ts');
    try {
      readFileSync(candidate);
      out.push(candidate);
    } catch {
      /* not a function dir (e.g. shared helpers); skip */
    }
  }
  return out;
}

function lastTopLevelArg(argText: string): string {
  // Walk forward, tracking nesting depth + string state. Return the
  // tail after the last top-level comma. Handles `(`, `[`, `{`,
  // template `${…}`, and single/double/backtick strings.
  let depth = 0;
  let lastCommaIdx = -1;
  let i = 0;
  while (i < argText.length) {
    const c = argText[i];
    if (c === '"' || c === "'" || c === '`') {
      const quote = c;
      i++;
      while (i < argText.length && argText[i] !== quote) {
        if (argText[i] === '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) lastCommaIdx = i;
    i++;
  }
  return lastCommaIdx === -1 ? argText : argText.slice(lastCommaIdx + 1);
}

function looksLikeBareErrorIdentifier(arg: string): boolean {
  // Strip a leading line comment / trailing line comment, then ask:
  // is this a bare identifier whose name signals an error object,
  // with no method access / wrapper?
  const stripped = arg.replace(/\/\/.*$/gm, '').trim();
  if (stripped.length === 0) return false;
  // Accept: anything containing `.message` / `?.message` / `String(` /
  // `instanceof Error` / `JSON.stringify` / object-literal `{` / array
  // literal `[` / string literal / number / template literal.
  if (
    stripped.includes('.message') ||
    stripped.includes('?.message') ||
    stripped.startsWith('String(') ||
    stripped.includes('instanceof Error') ||
    stripped.includes('JSON.stringify') ||
    stripped.startsWith('{') ||
    stripped.startsWith('[') ||
    stripped.startsWith('"') ||
    stripped.startsWith("'") ||
    stripped.startsWith('`') ||
    /^-?\d/.test(stripped)
  ) {
    return false;
  }
  // What's left is a bare identifier (or expression without any of the
  // accepted scrubbers). Flag it if the name suggests an error value.
  return /^[a-zA-Z_$][\w$]*$/.test(stripped) &&
    /(err|Err|error|Error)$/.test(stripped);
}

// ─── audit:deps May 2026 closeouts ───────────────────────────────────
// Three source-level dep-hygiene pins so version drift across Edge
// Functions can't silently accumulate. Each one walks every EF
// `index.ts` + `_shared/*.ts` as text and asserts a property the
// audit explicitly called out.

test('every Deno import in Edge Functions has a version pin', () => {
	// Reason: Deno fetches at module-resolution time, so an unpinned
	// `https://esm.sh/x` or `https://deno.land/std/...` import would
	// silently pull a different version on every cold start. The
	// audit:deps May 2026 sweep confirmed every import was pinned
	// today; this pin keeps it that way. Catches a future "let's see
	// what the latest version does" experiment that ships without a
	// version suffix.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const offenders: Array<{ file: string; line: number; url: string }> = [];
	function walk(dir: string): void {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			let stat;
			try {
				stat = readFileSync(full);
			} catch {
				continue;
			}
			// Best-effort directory detection via existsSync of a child;
			// use readdirSync inside try/catch instead.
			try {
				const entries = readdirSync(full);
				if (entries.length >= 0) {
					walk(full);
					continue;
				}
			} catch {
				/* not a directory; fall through to file handling */
			}
		}
	}
	// Above walk is verbose; simpler: collect every .ts file recursively
	// via a helper that uses readdirSync with file-type checks.
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				const entries = readdirSync(full);
				// It's a directory — recurse.
				collectTs(full, out);
				void entries;
			} catch {
				// Not a directory — check if it's a .ts file.
				if (full.endsWith('.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	assert.ok(tsFiles.length >= 8, `Expected ≥8 .ts files under ${efDir}, found ${tsFiles.length}.`);
	// Pattern: `from 'https://...'` — flag if no @version suffix appears
	// before the next slash or quote.
	const importRe = /from\s+['"](https:\/\/[^'"]+)['"]/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = importRe.exec(source)) !== null) {
			const url = m[1];
			// Acceptable shapes: ...@x.y.z/..., ...@x.y.z, ...@vx.y.z/...,
			// ...@<sha>/...
			// Anything without an @ before the next / or end is unpinned.
			// `v` prefix is common on deno.land/x/ (e.g. zipjs@v2.7.45),
			// SHA pins are 7-40 hex chars. Loose match covers both.
			const host = url.replace(/^https:\/\//, '').split('/')[0];
			const path_after_host = url.replace(/^https:\/\/[^/]+/, '');
			const hasVersionPin = /@v?[\d.]+/.test(url) || /@[0-9a-f]{7,40}\b/.test(url);
			if (!hasVersionPin) {
				const lineNo = source.slice(0, m.index).split('\n').length;
				offenders.push({ file: path, line: lineNo, url });
			}
			void host;
			void path_after_host;
		}
	}
	assert.strictEqual(
		offenders.length,
		0,
		'Every Deno import in Edge Functions must carry a @version pin. ' +
			'Unpinned imports re-resolve on every cold start — a supply-chain risk.\n' +
			`Offenders:\n${offenders.map((o) => `  ${o.file}:${o.line} → ${o.url}`).join('\n')}`,
	);
});

test('Edge Functions pin @supabase/supabase-js in lockstep', () => {
	// Reason: a partial bump where some EFs are at 2.105 and others at
	// 2.107 produces split behaviour on auth / RLS / Storage paths
	// (each major-line evolves its session handling differently).
	// Catches a one-off "I bumped this function but forgot the rest"
	// commit. The lockstep target lives in the production EFs; the
	// _shared/strava.ts + _shared/rate_limit.ts type-only imports must
	// match.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const versions = new Set<string>();
	const sites: Array<{ file: string; line: number; ver: string }> = [];
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				readdirSync(full);
				collectTs(full, out);
			} catch {
				if (full.endsWith('.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	const versionRe = /@supabase\/supabase-js@(\d+\.\d+\.\d+)/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = versionRe.exec(source)) !== null) {
			versions.add(m[1]);
			const lineNo = source.slice(0, m.index).split('\n').length;
			sites.push({ file: path, line: lineNo, ver: m[1] });
		}
	}
	assert.ok(sites.length >= 8, `Expected ≥8 supabase-js pins, found ${sites.length}.`);
	assert.strictEqual(
		versions.size,
		1,
		'Every Edge Function must pin @supabase/supabase-js to the SAME version. ' +
			`Found ${versions.size} distinct versions: ${[...versions].join(', ')}.\n` +
			`Sites:\n${sites.map((s) => `  ${s.file}:${s.line} → ${s.ver}`).join('\n')}`,
	);
});

test('Edge Functions use Deno.serve, not std http/server.ts', () => {
	// Reason: `std@0.177.0/http/server.ts` was the pre-Deno-1.35 way
	// to start an HTTP server. Since 1.35 the built-in `Deno.serve`
	// is the supported entry point — no supply-chain hop, no version
	// drift between prod (0.177) and tests (0.224) that we had before
	// the audit:deps May 2026 sweep. A future "let's restore the
	// import" change would re-introduce the drift; pin it out.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const offenders: Array<{ file: string; line: number }> = [];
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				readdirSync(full);
				collectTs(full, out);
			} catch {
				if (full.endsWith('.ts') && !full.endsWith('.test.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	const stdServeRe = /from\s+['"]https:\/\/deno\.land\/std@[\d.]+\/http\/server\.ts['"]/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = stdServeRe.exec(source)) !== null) {
			const lineNo = source.slice(0, m.index).split('\n').length;
			offenders.push({ file: path, line: lineNo });
		}
	}
	assert.strictEqual(
		offenders.length,
		0,
		'Edge Function source files (non-test) must NOT import `serve` from std/http — use built-in `Deno.serve` instead.\n' +
			`Offenders:\n${offenders.map((o) => `  ${o.file}:${o.line}`).join('\n')}`,
	);
});

// ─── audit:cost-controls May 2026 closeouts ──────────────────────────
// Six source-level pins on the Terraform IaC so cost-control regressions
// fail CI rather than waiting for the bill at end of month. Each test
// reads infra/* as text and asserts a property that the audit explicitly
// called out.

test('prod env wires alert_emails into the web-stack module', () => {
	// Reason: prod has tight validation on var.alert_emails (non-empty
	// + placeholder-rejected) but if main.tf didn't pass the variable
	// through, the module would default to [] and alarms would fire
	// into an empty SNS topic. The wire is the load-bearing link.
	const prodMain = read('../../infra/envs/prod/main.tf');
	const prodVars = read('../../infra/envs/prod/variables.tf');
	assert.match(
		prodMain,
		/alert_emails\s*=\s*var\.alert_emails/,
		'infra/envs/prod/main.tf must pass alert_emails into the web-stack module — without the wire, validated input never reaches the alarm subscribers.',
	);
	assert.match(
		prodVars,
		/variable\s+"alert_emails"[\s\S]*?validation\s*\{[\s\S]*?length\(var\.alert_emails\)\s*>\s*0/,
		'infra/envs/prod/variables.tf alert_emails must have a non-empty-list validation block.',
	);
	// Placeholder-rejection check accepts either the `endswith`
	// form or the `can(regex())` form used in prod today. Either is
	// acceptable; the load-bearing property is "rejects @example.com".
	assert.match(
		prodVars,
		/variable\s+"alert_emails"[\s\S]*?(endswith\(e,\s*"@example\.com"\)|@example\\?\.com)/,
		'infra/envs/prod/variables.tf alert_emails must reject @example.com placeholders (via endswith or regex match).',
	);
});

test('preview env declares alert_emails with non-empty validation', () => {
	// Reason: preview was the lone outlier — module default of [] +
	// no env-level validation meant alarms fired into an empty SNS
	// topic. A hit Lambda concurrency cap on a fresh preview env
	// went silent. /audit/cost-controls May 2026 closeout.
	const previewMain = read('../../infra/envs/preview/main.tf');
	const previewVars = read('../../infra/envs/preview/variables.tf');
	assert.match(
		previewMain,
		/alert_emails\s*=\s*var\.alert_emails/,
		'infra/envs/preview/main.tf must pass alert_emails into the web-stack module — closes the gap that /audit/cost-controls flagged.',
	);
	assert.match(
		previewVars,
		/variable\s+"alert_emails"[\s\S]*?validation\s*\{[\s\S]*?length\(var\.alert_emails\)\s*>\s*0/,
		'infra/envs/preview/variables.tf alert_emails must validate non-empty list.',
	);
});

test('web-stack CloudFront uses PriceClass_100 or PriceClass_200, never _All', () => {
	// Reason: PriceClass_All bills from every edge location, including
	// SA + AU which 10x the per-GB cost. A user accidentally toggling
	// the price class to _All in a "let's see if it's faster" experiment
	// produces a multi-x bill jump that doesn't get caught until end
	// of month.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	const priceClassMatch = mainTf.match(/price_class\s*=\s*"(PriceClass_\w+)"/);
	assert.ok(priceClassMatch, 'Could not locate price_class assignment in web-stack/main.tf.');
	assert.ok(
		['PriceClass_100', 'PriceClass_200'].includes(priceClassMatch![1]),
		`CloudFront price_class must be PriceClass_100 or PriceClass_200 (was "${priceClassMatch![1]}"). _All bills from every edge location regardless of where users live and 10× the per-GB cost.`,
	);
});

test('web-stack log groups all set retention_in_days', () => {
	// Reason: AWS CloudWatch Logs defaults to "Never expire" — that's
	// $0.50/GB/month forever for every log byte ever written. A
	// retention attribute on every aws_cloudwatch_log_group resource
	// caps the per-GB exposure to the configured window.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	// Find every aws_cloudwatch_log_group block and assert it sets
	// retention_in_days. The body grep is generous — exact-attribute
	// match would be fragile against HCL formatting variants.
	const logGroupRe = /resource\s+"aws_cloudwatch_log_group"\s+"[^"]+"\s*\{[\s\S]*?\n\}/g;
	const blocks = mainTf.match(logGroupRe) ?? [];
	assert.ok(
		blocks.length > 0,
		'Could not find any aws_cloudwatch_log_group blocks in web-stack/main.tf — has the resource moved?',
	);
	for (const block of blocks) {
		assert.match(
			block,
			/retention_in_days\s*=\s*\d+/,
			'Every aws_cloudwatch_log_group MUST set retention_in_days — default "Never expire" is $0.50/GB/month forever.\nBlock:\n' + block.slice(0, 200) + '…',
		);
	}
});

test('web-stack WAF web_acl_id wires the distribution + scope-down filters /api/coach', () => {
	// Reason: the WAF rate-limit rule fires per IP at 100 req / 5 min;
	// without the scope-down filter it would rate-limit ALL traffic
	// (static assets included), throttling legitimate users on the
	// first page load. Without the web_acl_id wire it wouldn't fire
	// at all. Both must be present together.
	const mainTf = read('../../infra/modules/web-stack/main.tf');
	const wafTf = read('../../infra/modules/web-stack/waf.tf');
	assert.match(
		mainTf,
		/web_acl_id\s*=\s*var\.waf_enabled[\s\S]*?aws_wafv2_web_acl\.coach\[0\]\.arn/,
		'CloudFront distribution must attach the WAF ACL via web_acl_id (gated on var.waf_enabled).',
	);
	// The scope-down statement must filter to /api/coach paths only.
	assert.match(
		wafTf,
		/scope_down_statement[\s\S]*?byte_match_statement[\s\S]*?\/api\/coach/,
		'WAF rate-limit rule must have a scope_down_statement byte-matching /api/coach so static-asset traffic isn\'t rate-limited.',
	);
});

test('AWS Budgets carries all three thresholds (50% ACTUAL, 100% ACTUAL, 100% FORECASTED)', () => {
	// Reason: the FORECASTED notification is the only one that catches
	// a runaway DURING the month — the two ACTUAL notifications fire
	// only after the spend lands on the bill (up to 24 h lag). A
	// budget that drops the FORECASTED notification leaves a 24 h
	// window where a leaked Anthropic key can rack up hundreds of
	// dollars before anyone notices.
	const budgets = read('../../infra/envs/prod/budgets.tf');
	const notifications = budgets.match(/notification\s*\{[\s\S]*?\}/g) ?? [];
	assert.ok(
		notifications.length >= 3,
		`Expected ≥3 notification blocks in budgets.tf, found ${notifications.length}. The 50%/100% ACTUAL + 100% FORECASTED set is the documented baseline.`,
	);
	// Pin each of the three required types/thresholds.
	const has = (re: RegExp): boolean => notifications.some((n) => re.test(n));
	assert.ok(
		has(/threshold\s*=\s*50[\s\S]*?notification_type\s*=\s*"ACTUAL"/),
		'budgets.tf must declare a 50% ACTUAL notification — early warning at half-budget.',
	);
	assert.ok(
		has(/threshold\s*=\s*100[\s\S]*?notification_type\s*=\s*"ACTUAL"/),
		'budgets.tf must declare a 100% ACTUAL notification — budget blown.',
	);
	assert.ok(
		has(/threshold\s*=\s*100[\s\S]*?notification_type\s*=\s*"FORECASTED"/),
		'budgets.tf must declare a 100% FORECASTED notification — the ONLY one that catches a runaway during the month (the 24h-lagged ACTUAL fires too late).',
	);
});

test('refresh-tokens fails closed (503) when CRON_SECRET env is absent', () => {
	// Reason: the function returns 503 `cron_not_configured` when
	// `Deno.env.get('CRON_SECRET')` is null — i.e. a misconfigured
	// production deployment refuses to do any work rather than
	// proceeding with "no auth check at all." The 403 path
	// (wrong/missing bearer with the env var present) is covered by
	// integration tests in handler_envelope.test.ts; the 503 branch
	// is a config-state property best pinned at the source level.
	//
	// The rollback path matters even more: refresh-tokens is the
	// deprecated-but-kept rollback for the Go service per
	// apps/backend/CLAUDE.md. If a future edit dropped the 503 guard
	// and just fell through to `auth.startsWith('Bearer ')` against an
	// undefined secret, an unauthenticated POST could trigger the
	// integrations loop with no auth (which is the exact bug that
	// commit b3373c6 originally closed).
	const source = read('../backend/supabase/functions/refresh-tokens/index.ts');
	// 1. Reads CRON_SECRET via Deno.env.get.
	assert.match(
		source,
		/Deno\.env\.get\(['"]CRON_SECRET['"]\)/,
		'refresh-tokens must read CRON_SECRET from env.',
	);
	// 2. Has an explicit fail-closed branch returning 503 when the
	//    env var is missing — before the bearer check.
	assert.match(
		source,
		/if\s*\(\s*!\s*cronSecret\s*\)\s*\{[\s\S]*?status:\s*503/,
		'refresh-tokens must return 503 fail-closed when CRON_SECRET is unset, BEFORE the bearer check. ' +
			'Falling through with an undefined secret would let an unauthenticated POST proceed.',
	);
	// 3. Drains the request body BEFORE the auth check (the body-
	//    drain commit e56cd48). A regression that removed
	//    discardBody() re-opens the slow-loris DoS window.
	const bodyDrainIdx = source.indexOf('discardBody(req)');
	const cronCheckIdx = source.search(/Deno\.env\.get\(['"]CRON_SECRET['"]\)/);
	assert.notStrictEqual(bodyDrainIdx, -1,
		'refresh-tokens must call discardBody(req) — the body-drain helper from _shared/body_limit.ts.');
	assert.ok(
		bodyDrainIdx < cronCheckIdx,
		'discardBody(req) must come BEFORE the CRON_SECRET env read — otherwise a chunked-body POST holds the connection open until the runtime timeout even on the auth-reject path.',
	);
});

test('revenuecat-webhook verifies HMAC before constructing the Supabase client', () => {
	// Reason: the webhook is the ONLY legitimate writer of
	// user_profiles.subscription_tier (the lock_subscription_columns
	// trigger from migration 20260624_001 rejects writes from anything
	// other than the service_role). If a refactor reordered the function
	// to construct the service-role `createClient` before the HMAC
	// verify, an attacker who knows the webhook URL could forge a Pro
	// upgrade by POSTing a valid-looking event body with no signature —
	// the client would be alive and ready to write the moment the
	// request handler crossed the (now-out-of-order) HMAC check.
	// Pinning the call order keeps the privilege boundary obvious.
	const source = read('../backend/supabase/functions/revenuecat-webhook/index.ts');
	const lines = source.split('\n');
	const tseqLine = lines.findIndex((l) => /timingSafeEqual\s*\(/.test(l));
	const createLine = lines.findIndex((l) => /createClient\s*\(/.test(l));
	assert.notStrictEqual(
		tseqLine,
		-1,
		'Could not locate timingSafeEqual call in revenuecat-webhook/index.ts — has the HMAC check been removed or renamed?',
	);
	assert.notStrictEqual(
		createLine,
		-1,
		'Could not locate createClient call in revenuecat-webhook/index.ts.',
	);
	assert.ok(
		tseqLine < createLine,
		`HMAC timingSafeEqual (line ${tseqLine + 1}) must appear before createClient (line ${createLine + 1}) — ` +
			'a service-role client constructed before HMAC verification opens a forge-Pro-upgrade window via the webhook URL.',
	);
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
	// Source-of-truth check: the value MUST be a positive small
	// integer (sanity guard; drifting to "0" or "10000" would be a
	// product mistake worth catching). The exact value (2 today,
	// reduced from 5 in commit 144d2a9 as a cost-control measure) is
	// not pinned here — the cross-checks below verify the placeholder
	// matches whatever the server says. The literal-value pin used to
	// be `=== '5'`; replaced after audit:cost-controls + the
	// 144d2a9 product change drifted past it without updating the
	// test. The lockstep-with-server property is what actually matters.
	assert.match(
		serverCap,
		/^[1-9]\d{0,2}$/,
		`TIER_LIMITS.free.dailyLimit should be a small positive integer (1–999), was "${serverCap}".`,
	);
	// Web placeholder. The current shape reads
	// `TIER_LIMITS.free.dailyLimit` directly from the imported source-
	// of-truth, which is structurally better than the old local
	// `DEFAULT_DAILY_LIMIT` constant — a server-cap change updates
	// both at once because the placeholder IS the server cap. Pin the
	// import path instead of a literal value.
	const chat = read('src/lib/components/CoachChat.svelte');
	assert.match(
		chat,
		/TIER_LIMITS\.free\.dailyLimit/,
		'CoachChat.svelte must use TIER_LIMITS.free.dailyLimit as the pre-handshake placeholder so the placeholder updates in lockstep with the server cap.',
	);
	// Mobile placeholder, both Dart twins. Same shape pin — the
	// `_freeDailyLimit` local constant must be the literal value
	// (Dart can't import from TS), so cross-check it against the
	// server cap extracted above.
	for (const p of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const dart = read(p);
		assert.match(
			dart,
			new RegExp(`_freeDailyLimit\\s*=\\s*${serverCap}\\b`),
			`${p} _freeDailyLimit must equal the server cap (${serverCap}). ` +
				'If the server tier was changed in coach/types.ts, mirror it here.',
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

test('accessibility: sidebar profile popover has focus trap + ESC close + focus return', () => {
	// Reason: audit/accessibility High — WCAG 2.1.2 (No Keyboard
	// Trap, paradoxically — the prior version let Tab escape the
	// popover leaving the user stranded in the page behind it
	// without a keyboard close path) + 2.4.3 (Focus Order). Pin
	// the focus-management wiring.
	const src = read('src/routes/+layout.svelte');
	assert.match(
		src,
		/bind:this={popoverEl}/,
		'popover must bind a ref so the focus trap + first-focus logic ' +
			'can find its DOM node.',
	);
	assert.match(
		src,
		/bind:this={profileBtnEl}/,
		'profile-btn must bind a ref so focus can return on close.',
	);
	assert.match(
		src,
		/if\s*\(e\.key\s*===\s*['"]Escape['"]/,
		'popover effect must wire an Escape key handler.',
	);
	assert.match(
		src,
		/if\s*\(e\.key\s*!==\s*['"]Tab['"]/,
		'popover effect must wire a Tab-trap handler.',
	);
	assert.match(
		src,
		/aria-label="Account menu"/,
		'popover root must carry an aria-label so screen readers ' +
			'announce the menu region.',
	);
});

test('accessibility: chart svgs + map canvas carry role + aria-label', () => {
	// Reason: audit/accessibility Medium — WCAG 1.1.1. Without
	// role + aria-label, screen readers traverse every SVG child
	// individually (rects on heatmap, paths on train-load chart)
	// and have no name for the maplibre canvas at all. Pin each
	// surface's labelled-landmark wrapper.
	const heatmap = read('src/lib/components/CalendarHeatmap.svelte');
	const train = read('src/lib/components/TrainingLoadChart.svelte');
	const map = read('src/lib/components/RunMap.svelte');
	assert.match(
		heatmap,
		/<svg[^>]*role="img"[^>]*aria-label="Activity calendar heatmap"/s,
		'CalendarHeatmap.svelte <svg> must carry role="img" + an ' +
			'aria-label.',
	);
	assert.match(
		train,
		/<svg[^>]*role="img"[^>]*aria-label="Training load chart/s,
		'TrainingLoadChart.svelte <svg> must carry role="img" + an ' +
			'aria-label that names the chart.',
	);
	assert.match(
		map,
		/<div\s+class="run-map-wrapper"\s+role="region"\s+aria-label="Run map">/,
		'RunMap.svelte wrapper must carry role="region" + aria-label="Run map" ' +
			'so AT users can skip past it or into it.',
	);
});

test(
	'accessibility: every :focus{outline:none} SELECTOR pairs ' +
		':focus-visible (WCAG 2.4.7 + 2.4.11)',
	() => {
		// Reason: audit/accessibility High — bulk-removing the browser
		// focus ring without giving keyboard users a replacement
		// indicator violates WCAG 2.4.7 (Focus Visible) + 2.4.11
		// (Focus Appearance).
		//
		// Self-audit round 6 strengthens this from "file references
		// :focus-visible somewhere" to "every <sel>:focus{outline:none}
		// has a matching <sel>:focus-visible". The weaker form let
		// routes/+page.svelte ship with .search-input:focus suppressing
		// the outline while only OTHER selectors in the same file
		// (.star-btn, .toolbar-select) had companions.
		const { readdirSync } = readFileSyncDeps();
		const root = resolve(__dirname, '..', '..', 'src');
		const walk = (dir: string, out: string[] = []): string[] => {
			for (const ent of readdirSync(dir, { withFileTypes: true })) {
				const full = `${dir}/${ent.name}`;
				if (ent.isDirectory()) walk(full, out);
				else if (ent.name.endsWith('.svelte')) out.push(full);
			}
			return out;
		};
		const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '');
		const focusRule = /([^{}]+?:focus)\s*\{\s*[^}]*outline\s*:\s*none[^}]*\}/g;
		const fvRule = /([^{}]+?:focus-visible)\s*\{/g;
		const baseOf = (sel: string, suffix: string): string[] =>
			sel
				.split(',')
				.map((s) => s.trim())
				.filter((s) => s.endsWith(suffix))
				.map((s) => s.slice(0, -suffix.length).trim());
		const offenders: string[] = [];
		for (const f of walk(root)) {
			const body = stripComments(readFileSync(f, 'utf-8'));
			const focusSelectors = new Set<string>();
			let m: RegExpExecArray | null;
			focusRule.lastIndex = 0;
			while ((m = focusRule.exec(body)) !== null) {
				for (const b of baseOf(m[1], ':focus')) focusSelectors.add(b);
			}
			if (focusSelectors.size === 0) continue;
			const pairedSelectors = new Set<string>();
			fvRule.lastIndex = 0;
			while ((m = fvRule.exec(body)) !== null) {
				for (const b of baseOf(m[1], ':focus-visible'))
					pairedSelectors.add(b);
			}
			const unpaired = [...focusSelectors].filter((s) => !pairedSelectors.has(s));
			if (unpaired.length > 0) {
				const rel = f.replace(resolve(__dirname, '..', '..') + '/', '');
				offenders.push(`${rel}: ${unpaired.map((s) => `${s}:focus`).join(', ')}`);
			}
		}
		assert.deepEqual(
			offenders,
			[],
			'these selectors suppress :focus outline without a matching ' +
				':focus-visible companion:\n  ' +
				offenders.join('\n  '),
		);
	},
);

test('accessibility: every top-level page renders an h1 (WCAG 1.3.1 + 2.4.6)', () => {
	// Reason: audit/accessibility High — Dashboard / Runs / Coach
	// had no h1, so a screen-reader user navigating by headings
	// couldn't identify which route they were on. visually-hidden
	// h1s preserve the visual design while giving the heading-by-
	// headings flow an anchor.
	for (const [path, expectedText] of [
		['src/routes/dashboard/+page.svelte', 'Dashboard'],
		['src/routes/runs/+page.svelte', 'Run history'],
		['src/routes/coach/+page.svelte', 'AI Coach'],
	] as const) {
		const src = read(path);
		assert.match(
			src,
			new RegExp(
				`<h1\\s+class="visually-hidden">${expectedText}</h1>`,
			),
			`${path} must render <h1 class="visually-hidden">${expectedText}</h1>`,
		);
	}
});

test('accessibility: app.css carries a prefers-reduced-motion safety net', () => {
	// Reason: audit/accessibility High — WCAG 2.3.3 / EU EAA. Page-
	// level components do their own reduced-motion handling, but a
	// global * { animation-duration: 0.01ms } catch-all covers
	// future animations the dev forgets to gate. Pin the rule so
	// it can't disappear in a refactor.
	const css = read('src/app.css');
	assert.match(
		css,
		/@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{[\s\S]*?\*[\s\S]*?animation-duration:\s*0\.01ms[\s\S]*?transition-duration:\s*0\.01ms/,
		'app.css must carry a global prefers-reduced-motion safety net ' +
			'that sets animation-duration + transition-duration to 0.01ms ' +
			'on the universal selector.',
	);
});

test('accessibility: web shell wires WCAG 2.4.1 skip link + #main-content target', () => {
	// Reason: audit/accessibility High (May 2026). Keyboard users
	// had to Tab through 5 sidebar items before reaching page
	// content on every load. Pin the skip-link wiring.
	const layout = read('src/routes/+layout.svelte');
	const css = read('src/app.css');
	assert.match(
		layout,
		/<a\s+href="#main-content"\s+class="skip-link">/,
		'+layout.svelte must render a `Skip to main content` link as the ' +
			'first element above the sidebar (WCAG 2.4.1).',
	);
	assert.match(
		layout,
		/<main\s+id="main-content"/,
		'+layout.svelte <main> must carry id="main-content" so the skip ' +
			"link's anchor resolves.",
	);
	assert.match(
		css,
		/\.skip-link\s*\{[\s\S]*?:focus[\s\S]*?translateY/,
		'app.css must style .skip-link as visually-hidden-until-focused ' +
			'(translateY transform on :focus).',
	);
});

test('accessibility: ToastContainer wraps the live region (audit/accessibility High)', () => {
	// Reason: audit/accessibility High — toasts went unannounced
	// because the container had no aria-live region. Pin role +
	// aria-live on the wrapper AND assertive on the error toast.
	const src = read('src/lib/components/ToastContainer.svelte');
	assert.match(
		src,
		/role="status"\s+aria-live="polite"/,
		'ToastContainer must wrap toasts in role="status" aria-live="polite".',
	);
	assert.match(
		src,
		/aria-live=\{t\.type\s*===\s*'error'\s*\?\s*'assertive'\s*:\s*'polite'\}/,
		'Error toasts must escalate to aria-live="assertive" so screen ' +
			'readers interrupt the user on failure.',
	);
});

test('accessibility: login inputs carry programmatically associated labels', () => {
	// Reason: audit/accessibility High — the email + password inputs
	// used `placeholder` only, which disappears as the user types
	// and screen readers announce just "edit text". Visually-hidden
	// <label for> is the most-compatible WCAG 3.3.2 + 1.3.1 fix.
	const src = read('src/routes/login/+page.svelte');
	for (const id of ['login-email', 'login-password']) {
		assert.match(
			src,
			new RegExp(`<label\\s+for="${id}"[^>]*>`),
			`login page must declare a <label for="${id}"> so the input ` +
				'has a programmatically associated name.',
		);
		assert.match(
			src,
			new RegExp(`id="${id}"`),
			`login page input must carry id="${id}" matching its label.`,
		);
	}
});

test('app.html + app.css do not load Google Fonts (audit/cookie-consent Critical)', () => {
	// Reason: audit/cookie-consent (May 2026) flagged that the prior
	// shape fetched the Material Symbols font from fonts.googleapis.com
	// / fonts.gstatic.com unconditionally on every page hit. EU IPs
	// reached a US sub-processor before the consent banner rendered —
	// ePrivacy Art 5(3) Critical. Self-hosted via the material-symbols
	// npm package (Apache 2.0); the JS-side import in +layout.svelte
	// pulls both the package CSS and the .woff2 into the build.
	const stripRepeatedly = (s: string, re: RegExp): string => {
		let prev;
		let next = s;
		do {
			prev = next;
			next = prev.replace(re, '');
		} while (next !== prev);
		return next;
	};
	const stripHtmlComments = (s: string) => stripRepeatedly(s, /<!--[\s\S]*?-->/g);
	const stripCssComments = (s: string) => stripRepeatedly(s, /\/\*[\s\S]*?\*\//g);
	const layout = read('src/routes/+layout.svelte');
	const html = stripHtmlComments(read('src/app.html'));
	const css = stripCssComments(read('src/app.css'));
	for (const [name, surface] of [
		['app.html', html],
		['app.css', css],
	] as const) {
		assert.doesNotMatch(
			surface,
			/fonts\.googleapis\.com/,
			`${name} must not reference fonts.googleapis.com — ` +
				'the font is self-hosted via material-symbols (npm).',
		);
		assert.doesNotMatch(
			surface,
			/fonts\.gstatic\.com/,
			`${name} must not reference fonts.gstatic.com.`,
		);
	}
	assert.match(
		layout,
		/import\s+['"]material-symbols\/outlined\.css['"]/,
		'+layout.svelte must import material-symbols/outlined.css so the ' +
			'self-hosted @font-face + .woff2 are bundled.',
	);
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
	// references the old phrasing for history. Loop the replace + case-
	// insensitive flag so nested or upper-case <SCRIPT> tags can't slip
	// rendered copy past the guard (CodeQL js/bad-tag-filter +
	// js/incomplete-multi-character-sanitization).
	let renderedOnly = source;
	let prev;
	const scriptRe = /<script\b[\s\S]*?<\/script\s*>/gi;
	do {
		prev = renderedOnly;
		renderedOnly = prev.replace(scriptRe, '');
	} while (renderedOnly !== prev);
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

test('MapTiler tile fetches on anon public pages are gated on consent', () => {
	// Reason: audit/cookie-consent (2026-05-25). MapTiler logs the
	// requester IP per tile fetch. /live/[id], /share/route/[id], and
	// /share/run/[id] are anon-accessible — the visitor's IP must
	// not reach MapTiler until they have either accepted the cookie
	// banner or tapped "Load map" on the placeholder.
	const liveSrc = read('src/routes/live/[id]/+page.svelte');
	assert.match(
		liveSrc,
		/hasAcceptedConsent\(\)/,
		'/live/[id] must consult hasAcceptedConsent() before auto-mounting the map.',
	);
	assert.match(
		liveSrc,
		/{#if mapConsented}/,
		'/live/[id] must conditionally render the map container so the ' +
			'MapTiler init only fires after consent.',
	);
	assert.match(
		liveSrc,
		/onclick={loadMapNow}/,
		'/live/[id] must offer a "Load map" button that flips mapConsented.',
	);

	const runMapSrc = read('src/lib/components/RunMap.svelte');
	assert.match(
		runMapSrc,
		/requireExplicitConsent\?:\s*boolean/,
		'RunMap must expose requireExplicitConsent so anon callers can gate map init.',
	);
	assert.match(
		runMapSrc,
		/if \(!mapConsented\) return;/,
		'RunMap.onMount must short-circuit when consent is pending — no maplibregl.Map() until the user opts in.',
	);

	// The two share surfaces must pass the consent-required prop.
	const routeShareSrc = read('src/routes/share/route/[id]/+page.svelte');
	assert.match(
		routeShareSrc,
		/<RunMap[^>]*requireExplicitConsent/,
		'/share/route/[id] must pass requireExplicitConsent to RunMap.',
	);
	const runShareSrc = read('src/lib/components/RunShareView.svelte');
	assert.match(
		runShareSrc,
		/<RunMap[\s\S]*?requireExplicitConsent[\s\S]*?\/>/,
		'RunShareView (used by /share/run/[id]) must pass requireExplicitConsent.',
	);
});

test('Coach handler gates the Anthropic fan-out behind coach_consent_at', () => {
	// Reason: audit/gdpr (2026-05-25). Coach forwards health-adjacent
	// data to Anthropic (US sub-processor). Art 6(1)(a) requires an
	// affirmative consent act before the first dispatch — opening
	// /coach is not affirmative. The handler must read
	// user_profiles.coach_consent_at (via the get_my_profile RPC, since
	// the column isn't in the public-safe grant list — migration
	// 20260707_001) and refuse before the provider stream runs.
	const source = read('src/lib/coach/handler.ts');
	assert.match(
		source,
		/\.rpc\('get_my_profile'\)/,
		'handler.ts must call get_my_profile() to load the self row including coach_consent_at.',
	);
	assert.match(
		source,
		/coach_consent_at/,
		'handler.ts must reference coach_consent_at as the gating field.',
	);
	assert.match(
		source,
		/return jsonError\(\s*403,\s*'Coach consent required[\s\S]*?\)/,
		'handler.ts must return 403 when coach_consent_at is null — failing closed.',
	);
	// The gate must sit BEFORE any provider stream invocation. We
	// assert ordering by checking that the consent lookup appears
	// before the first `tier ===` reference (which is the start of
	// the rate-limit / provider-dispatch block).
	const consentIdx = source.indexOf("rpc('get_my_profile')");
	const tierIdx = source.indexOf('tier === ');
	assert.ok(
		consentIdx > 0 && consentIdx < tierIdx,
		'coach_consent_at lookup must precede the tier / provider dispatch.',
	);
});

test('Nominatim fallback uses a reachable contact email (no protomaps placeholder)', () => {
	// Reason: audit/third-party-data-flows (2026-05-25). The
	// Nominatim `email=` parameter is the usage-policy contact path
	// — OSM Foundation requires a reachable address so they can
	// reach the operator on abuse / takedown. The previous value
	// (`protomaps-dev@localhost`) was a placeholder copied from a
	// different project and violates the policy.
	const source = read('src/lib/geocoding_math.ts');
	assert.ok(
		!source.includes('protomaps-dev@localhost'),
		'geocoding_math.ts must not retain the protomaps-dev placeholder email.',
	);
	assert.match(
		source,
		/email:\s*'privacy@threkir\.com'/,
		'Nominatim fallback must declare privacy@threkir.com (the operator-' +
			'reachable contact alias) per OSM usage policy.',
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
