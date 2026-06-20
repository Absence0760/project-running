// Cross-client round-trip for ROUTES — the web **read** half.
//
// Reads back the route that the Dart `ApiClient.saveRoute` wrote (see
// packages/api_client/test/cross_client_roundtrip_route_test.dart) using
// the EXACT owner-read shape of the web data layer's `fetchRouteById`
// (apps/web/src/lib/core/data.ts):
//
//   supabase.from('routes').select('*').eq('id', id).maybeSingle()
//     ->  { ...rest, surface: parseRouteSurface(rest.surface) }  (shadow_hidden stripped)
//
// and asserts field-for-field equality against the fixture the Dart half
// emitted — including the waypoints array structure (`{lat,lng,ele}` per
// point) and the `RouteSurface` narrow union. A mismatch on any field
// means a value the Dart client wrote does NOT round-trip to the value
// the web client reads — the runtime drift `gen:types:check` cannot see.
//
// `parseRouteSurface` is imported from the real web lib so the surface
// narrow genuinely runs through web code, not a copy. The script also
// asserts `shadow_hidden` (the trigger-owned moderation column the Dart
// saveRoute strips) round-trips as false AND is not surfaced by the read
// shape — matching `fetchRouteById`, which projects it away.
//
// Env contract (all required):
//   SUPABASE_TEST_URL              local stack API url (http://127.0.0.1:54321)
//   SUPABASE_TEST_ANON_KEY         local stack anon key
//   CROSS_CLIENT_ROUTE_FIXTURE_IN  path to the fixture JSON the Dart half wrote
//
// Run via tsx so the TS import resolves:
//   node --import tsx apps/web/scripts/cross_client_roundtrip_route_read.mjs
//
// Exits 0 on a clean round-trip, 1 (with a diff) on any mismatch.

import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { parseRouteSurface } from '../src/lib/types.ts';

const url = process.env.SUPABASE_TEST_URL;
const anonKey = process.env.SUPABASE_TEST_ANON_KEY;
const fixturePath = process.env.CROSS_CLIENT_ROUTE_FIXTURE_IN;

function fail(msg) {
	console.error(`✗ cross-client route round-trip: ${msg}`);
	process.exit(1);
}

if (!url || !anonKey) fail('SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY must be set');
if (!fixturePath) fail('CROSS_CLIENT_ROUTE_FIXTURE_IN must point to the fixture JSON');

const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

const supabase = createClient(url, anonKey);

const { data: signIn, error: signInError } = await supabase.auth.signInWithPassword({
	email: 'runner@test.com',
	password: 'testtest'
});
if (signInError || !signIn?.user) fail(`sign-in failed: ${signInError?.message ?? 'no user'}`);

// Mirror fetchRouteById's owner branch exactly: '*' select on the base
// `routes` table, single row by id (RLS scopes it to the owner), then the
// same projection — strip shadow_hidden, narrow surface through the real
// parseRouteSurface.
const { data, error } = await supabase
	.from('routes')
	.select('*')
	.eq('id', fixture.route_id)
	.maybeSingle();
if (error || !data) fail(`route ${fixture.route_id} not found via the web read shape: ${error?.message ?? 'no row'}`);

const { shadow_hidden, ...rest } = data;
const route = { ...rest, surface: parseRouteSurface(rest.surface) };

const wps = Array.isArray(route.waypoints) ? route.waypoints : [];
const first = wps[0] ?? {};
const last = wps.at(-1) ?? {};

// Field-by-field assertions against the fixture. Each entry is
// [label, actual, expected, kind]; numbers compare with a tiny epsilon so
// a float that survives jsonb but prints differently doesn't false-fail.
const EPS = 1e-6;
const tagsEqual =
	Array.isArray(route.tags) &&
	route.tags.length === fixture.tags.length &&
	route.tags.every((t, i) => t === fixture.tags[i]);

const checks = [
	['route found', route.id, fixture.route_id, 'string'],
	['name', route.name, fixture.name, 'string'],
	['distance_m', route.distance_m, fixture.distance_m, 'number'],
	['elevation_m', route.elevation_m, fixture.elevation_m, 'number'],
	['surface (parseRouteSurface)', route.surface, fixture.surface, 'string'],
	['is_public', route.is_public, fixture.is_public, 'bool'],
	['tags array', tagsEqual, true, 'bool'],
	['description', route.description, fixture.description, 'string'],
	['waypoint count', wps.length, fixture.waypoint_count, 'number'],
	['waypoint[0].lat', first.lat, fixture.wp_first_lat, 'number'],
	['waypoint[0].lng', first.lng, fixture.wp_first_lng, 'number'],
	['waypoint[0].ele', first.ele, fixture.wp_first_ele, 'number'],
	['waypoint[last].lat', last.lat, fixture.wp_last_lat, 'number'],
	['waypoint[last].lng', last.lng, fixture.wp_last_lng, 'number'],
	['waypoint[last].ele', last.ele, fixture.wp_last_ele, 'number'],
	// The DB value of shadow_hidden round-trips as false (Dart strips it on
	// write, the column defaults false)...
	['shadow_hidden (db value)', shadow_hidden, fixture.shadow_hidden, 'bool'],
	// ...and the read shape must NOT surface it to the client (the public
	// view projects it away; the owner read strips it the same way).
	["shadow_hidden absent from read shape", 'shadow_hidden' in route, false, 'bool']
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
	console.error('✗ cross-client route round-trip FAILED — a field written by the Dart client');
	console.error('  does not read back identically through the web data layer:');
	console.error(failures.join('\n'));
	process.exit(1);
}

console.log(`✓ cross-client route round-trip: all ${checks.length} fields round-tripped Dart → web for route ${fixture.route_id}`);
process.exit(0);
