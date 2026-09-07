// What a typed Supabase client is supposed to catch, and the one thing the
// generated schema cannot tell it.
//
// Two halves. The runtime half scans the two client constructors and pins that
// both still pass the schema — an untyped `createBrowserClient(url, key)` is a
// one-token regression that nothing else in the tree notices, because every
// query keeps compiling and every row silently becomes `any`.
//
// The type half is the assertions below, which `svelte-check` evaluates: this
// file is under `src/`, so a `@ts-expect-error` that stops being an error, or
// an assignment that starts being one, fails the typecheck gate rather than
// this suite. That is deliberate — the claims are about types, and a runtime
// assertion could not make them.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import type { Json } from '../database.types';
import type { AppDatabase, Insertable, Join, Updatable } from './database';

type Functions = AppDatabase['public']['Functions'];

// --- The generated Args carry no nullability, so `AppDatabase` restates it ---

// `mark_attendance(p_attendance text)` has NO default, so the generator emits
// it as a required `string` — while the function's own body branches on
// `p_attendance is not null` and `data.ts` documents "pass null to clear".
const clearAttendance: Functions['mark_attendance']['Args'] = {
	p_event_id: 'e',
	p_user_id: 'u',
	p_instance_start: '2026-01-01T00:00:00Z',
	p_attendance: null,
};

// `search_public_routes(p_query text default null)` is emitted optional, and
// still never `| null`. Saying null explicitly is what keeps the client from
// inheriting whatever default a later migration gives the parameter.
const noQuery: Functions['search_public_routes']['Args'] = {
	p_query: null,
	p_surface: null,
	p_tags: null,
};

// The widening is per-argument, not a blanket `any`: the argument NAMES and
// their base types are still checked, which is the half of the RPC contract
// the generated schema does know.
const misspelled: Functions['mark_attendance']['Args'] = {
	p_event_id: 'e',
	p_user_id: 'u',
	p_instance_start: '2026-01-01T00:00:00Z',
	// @ts-expect-error a misspelled argument is still a misspelled argument
	p_attendence: 'attended',
};

const wrongType: Functions['mark_attendance']['Args'] = {
	p_event_id: 'e',
	p_user_id: 'u',
	p_instance_start: '2026-01-01T00:00:00Z',
	// @ts-expect-error a number is not a text parameter
	p_attendance: 7,
};

// --- Write shapes are the table's, not a bag ---

const runPatch: Updatable<'runs'> = { distance_m: 5000 };
// @ts-expect-error `distance_metres` is not a column of `runs`
const typoPatch: Updatable<'runs'> = { distance_metres: 5000 };
const badBag: Insertable<'runs'> = {
	user_id: 'u',
	started_at: '2026-01-01T00:00:00Z',
	distance_m: 1,
	duration_s: 1,
	// @ts-expect-error a Date does not survive a jsonb round trip as itself
	metadata: { when: new Date() },
};

// --- A select list has to reach supabase-js as a literal ---

const joined: Join<readonly ['id', 'user_id', 'distance_m'], ', '> =
	'id, user_id, distance_m';
// @ts-expect-error the joined literal is exactly the tuple, in order
const misjoined: Join<readonly ['id', 'user_id'], ', '> = 'user_id, id';

void clearAttendance;
void noQuery;
void misspelled;
void wrongType;
void runPatch;
void typoPatch;
void badBag;
void joined;
void misjoined;

// --- Both clients pass the schema ---

test('both Supabase clients are constructed with the schema, not bare', () => {
	// An untyped client is not a compile error anywhere: `@supabase/ssr`
	// declares the generic as `<Database = any>`, so dropping it leaves every
	// `.from()` / `.select()` / `.rpc()` in the app compiling and every row
	// typed `any`. Nothing but this guard would notice.
	for (const file of ['src/lib/core/supabase.ts', 'src/lib/core/supabase-server.ts']) {
		const source = readFileSync(resolve(file), 'utf-8');
		assert.match(
			source,
			/create(Browser|Server)Client<AppDatabase>\(/,
			`${file} must pass the schema to its client — an untyped client compiles and checks nothing`,
		);
	}
});

test('the app schema corrects the generated one rather than replacing it', () => {
	// `database.types.ts` is generated and CI's `gen:types:check` compares it
	// with a fresh run, so the correction cannot live there. It must stay a
	// derivation OF that file, or the two drift on the next migration.
	const source = readFileSync(resolve('src/lib/core/database.ts'), 'utf-8');
	assert.match(
		source,
		/import type \{ Database \} from '\.\.\/database\.types'/,
		'AppDatabase must be derived from the generated Database, never re-declared',
	);
	assert.doesNotMatch(
		source,
		/^\s*(export )?type Database = /m,
		'AppDatabase must not shadow the generated Database with a hand-written one',
	);
});
