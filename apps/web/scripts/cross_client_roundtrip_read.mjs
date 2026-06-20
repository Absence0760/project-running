// Cross-client round-trip — the web **read** half.
//
// Reads back the run that the Dart `ApiClient.saveRun` wrote (see
// packages/api_client/test/cross_client_roundtrip_test.dart) using the
// EXACT read shape of the web data layer's `fetchRunById`
// (apps/web/src/lib/core/data.ts):
//
//   supabase.from('runs').select('*').eq('id', id).eq('user_id', uid)
//     .single()  ->  { ...data, source: parseRunSource(data.source), track }
//
// and asserts field-for-field equality against the fixture the Dart
// half emitted. A mismatch on any field means a value the Dart client
// wrote does NOT round-trip to the value the web client reads — the
// runtime drift that `gen:types:check` (a static type-shape check)
// cannot see.
//
// `parseRunSource` is imported from the real web lib so the source-enum
// parse genuinely runs through web code, not a copy.
//
// Env contract (all required):
//   SUPABASE_TEST_URL          local stack API url (http://127.0.0.1:54321)
//   SUPABASE_TEST_ANON_KEY     local stack anon key
//   CROSS_CLIENT_FIXTURE_IN    path to the fixture JSON the Dart half wrote
//
// Run via tsx so the TS import resolves:
//   node --import tsx apps/web/scripts/cross_client_roundtrip_read.mjs
//
// Exits 0 on a clean round-trip, 1 (with a diff) on any mismatch.

import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { parseRunSource } from '../src/lib/types.ts';

const url = process.env.SUPABASE_TEST_URL;
const anonKey = process.env.SUPABASE_TEST_ANON_KEY;
const fixturePath = process.env.CROSS_CLIENT_FIXTURE_IN;

function fail(msg) {
	console.error(`✗ cross-client round-trip: ${msg}`);
	process.exit(1);
}

if (!url || !anonKey) fail('SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY must be set');
if (!fixturePath) fail('CROSS_CLIENT_FIXTURE_IN must point to the fixture JSON');

const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

const supabase = createClient(url, anonKey);

const { data: signIn, error: signInError } = await supabase.auth.signInWithPassword({
	email: 'runner@test.com',
	password: 'testtest'
});
if (signInError || !signIn?.user) fail(`sign-in failed: ${signInError?.message ?? 'no user'}`);
const userId = signIn.user.id;

// Mirror fetchRunById exactly: '*' select, owner-scoped, single row,
// then the same projection (parseRunSource + a lazily-fetched track).
const { data, error } = await supabase
	.from('runs')
	.select('*')
	.eq('id', fixture.run_id)
	.eq('user_id', userId)
	.single();
if (error || !data) fail(`run ${fixture.run_id} not found via the web read shape: ${error?.message ?? 'no row'}`);

// Lazy track download + gzip decode — the same pipeline fetchRunById
// uses (DecompressionStream is native in Node 24).
let track = null;
if (data.track_url) {
	const { data: blob, error: dlErr } = await supabase.storage.from('runs').download(data.track_url);
	if (dlErr || !blob) fail(`track download failed for ${data.track_url}: ${dlErr?.message ?? 'no data'}`);
	const buf = await blob.arrayBuffer();
	const ds = new DecompressionStream('gzip');
	const decompressed = await new Response(new Response(buf).body.pipeThrough(ds)).arrayBuffer();
	track = JSON.parse(new TextDecoder().decode(decompressed));
}

const run = { ...data, source: parseRunSource(data.source), track };

// Field-by-field assertions against the fixture. Each entry is
// [label, actual, expected]; numbers compare with a tiny epsilon so a
// float that survives jsonb but prints differently doesn't false-fail.
const EPS = 1e-6;
const steps = run.metadata?.steps;
// The web consumes steps via `typeof v === 'number' ? v : null` AND the
// roadmap names `parseInt(run.metadata?.steps)` — assert both the value
// and that it is a JSON number (a Dart string-write would parseInt-coerce
// but fail the typeof-number guard the run-detail screen uses).
const stepsIsNumber = typeof steps === 'number';
const ageGrade = run.metadata?.age_grade;

const checks = [
	['run found', run.id, fixture.run_id, 'string'],
	['distance_m', run.distance_m, fixture.distance_m, 'number'],
	['duration_s', run.duration_s, fixture.duration_s, 'number'],
	['source (parseRunSource)', run.source, fixture.source, 'string'],
	['activity_type', run.activity_type, fixture.activity_type, 'string'],
	['started_at (instant)', new Date(run.started_at).toISOString(), fixture.started_at_iso, 'string'],
	['metadata.steps value', steps, fixture.metadata_steps, 'number'],
	['metadata.steps is JSON number', stepsIsNumber, true, 'bool'],
	['parseInt(metadata.steps)', Number.parseInt(String(steps), 10), fixture.metadata_steps, 'number'],
	['metadata.age_grade', ageGrade, fixture.metadata_age_grade, 'number'],
	['track point count', Array.isArray(track) ? track.length : -1, fixture.track_point_count, 'number'],
	['track first lat', Array.isArray(track) ? track[0]?.lat : null, fixture.track_first_lat, 'number'],
	['track last lng', Array.isArray(track) ? track.at(-1)?.lng : null, fixture.track_last_lng, 'number']
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
	console.error('✗ cross-client round-trip FAILED — a field written by the Dart client');
	console.error('  does not read back identically through the web data layer:');
	console.error(failures.join('\n'));
	process.exit(1);
}

console.log(`✓ cross-client round-trip: all ${checks.length} fields round-tripped Dart → web for run ${fixture.run_id}`);
process.exit(0);
