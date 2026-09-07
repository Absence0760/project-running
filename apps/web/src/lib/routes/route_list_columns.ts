/// The routes-list projection: the columns the list reads, the PostgREST
/// select string built from them, and the row type that says so.
///
/// `fetchRoutes` / `fetchRoutesWithError` select eleven of `routes`' twenty-two
/// columns and used to hand the rows back as `Route`, which declares twenty-one
/// of them (`shadow_hidden` left the overlay in § 1327, because every read path
/// strips it). Ten of those fields — `description`, `tags`, `is_public`,
/// `updated_at`, `slug`, `is_featured`, `featured_at`, `geom`, `geom_public`,
/// `start_point` — are `undefined` at runtime under a type promising them, so a
/// consumer that reads one gets `undefined` with the compiler's blessing.
/// Narrowing the select is right (§ 1229 and the guard above it): `geom`
/// duplicates `waypoints` for server-side spatial queries and doubles the wire
/// payload, and `shadow_hidden` is a moderation column the read boundary strips
/// everywhere else. The defect is the type, not the query.
///
/// So the contract is declared ONCE, here, and both halves are derived from it:
/// the wire string is computed from the column tuple, and `RouteListItem` is
/// `Pick`ed from the same tuple. The query and the type it is read as cannot
/// describe different sets, and the tuple is `satisfies (keyof Route)[]`, so a
/// column that no longer exists after a migration fails to compile rather than
/// silently asking PostgREST for nothing.
import type { Route } from '../types';
import type { Database } from '../database.types';

/// The PostgREST separator. A select list is comma-separated; the space is
/// cosmetic and matches the hand-written literal this replaced.
const COLUMN_SEPARATOR = ', ';

/// A tuple of column names as the string a `.select()` takes. Written as a
/// type because `Array.prototype.join` is declared to return `string`, and the
/// literal is what lets supabase-js infer a row shape from the select list
/// (the reason the constants it replaces carried `as const`).
type Join<T extends readonly string[], D extends string> = T extends readonly []
	? ''
	: T extends readonly [infer Head extends string]
		? Head
		: T extends readonly [infer Head extends string, ...infer Rest extends readonly string[]]
			? `${Head}${D}${Join<Rest, D>}`
			: string;

/// Every column a consumer of the routes list reads: `/routes` (cards, filters,
/// sorts, the star toggle, the track preview) and the three pickers — RunEditor,
/// EventEditor, and the club-transfer modal.
export const ROUTE_LIST_COLUMNS = [
	'id',
	'user_id',
	'club_id',
	'name',
	'distance_m',
	'elevation_m',
	'surface',
	'waypoints',
	'is_starred',
	'run_count',
	'created_at',
] as const satisfies readonly (keyof Route)[];

/// The subset the `public_routes` view can serve. It withholds `waypoints`
/// (a non-owner's line is served only through `clip_route_for_viewer`, § 33)
/// and `is_starred` (the owner's own flag) by construction, so the saved-route
/// read takes what is left and `publicRouteListFill` supplies the difference.
export const PUBLIC_ROUTE_LIST_COLUMNS = [
	'id',
	'user_id',
	'club_id',
	'name',
	'distance_m',
	'elevation_m',
	'surface',
	'run_count',
	'created_at',
] as const satisfies readonly (keyof Route)[];

export const ROUTE_LIST_COLS = ROUTE_LIST_COLUMNS.join(COLUMN_SEPARATOR) as Join<
	typeof ROUTE_LIST_COLUMNS,
	typeof COLUMN_SEPARATOR
>;

export const PUBLIC_ROUTE_LIST_COLS = PUBLIC_ROUTE_LIST_COLUMNS.join(COLUMN_SEPARATOR) as Join<
	typeof PUBLIC_ROUTE_LIST_COLUMNS,
	typeof COLUMN_SEPARATOR
>;

/// A row of the routes list — exactly the columns the query asks for, so
/// reading anything else is a compile error rather than an `undefined`.
export type RouteListItem = Pick<Route, (typeof ROUTE_LIST_COLUMNS)[number]>;

/// A raw `public_routes` row from the saved-route lookup, before
/// `publicRouteListFill` supplies what the view withholds. Union it with the
/// fill and the result is a `RouteListItem`.
export type PublicRouteListRow = Pick<Route, (typeof PUBLIC_ROUTE_LIST_COLUMNS)[number]>;

/// Everything `public_routes` serves. Not a select list — the two catalogue
/// RPCs (`nearby_routes`, `search_public_routes`) are declared `setof
/// public_routes`, so the server fixes the projection and the client's only
/// job is to say what it is. Both readers used to end `as Route[]`, promising
/// the caller seven columns the view withholds by construction, of which
/// `waypoints` is the non-nullable `TrackPoint[]` whose absence was the whole
/// of § 1229.
///
/// Derived from the generated view row rather than enumerated, so a migration
/// that widens or narrows the view moves this type in the same regeneration;
/// `route_list_columns.test.ts` pins that the view names nothing `Route` does
/// not, which is the one way the intersection could silently drop a column.
type PublicRouteViewRow = Database['public']['Views']['public_routes']['Row'];

/// A row of the public-route catalogue. `Pick`ed from `Route` rather than
/// taken as the generated view row: postgres cannot prove a view column NOT
/// NULL, so the generated row types every one of the fifteen as nullable,
/// while the base columns behind them are not. `PublicRouteListRow` below
/// already takes that decision for the same view — this is the same view read
/// through a different door.
export type PublicRouteSummary = Pick<Route, keyof PublicRouteViewRow & keyof Route>;

/// The columns of `routes` the list deliberately does not ask for. Exported so
/// a caller that needs one has to say so — by widening the tuple above, which
/// widens the select in the same edit.
export type RouteListWithheldColumn = Exclude<keyof Route, (typeof ROUTE_LIST_COLUMNS)[number]>;
