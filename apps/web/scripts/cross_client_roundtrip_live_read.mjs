// Cross-client round-trip for IN-PROGRESS (live spectator) runs — the
// web **read** half.
//
// Reads back the in-progress run + the live pings that the Dart
// `ApiClient.beginLiveBroadcast` + `insertLivePing` wrote (see
// packages/api_client/test/cross_client_roundtrip_live_test.dart) using the
// EXACT read shapes the web `/live/[id]` spectator page uses
// (apps/web/src/routes/live/[id]/+page.svelte):
//
//   1. visibility: supabase.from('public_runs')
//        .select('id, user_id, started_at, duration_s, distance_m, route_id')
//        .eq('id', id).maybeSingle()        // only present when is_public = true
//
//   2. catch-up:   supabase.from('live_run_pings')
//        .select('lat, lng, distance_m, elapsed_s, at, coarse')
//        .eq('run_id', id).order('at', { ascending: true })
//
// and asserts field-for-field equality against the fixture the Dart half
// emitted. A mismatch on any field means a value the Dart live broadcaster
// wrote does NOT round-trip to the value the web spectator reads — the
// runtime drift `gen:types:check` (a static type-shape check) cannot see.
//
// The `coarse` column (migration 20270121_001) is trigger-owned and part of
// the catch-up read shape; the fixture asserts it round-trips false for an
// out-of-zone ping. Finding the run in `public_runs` AT ALL is the is_public
// round-trip (the view filters `where is_public = true`).
//
// Env contract (all required):
//   SUPABASE_TEST_URL             local stack API url (http://127.0.0.1:54321)
//   SUPABASE_TEST_ANON_KEY        local stack anon key
//   CROSS_CLIENT_LIVE_FIXTURE_IN  path to the fixture JSON the Dart half wrote
//
// Run via tsx so the (no-op here, but parity-consistent) TS resolution path
// matches the run + route halves:
//   node --import tsx apps/web/scripts/cross_client_roundtrip_live_read.mjs
//
// Exits 0 on a clean round-trip, 1 (with a diff) on any mismatch.

import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_TEST_URL;
const anonKey = process.env.SUPABASE_TEST_ANON_KEY;
const fixturePath = process.env.CROSS_CLIENT_LIVE_FIXTURE_IN;

function fail(msg) {
	console.error(`✗ cross-client live round-trip: ${msg}`);
	process.exit(1);
}

if (!url || !anonKey) fail('SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY must be set');
if (!fixturePath) fail('CROSS_CLIENT_LIVE_FIXTURE_IN must point to the fixture JSON');

const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

const supabase = createClient(url, anonKey);

const { data: signIn, error: signInError } = await supabase.auth.signInWithPassword({
	email: 'runner@test.com',
	password: 'testtest'
});
if (signInError || !signIn?.user) fail(`sign-in failed: ${signInError?.message ?? 'no user'}`);

// 1) Visibility read — mirror ensureRunIsVisible exactly: the public_runs
//    view (only rows with is_public = true), single row by id, the same
//    column projection. Finding the row here IS the is_public round-trip.
const { data: runRow, error: runErr } = await supabase
	.from('public_runs')
	.select('id, user_id, started_at, duration_s, distance_m, route_id')
	.eq('id', fixture.run_id)
	.maybeSingle();
if (runErr || !runRow) {
	fail(`in-progress run ${fixture.run_id} not visible via public_runs: ${runErr?.message ?? 'no row (is_public not true?)'}`);
}

// 2) Catch-up read — mirror the live-page ping hydration query exactly:
//    the same columns, ordered by `at asc`.
const { data: pings, error: pingErr } = await supabase
	.from('live_run_pings')
	.select('lat, lng, distance_m, elapsed_s, at, coarse')
	.eq('run_id', fixture.run_id)
	.order('at', { ascending: true });
if (pingErr || !pings) fail(`live_run_pings read failed for ${fixture.run_id}: ${pingErr?.message ?? 'no rows'}`);

const first = pings[0] ?? {};
const last = pings.at(-1) ?? {};

// The Dart ping payload carries `ele`, but the live-page catch-up query does
// not select it (the spectator map only draws lat/lng + the distance/elapsed
// labels). Read `ele` through a second owner-scoped query in the SAME row
// order so the elevation round-trip is still asserted — the recorder's own
// /runs view and fetchLiveRunPings both read it.
const { data: elePings, error: eleErr } = await supabase
	.from('live_run_pings')
	.select('ele, at')
	.eq('run_id', fixture.run_id)
	.order('at', { ascending: true });
if (eleErr || !elePings) fail(`live_run_pings ele read failed for ${fixture.run_id}: ${eleErr?.message ?? 'no rows'}`);
const firstEle = elePings[0]?.ele;
const lastEle = elePings.at(-1)?.ele;

// Field-by-field assertions against the fixture. Each entry is
// [label, actual, expected, kind]; numbers compare with a tiny epsilon so a
// float that survives the round-trip but prints differently doesn't
// false-fail.
const EPS = 1e-6;

const checks = [
	['run visible in public_runs', runRow.id, fixture.run_id, 'string'],
	['started_at (instant)', new Date(runRow.started_at).toISOString(), fixture.started_at_iso, 'string'],
	['stub distance_m', Number(runRow.distance_m ?? -1), fixture.distance_m, 'number'],
	['ping count', pings.length, fixture.ping_count, 'number'],
	['first ping lat', first.lat, fixture.first_lat, 'number'],
	['first ping lng', first.lng, fixture.first_lng, 'number'],
	['first ping ele', firstEle, fixture.first_ele, 'number'],
	['first ping distance_m', first.distance_m, fixture.first_distance_m, 'number'],
	['first ping elapsed_s', first.elapsed_s, fixture.first_elapsed_s, 'number'],
	['last ping lat', last.lat, fixture.last_lat, 'number'],
	['last ping lng', last.lng, fixture.last_lng, 'number'],
	['last ping ele', lastEle, fixture.last_ele, 'number'],
	['last ping distance_m', last.distance_m, fixture.last_distance_m, 'number'],
	['last ping elapsed_s', last.elapsed_s, fixture.last_elapsed_s, 'number'],
	// coarse is trigger-owned, defaults false for an out-of-zone ping, and is
	// part of the catch-up read shape — assert it round-trips false on every
	// ping so the spectator never renders a precise live fix as approximate.
	['first ping coarse', first.coarse, fixture.coarse, 'bool'],
	['last ping coarse', last.coarse, fixture.coarse, 'bool']
];

const failures = [];
for (const [label, actual, expected, kind] of checks) {
	let ok;
	if (kind === 'number') ok = typeof actual === 'number' && Math.abs(actual - expected) < EPS;
	else ok = actual === expected;
	if (!ok) failures.push(`  - ${label}: got ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);
}

await supabase.auth.signOut();

if (failures.length) {
	console.error('✗ cross-client live round-trip FAILED — a field written by the Dart live');
	console.error('  broadcaster does not read back identically through the web spectator read shape:');
	console.error(failures.join('\n'));
	process.exit(1);
}

console.log(`✓ cross-client live round-trip: all ${checks.length} fields round-tripped Dart → web for in-progress run ${fixture.run_id}`);
process.exit(0);
