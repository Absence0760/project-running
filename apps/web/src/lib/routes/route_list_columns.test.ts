// The routes-list projection is one declaration with two derivations, and
// these pin both ends of it.
//
// The defect the module closes is invisible to a runtime test: eleven of
// `routes`' twenty-two columns are absent from the wire under a type that
// declares them, and nothing throws — a consumer reading one gets `undefined`
// with the compiler's blessing. So the strongest assertions here are
// COMPILE-time (`@ts-expect-error`, and an `Exclude` that must be `never`),
// checked by `pnpm -C apps/web check` rather than by `tsx --test`; the runtime
// half proves the derived select string is byte-identical to the one
// `core/data.ts` actually hands PostgREST, so the type cannot describe a
// different set than the query asks for.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { publicRouteListFill } from '../core/data_normalise';
import type { Route } from '../types';
import type { Database } from '../database.types';
import {
	PUBLIC_ROUTE_LIST_COLS,
	PUBLIC_ROUTE_LIST_COLUMNS,
	ROUTE_LIST_COLS,
	ROUTE_LIST_COLUMNS,
	type PublicRouteListRow,
	type PublicRouteSummary,
	type RouteListItem,
} from './route_list_columns';

// ── Compile-time: the type refuses what the query never asked for ──

/// `T extends never` only holds for the empty union, so a non-empty argument
/// is a compile error naming the columns that broke the claim.
type AssertNever<T extends never> = T;

/// `shadow_hidden` is not merely absent from the list projection — it left the
/// `Route` overlay entirely (§ 1327), because every read path strips it:
/// `fetchRouteById` destructures it off the owner read, `public_routes`
/// projects it away, and neither column tuple names it. Pinned on `Route`
/// rather than only on `RouteListItem`, because re-adding it to the overlay
/// would put it back on `fetchRouteById`'s return without touching the `Pick`
/// below — the `@ts-expect-error` further down would still be used, and
/// nothing else would notice.
export type RouteDeclaresNoModerationState = AssertNever<Extract<keyof Route, 'shadow_hidden'>>;

/// The saved-route half reads `public_routes` and fills what the view
/// withholds. If the fill ever stops covering the difference — or starts
/// covering more than it — one of these stops being `never` and fails
/// `svelte-check`, which is a stronger claim than the runtime key check in
/// `data_normalise.test.ts`: that one proves a key is present, this one
/// proves the SHAPE is a `RouteListItem`.
type PublicRowFilled = PublicRouteListRow & ReturnType<typeof publicRouteListFill>;
export type PublicFillLeavesNoGap = AssertNever<Exclude<keyof RouteListItem, keyof PublicRowFilled>>;
export type PublicFillAddsNothingExtra = AssertNever<
	Exclude<keyof PublicRowFilled, keyof RouteListItem>
>;

/// Each of these was a field `Route` promised and the query never fetched.
/// The `@ts-expect-error` is the mutation test: widen `RouteListItem` back
/// towards `Route` and the suppressed error disappears, which fails the build.
export const withheldReadsDoNotCompile = (r: RouteListItem) => [
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.description,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.tags,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.is_public,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.updated_at,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.slug,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.is_featured,
	// @ts-expect-error — not in ROUTE_LIST_COLUMNS
	r.featured_at,
	// @ts-expect-error — server-owned moderation column: not in the projection,
	// and since § 1327 not on `Route` either
	r.shadow_hidden,
	// @ts-expect-error — server-spatial only, doubles the wire payload
	r.geom,
	// @ts-expect-error — server-spatial only
	r.geom_public,
	// @ts-expect-error — leaks the run start location
	r.start_point,
];

/// `PublicRouteSummary` is the intersection of the generated `public_routes`
/// row with `Route`, so a view column `Route` does not have would be dropped
/// silently — the type would still compile and still be wrong. This is the one
/// direction the intersection cannot state for itself.
export type PublicViewNamesNothingRouteDoesNot = AssertNever<
	Exclude<keyof Database['public']['Views']['public_routes']['Row'], keyof Route>
>;

/// The catalogue RPCs serve the view, not the table, so the seven columns
/// `public_routes` withholds must not be readable off their result. `waypoints`
/// is the one that mattered: it is `TrackPoint[]`, non-nullable, and a caller
/// that mapped over it got `undefined.map` — § 1229 — under a `Route` cast.
export const viewWithheldReadsDoNotCompile = (r: PublicRouteSummary) => [
	// @ts-expect-error — served only through clip_route_for_viewer (§ 33)
	r.waypoints,
	// @ts-expect-error — the owner's own flag, not a property of a public route
	r.is_starred,
	// @ts-expect-error — server-spatial only
	r.geom,
	// @ts-expect-error — server-spatial only
	r.geom_public,
	// @ts-expect-error — leaks the route start location
	r.start_point,
	// @ts-expect-error — server-owned moderation column (§ 1327)
	r.shadow_hidden,
];

/// The catalogue card reads these nine off every row, so they have to survive
/// the narrowing or the RouteExplorer stops compiling instead of the type
/// stopping being a lie.
export const catalogueReadsCompile = (r: PublicRouteSummary) => [
	r.id,
	r.user_id,
	r.name,
	r.distance_m,
	r.elevation_m,
	r.surface,
	r.run_count,
	r.is_featured,
	r.tags,
];

/// The saved-route half of the list reads the same view, so its tuple is a
/// subset of what the view serves — not merely of what `routes` has, which is
/// what the column check further down proves and is not the same claim: adding
/// `waypoints` to the public tuple passes that one and 400s at runtime.
export type PublicListIsAViewSubset = AssertNever<
	Exclude<keyof PublicRouteListRow, keyof PublicRouteSummary>
>;

/// Every column the list DOES read has to stay readable, or the narrowing has
/// gone too far and the pin above would be the only thing left passing.
export const projectedReadsCompile = (r: RouteListItem) => [
	r.id,
	r.user_id,
	r.club_id,
	r.name,
	r.distance_m,
	r.elevation_m,
	r.surface,
	r.waypoints,
	r.is_starred,
	r.run_count,
	r.created_at,
];

// ── Runtime: the derived string is the one the query actually sends ──

test('the derived select strings are what core/data.ts hands PostgREST', () => {
	// Reason: the join is asserted to a template-literal type because
	// `Array.prototype.join` returns `string`, and an assertion proves nothing
	// on its own. This is what proves it — the derived string compared against
	// the literal `.select()` is called with. Until `data.ts` imports these
	// constants it declares its own copies, so accept either shape and fail
	// when neither is present: a renamed constant must not read as agreement.
	const source = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	for (const [name, derived] of [
		['ROUTE_LIST_COLS', ROUTE_LIST_COLS],
		['PUBLIC_ROUTE_LIST_COLS', PUBLIC_ROUTE_LIST_COLS],
	] as const) {
		const declared = source.match(new RegExp(`const ${name}\\s*=\\s*'([^']*)'`));
		if (declared) {
			assert.equal(
				declared[1],
				derived,
				`${name} in core/data.ts asks for a different column set than route_list_columns.ts declares — the rows would be read as a type the query cannot produce`,
			);
		} else {
			assert.match(
				source,
				new RegExp(`import[^;]*\\b${name}\\b[^;]*from '\\.\\./routes/route_list_columns'`),
				`${name} is neither declared in core/data.ts nor imported from route_list_columns.ts — re-anchor this guard`,
			);
		}
	}
});

test('the public column list is a subset of the owned one', () => {
	// Reason: the fill is defined as the set difference. A public column the
	// owned read does not take makes that difference meaningless and leaves a
	// field on the saved half that the owned half has never carried.
	const owned = new Set<string>(ROUTE_LIST_COLUMNS);
	const extra = PUBLIC_ROUTE_LIST_COLUMNS.filter((c) => !owned.has(c));
	assert.deepEqual(extra, []);
});

test('neither list repeats a column', () => {
	// Reason: PostgREST accepts a duplicate silently, and a duplicate in the
	// tuple is invisible to `Pick` — the type would look correct while the
	// wire string carried a column twice.
	for (const cols of [ROUTE_LIST_COLUMNS, PUBLIC_ROUTE_LIST_COLUMNS]) {
		assert.equal(new Set<string>(cols).size, cols.length);
	}
});

test('the deliberately withheld columns stay out of the select', () => {
	// Reason: each is withheld for its own reason, and the reasons are not
	// interchangeable — `geom` for payload size (issue #344), `start_point`
	// and `geom_public` because raw geometry bypasses the privacy clip
	// (§ 33), `shadow_hidden` because it is server-owned moderation state
	// `fetchRouteById` already strips from the owner read.
	for (const withheld of ['geom', 'geom_public', 'start_point', 'shadow_hidden']) {
		assert.ok(
			!(ROUTE_LIST_COLUMNS as readonly string[]).includes(withheld),
			`${withheld} must not be in the routes-list projection`,
		);
		assert.ok(
			!(PUBLIC_ROUTE_LIST_COLUMNS as readonly string[]).includes(withheld),
			`${withheld} must not be in the public routes-list projection`,
		);
	}
});

test('every column named is a real column of routes', () => {
	// Reason: `satisfies (keyof Route)[]` already refuses a name that is not a
	// column — but only while `database.types.ts` is current. This reads the
	// generated file directly, so a migration that drops a column fails here
	// even if the regenerated types have not landed in the same tree.
	const types = readFileSync(resolve('src/lib/database.types.ts'), 'utf-8');
	const start = types.indexOf('      routes: {');
	assert.ok(start > 0, 'could not locate the routes table in database.types.ts — re-anchor');
	const row = types.slice(types.indexOf('Row: {', start), types.indexOf('Insert: {', start));
	const columns = new Set(
		row
			.split('\n')
			.map((l) => l.trim())
			.filter((l) => l.includes(':'))
			.map((l) => l.split(':')[0].trim()),
	);
	for (const c of [...ROUTE_LIST_COLUMNS, ...PUBLIC_ROUTE_LIST_COLUMNS]) {
		assert.ok(columns.has(c), `${c} is not a column of routes`);
	}
});
