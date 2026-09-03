// Who may read what. Every guard here pins a boundary between an owner's
// own data and what a non-owner viewer, a public page or an export is
// allowed to resolve: track and route clipping on the thumbnail surfaces,
// the public views and RPCs the non-owner readers must go through, the
// column allowlists on the client selects, the deletion sweeps, and the
// fields a restore must not carry back.
//
// Mirrors the `thumbnail privacy-zone clipping` group in
// `apps/mobile_android/test/architecture_guards_test.dart` — the two
// rules must stay in lockstep.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

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

test('SocialFeed threads runId + ownerUserId into RunTrackPreview', () => {
	// Reason: the /social Feed tab (SocialFeed.svelte) renders OTHER
	// users' public runs to the viewer. RunTrackPreview's non-owner clip
	// path needs the run id (the clip-public-track EF resolves track_url
	// + clips server-side) AND the owner's id (so it knows the viewer
	// isn't the owner and must clip). Without either prop the thumbnail
	// either renders a placeholder or — worse, on a refactor that drops
	// ownerUserId — skips the privacy-zone clip. Same contract as the
	// /u/[id] guard above; pinned so a "simplify the feed card" refactor
	// can't silently regress it. See decisions §33 + audit/privacy-zones.
	const source = read('src/lib/components/SocialFeed.svelte');
	const mounts = [...source.matchAll(/<RunTrackPreview\b[^/>]*\/?>/gs)];
	assert.ok(
		mounts.length >= 1,
		'expected at least one RunTrackPreview mount in SocialFeed.svelte; got ' +
			mounts.length +
			' — has the feed card stopped rendering track thumbnails?',
	);
	for (const m of mounts) {
		const tag = m[0];
		assert.match(
			tag,
			/runId=/s,
			'RunTrackPreview in SocialFeed missing runId prop — the non-owner clip EF can\'t resolve the track without it:\n' +
				tag,
		);
		assert.match(
			tag,
			/ownerUserId=/s,
			'RunTrackPreview in SocialFeed missing ownerUserId prop ' +
				'(privacy-zone clip is skipped without it — non-owner viewers would see the unclipped polyline):\n' +
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
	const source = read('src/lib/core/data.ts');
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
	// Reason: same fail-closed rule every privacy-clipping path follows.
	// Returning the input on RPC
	// error would defeat the helper. The empty-input early-return is
	// not relevant here (the helper takes only an id), so we only
	// assert that the error branch returns [].
	const source = read('src/lib/core/data.ts');
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
	const source = read('src/lib/core/data.ts');

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
		'export async function fetchPublicRunsByUser(',
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
			path: 'src/lib/core/data.ts',
			functionRe: /export async function deleteRun\(id: string\)[\s\S]*?\n\}/,
			label: 'deleteRun (web)',
		},
		{
			path: 'src/lib/core/data.ts',
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
			// Accept the F11 BUCKETS registry constant (BUCKETS.run_photos ===
			// 'run-photos') as well as the bare literal — web routes storage
			// access through core/schema.ts, not raw bucket-name strings.
			/storage[\s\S]*?from\((?:['"]run-photos['"]|BUCKETS\.run_photos)\)[\s\S]*?\.remove\(/,
			`${label} must call storage.from(BUCKETS.run_photos).remove(...) with the collected paths.`,
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
		// StorageBuckets.runPhotos === 'run-photos' — the dart twin routes
		// bucket access through the registry, same as the web BUCKETS const.
		/Future<void> deleteRunPhoto\(RunPhotoRow photo\)[\s\S]*?thumb512Path[\s\S]*?(?:run-photos|StorageBuckets\.runPhotos)[\s\S]*?\.remove\(/,
		'api_client.dart#deleteRunPhoto must include photo.thumb512Path in the storage remove list.',
	);
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
	// The invariant is the COMPARISON and the fact that every download
	// site is filtered through it — not the file either lives in. The
	// streaming rewrite already inlined what used to be an
	// `expectedTrackUrl` variable, and the §832 round moved the
	// comparison itself into `render.ts`; both satisfied the property
	// exactly while failing a guard pinned to `index.ts`. So read the
	// module and its renderers together, then assert separately that
	// `index.ts` still resolves its keys through the helper — otherwise
	// a live comparison in a function nobody calls would pass this.
	const index = read('../backend/supabase/functions/export-data/index.ts');
	const render = read('../backend/supabase/functions/export-data/render.ts');
	const ef = `${index}\n${render}`;
	const canonical = String.raw`\`\$\{[^}]*user_id[^}]*\}\/\$\{[^}]*\.id[^}]*\}\.json\.gz\``;
	assert.match(
		ef,
		new RegExp(`track_url\\s*[!=]==\\s*(?:${canonical}|[A-Za-z_$][\\w$]*)`),
		'export-data must compare track_url against the canonical Storage path — pass-2 commit 978b4c9.',
	);
	assert.match(
		ef,
		new RegExp(canonical),
		'export-data must build the canonical path as `${user_id}/${run_id}.json.gz`.',
	);
	// Every service-role Storage download of a track must take its key
	// from the checked helper. A bare `r.track_url` at a download site
	// is the regression this backstop exists to stop.
	const trackKeySites = [...index.matchAll(/canonicalTrackUrl\(/g)];
	assert.ok(
		trackKeySites.length >= 2,
		'export-data must resolve every track download key through canonicalTrackUrl — found ' +
			`${trackKeySites.length} call site(s).`,
	);
});

test('fetchRunGear routes the non-owner gear read through the public_run_gear RPC', () => {
	// Reason: audit/public-rows (May 2026). run_gear visibility extends to
	// non-owners of public runs (the SELECT policy is is_run_visible_to-gated),
	// so the public run-share page renders the gear chip for anon viewers. A
	// client-side `run_gear` -> `gear` join can only enforce a column allowlist
	// in TypeScript — owner-private columns (`notes`, `purchased_at`,
	// `retired_at`, `target_distance_m`) would still leak the moment the `gear`
	// RLS drifts or a writer regresses the join back to `*`. Migration
	// 20261126_001 moved the projection server-side: the `public_run_gear`
	// SECURITY DEFINER RPC gates on is_run_visible_to and returns ONLY
	// (id, kind, name, brand, model). Pin that fetchRunGear calls the RPC and
	// never joins the owner-only gear table directly.
	const source = read('src/lib/core/data.ts');
	assert.match(
		source,
		/supabase\.rpc\(\s*['"]public_run_gear['"]/,
		'fetchRunGear must read non-owner gear via the public_run_gear ' +
			'SECURITY DEFINER RPC (migration 20261126_001), which projects only ' +
			'the public columns server-side — not a client-side gear-table join.',
	);
	assert.doesNotMatch(
		source,
		/\.select\(['"`]gear:gear_id\(\*\)['"`]\)/,
		'fetchRunGear must not select gear:gear_id(*) — that join streams ' +
			'owner-private inventory columns to public-run viewers. Use the ' +
			'public_run_gear RPC instead (audit/public-rows).',
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
		'src/lib/backup/backup.ts',
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

// Persona-hunt Round 2 finding Casual #1: the /auth/reset page used
// to leave the recovery session live if the user closed the tab
// without typing a new password. supabase-js consumes the
// `#access_token` from the URL on page load + mints a session before
// the user touches the form. On a shared / library / family laptop
// the next person navigating to / could land in /dashboard signed
// in as the victim. Fix: sign out on unmount + beforeunload IF the
// password wasn't changed. Pinned via source-grep so a future
// refactor of the reset page that drops the cleanup surfaces here.

test('/auth/reset signs out the recovery session on unmount when no password change happened', () => {
	const source = read('src/routes/auth/reset/+page.svelte');
	assert.match(
		source,
		/cleanupRecoverySession/,
		'/auth/reset must define a cleanupRecoverySession helper called on unmount/beforeunload',
	);
	assert.match(
		source,
		/supabase\.auth\.signOut/,
		'/auth/reset must call supabase.auth.signOut from the cleanup path',
	);
	assert.match(
		source,
		/passwordChanged/,
		'cleanupRecoverySession must gate on a passwordChanged flag so a successful update -> goto(/dashboard) doesn\'t sign out the freshly-set session',
	);
	assert.match(
		source,
		/onDestroy|beforeunload/,
		'cleanupRecoverySession must run on at least one of onDestroy / beforeunload (both is the belt-and-braces shape, but either by itself catches the casual-user case)',
	);
});

test('client user_profiles selects only touch public-safe columns', () => {
	// Reason: migration 20260707_001 revoked table-level SELECT on
	// user_profiles and re-granted only the public-safe columns
	// (id, display_name, avatar_url, created_at). Every other column is
	// deny-by-default, so a client `.from('user_profiles').select(<private>)`
	// gets a 403 (42501) at runtime. Owner self-reads of private columns
	// (gender, date_of_birth, health_data_consent_at, parkrun_number, …)
	// MUST go through the get_my_profile() SECURITY DEFINER RPC instead.
	//
	// This caught the run-26822355308 regression where the settings,
	// preferences, run-detail and plan-editor surfaces direct-selected
	// private columns — the reads 403'd, the consent state read as false,
	// and the save flow silently short-circuited. The web e2e suite that
	// would normally catch it had been dark for ~2 days behind a broken
	// stack. This unit guard fails fast instead.
	// 20270424000002 re-emits that grant list plus `handle` — the public
	// @handle is cross-user readable by design (People search renders it).
	const PUBLIC_SAFE = new Set(['id', 'display_name', 'avatar_url', 'created_at', 'handle']);
	const root = resolve(__dirname, '..');
	const walk = (dir: string, out: string[] = []): string[] => {
		for (const ent of readdirSync(dir, { withFileTypes: true })) {
			const full = `${dir}/${ent.name}`;
			if (ent.isDirectory()) walk(full, out);
			else if (
				(ent.name.endsWith('.svelte') || ent.name.endsWith('.ts')) &&
				!ent.name.includes('.test.')
			)
				out.push(full);
		}
		return out;
	};
	// Matches `.from('user_profiles').select(<string-literal>)` with the
	// column list captured. Dynamic (non-literal) selects are not matched —
	// none exist today, and adding one should come with its own review.
	const re =
		/\.from\(\s*['"]user_profiles['"]\s*\)\s*\.select\(\s*([`'"])([\s\S]*?)\1/g;
	const offenders: string[] = [];
	for (const f of walk(root)) {
		const src = readFileSync(f, 'utf-8');
		let m: RegExpExecArray | null;
		re.lastIndex = 0;
		while ((m = re.exec(src)) !== null) {
			const cols = m[2]
				.split(/[,\n]/)
				.map((c) => c.trim())
				// strip embedded relation syntax `alias:table(cols)` → leading token
				.map((c) => c.split(':')[0].split('(')[0].trim())
				.filter(Boolean);
			const bad = cols.filter((c) => !PUBLIC_SAFE.has(c));
			if (bad.length > 0) {
				const rel = f.replace(resolve(__dirname, '..', '..') + '/', '');
				offenders.push(`${rel} — selects non-public column(s): ${bad.join(', ')}`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'Client direct-selects of deny-by-default user_profiles columns (they ' +
			'403 at runtime — route owner self-reads through get_my_profile()):\n  ' +
			offenders.join('\n  '),
	);
});

test('every image type an upload surface accepts is one the EXIF stripper can clean', () => {
	// Reason: `stripImageExif` used to return an unrecognised format
	// unchanged, and every photo picker advertised `image/heic,image/heif`.
	// Nothing downstream covers the gap — the Go worker's photo handler
	// returns early on any non-JPEG (`exif.IsJPEG` in
	// apps/job_worker/internal/handler_photo_process.go) — so an iPhone HEIC
	// landed in the bucket with its GPS EXIF intact and the gallery served
	// that original back to every viewer. The accepted set must therefore be
	// a subset of the strippable set, on both the MIME→extension maps and
	// the `accept` attribute of every file input. See decisions §33.
	const strippable = new Set(
		[...read('src/lib/util/exif_strip.ts').matchAll(
			/STRIPPABLE_IMAGE_MIME_TYPES:\s*readonly string\[\]\s*=\s*\[([\s\S]*?)\]/g,
		)]
			.flatMap((m) => [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1])),
	);
	assert.ok(
		strippable.size >= 3,
		'Could not parse STRIPPABLE_IMAGE_MIME_TYPES out of util/exif_strip.ts — renamed?',
	);

	const data = read('src/lib/core/data.ts');
	for (const mapName of ['PHOTO_MIME_TO_EXT', 'AVATAR_MIME_TO_EXT']) {
		const body = data.match(
			new RegExp(`const ${mapName}: Record<string, string> = \\{([\\s\\S]*?)\\}`),
		);
		assert.ok(body, `Could not locate ${mapName} in core/data.ts — renamed?`);
		const accepted = [...body![1].matchAll(/'([^']+)':/g)].map((m) => m[1]);
		assert.ok(accepted.length > 0, `${mapName} parsed empty`);
		for (const mime of accepted) {
			assert.ok(
				strippable.has(mime),
				`${mapName} accepts "${mime}", which stripImageExif cannot clean — ` +
					'the upload would carry its GPS metadata into the bucket.',
			);
		}
	}

	const root = resolve(__dirname, '..');
	const walk = (dir: string, out: string[] = []): string[] => {
		for (const ent of readdirSync(dir, { withFileTypes: true })) {
			const full = `${dir}/${ent.name}`;
			if (ent.isDirectory()) walk(full, out);
			else if (ent.name.endsWith('.svelte')) out.push(full);
		}
		return out;
	};
	const offenders: string[] = [];
	for (const f of walk(root)) {
		for (const m of readFileSync(f, 'utf-8').matchAll(/accept="(image\/[^"]*)"/g)) {
			for (const mime of m[1].split(',').map((s) => s.trim())) {
				if (!strippable.has(mime)) {
					offenders.push(`${f.replace(resolve(__dirname, '..', '..') + '/', '')} — accept="${mime}"`);
				}
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'File inputs must not advertise an image type the EXIF stripper cannot clean:\n  ' +
			offenders.join('\n  '),
	);
});

test('plan publishers never copy the publisher private fields onto a template', () => {
	// Reason: RLS has no column dimension, so the two template SELECT
	// branches ("anyone reads public plan templates", "club members read
	// club templates") expose every column of a published row. vdot and
	// current_5k_seconds are the publisher's fitness proxies; plan-level
	// notes is their own free text (injury history). Both publishers used
	// to copy `notes` straight off the source plan, so the sanctioned
	// button leaked it — not merely a crafted REST call. Migration
	// 20270508_001 strips all three in a trigger, which is what actually
	// holds; this guard keeps the clients honest so the row never carries
	// the value in the first place.
	const source = read(__dirname, 'core/data.ts');
	const publishers = ['publishPlanToLibrary', 'publishPlanAsTemplate'];
	for (const fn of publishers) {
		const start = source.indexOf(`export async function ${fn}(`);
		assert.ok(start > 0, `${fn} not found — rename it here too.`);
		// The insert body ends at the first `.select(` chained after it.
		const body = source.slice(start, source.indexOf('.select(', start));
		for (const col of ['vdot', 'current_5k_seconds', 'notes']) {
			assert.match(
				body,
				new RegExp(`${col}:\\s*null`),
				`${fn} must set ${col} to null on the template row it inserts.`,
			);
			assert.doesNotMatch(
				body,
				new RegExp(`${col}:\\s*src\\.`),
				`${fn} must not copy ${col} from the source plan onto a template.`,
			);
		}
	}
});

test('the public plan library reader does not select the private template columns', () => {
	// Reason: fetchPublicPlanLibrary does select('*'), which is only safe
	// because 20270508_001 guarantees a template row holds nulls in those
	// columns. If a future edit names them explicitly it is reintroducing
	// the read side of the leak.
	const source = read(__dirname, 'core/data.ts');
	const start = source.indexOf('export async function fetchPublicPlanLibrary(');
	assert.ok(start > 0, 'fetchPublicPlanLibrary not found — rename it here too.');
	const body = source.slice(start, source.indexOf('\n}', start));
	for (const col of ['vdot', 'current_5k_seconds']) {
		assert.doesNotMatch(
			body,
			new RegExp(`['"\`][^'"\`]*\\b${col}\\b`),
			`fetchPublicPlanLibrary must not name ${col} in its projection.`,
		);
	}
});

// A stacked PR — one based on another feature branch rather than on main —
// matched no `branches: [main]` filter and therefore ran NOTHING: no CI gate,
// no secret scan, no CodeQL. It showed two green checks (title lint +
// labeller, the only two workflows without a base filter) and read as
// healthy, which is worse than an obvious red, and branch protection only
// requires the gate on pushes to main. The filters are gone; this pins that
// they stay gone, because the failure mode is invisible from the PR page.
//
// `dependabot-auto-merge.yml` is deliberately exempt: it is a
// `pull_request_target` job with `contents: write` that MERGES code, so its
// base filter is a safety scope rather than this bug.

test('the DM route attachment card reads through the owner-aware fetchRouteById', () => {
	// Reason: a route attached to a direct message renders in the RECIPIENT's
	// thread, which is a non-owner surface showing someone else's polyline —
	// exactly the class /routes/[id], the routes list and the clubs Routes tab
	// are already pinned for above. fetchRouteById is the owner-aware gateway:
	// the bare `routes` table under RLS for the owner and active club members,
	// the `public_routes` view plus fetchClippedRouteForViewer for everyone
	// else, so the line a recipient sees has had the sender's privacy zones
	// removed server-side. Reading `routes` directly here — or passing a
	// waypoints array in from the message row — would hand the recipient the
	// unclipped polyline. See decisions §33 + §772.
	const source = read('src/lib/components/DmRouteAttachment.svelte');
	assert.match(
		source,
		/fetchRouteById/,
		'DmRouteAttachment must resolve the route through fetchRouteById — it is the only read that clips for a non-owner recipient. See decisions §33.',
	);
	assert.doesNotMatch(
		source,
		/from\(['"]routes['"]\)/,
		'DmRouteAttachment must not read the bare `routes` table — that returns the unclipped waypoints column.',
	);
	assert.match(
		source,
		/CACHE_MAX/,
		'DmRouteAttachment must have a bounded cache — see RouteTrackPreview for the LRU shape.',
	);
	assert.match(
		source,
		/auth\.user\?\.id/,
		'the attachment cache key must include the viewer: what fetchRouteById returns IS the viewer\'s own clipped view, so a viewer-blind key can serve one reader another reader\'s clip.',
	);
});

test('the message thread renders a route attachment through DmRouteAttachment', () => {
	// Reason: the bubble used to render `{m.body}` and nothing else, so v1's
	// share URL arrived as inert text. The typed attachment (migration
	// 20270619_001) must reach the guarded card above rather than being
	// resolved inline in the page — an inline read here would sit outside the
	// clip guard entirely.
	const source = read('src/routes/messages/[[id]]/+page.svelte');
	assert.match(
		source,
		/<DmRouteAttachment\b[^/>]*routeId=/s,
		'the /messages thread must mount <DmRouteAttachment routeId={…}> for a message carrying route_id.',
	);
	assert.doesNotMatch(
		source,
		/fetchClippedRouteForViewer|fetchRouteById/,
		'the thread page must not resolve a route itself — it goes through DmRouteAttachment, which is the surface the clip guard covers.',
	);
});
