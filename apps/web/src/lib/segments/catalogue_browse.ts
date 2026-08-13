/**
 * Browse shaping for the free-standing famous-segment catalogue
 * (decisions §233).
 *
 * The catalogue shipped with a detail page and the run-detail "Famous
 * segments" chips, but nothing that lets a runner FIND a segment they
 * haven't already run — the one thing a curated catalogue exists for. The
 * schema anticipated it (`global_segments.region` / `country_code` are
 * documented in `20270411_001` as the coarse filter/grouping columns "on
 * the browse page") and so does the fetcher (`fetchGlobalSegmentsWithError`
 * carries the browse-page error contract); only the surface was missing.
 *
 * Filtering is client-side because the curated v1 catalogue is bounded by
 * `GLOBAL_SEGMENT_SCORING_LIMIT` (500 rows) and already fetched whole — a
 * server round-trip per keystroke would buy nothing.
 *
 * Pure module — no Supabase, no DOM, no runes.
 */

import { ENUM_VOCABULARIES } from '../i18n/enum_labels';

/**
 * The catalogue fields the browse surface reads. Structurally satisfied by
 * `GlobalSegment` from `core/data`, without dragging the `$env`-bound client
 * into a unit test.
 *
 * `distance_m` / `elevation_m` accept a string because they are Postgres
 * `numeric` columns, and PostgREST serialises `numeric` as a JSON string to
 * preserve precision. `GlobalSegment` optimistically types them `number` and
 * every existing read site (`/segments/[id]`, the scoring sweep) wraps them in
 * `Number(...)` — so the honest input type here is the widened one, and the
 * coercion happens once, inside.
 */
export interface CatalogueSegment {
	id: string;
	name: string;
	surface: string;
	region: string | null;
	distance_m: number | string;
	elevation_m: number | string | null;
}

export type CatalogueSort = 'name' | 'shortest' | 'longest' | 'climb';

export interface CatalogueFilters {
	query?: string;
	region?: string | null;
	surface?: string | null;
}

/**
 * Case- and diacritic-insensitive search key. Applied to BOTH sides of every
 * comparison, and built character-by-character (NFD decompose → drop combining
 * marks → lowercase), so it can only ever widen a match: anything that matched
 * on the raw strings still matches on the folded ones. That's what lets a
 * reader type "champs-elysees" and reach "Champs-Élysées" without a keyboard
 * that has the accent.
 */
function fold(value: string): string {
	return value.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
}

/** Finite numeric value of a possibly-stringly `numeric` column, else null. */
function num(value: number | string | null | undefined): number | null {
	if (value == null) return null;
	const n = Number(value);
	return Number.isFinite(n) ? n : null;
}

/**
 * Total order on names. Compares folded names with `<` / `>` rather than
 * `localeCompare` so the order is identical in every runtime — collation
 * varies with the host's ICU data, and a catalogue that reorders itself
 * between a test runner and a browser is a bug that only shows up in CI.
 * Ties break on `id`, so the result never depends on sort stability either.
 */
function byName(a: CatalogueSegment, b: CatalogueSegment): number {
	const fa = fold(a.name);
	const fb = fold(b.name);
	if (fa !== fb) return fa < fb ? -1 : 1;
	if (a.id !== b.id) return a.id < b.id ? -1 : 1;
	return 0;
}

/**
 * The identity `catalogueRegions` dedupes on AND `filterCatalogue` compares
 * against — one function for both, because they are one decision. The dropdown
 * collapses "Zürich, CH" and "zurich, ch" onto a single offered spelling, so a
 * filter matching the raw string would return half the rows its own option
 * claims to cover: a fold-built list feeding an exact-match filter loses
 * matches the list asserts exist. That is the mirror of the property the text
 * query is careful to hold, and it has to be closed in the same place.
 *
 * Regions are free-text curator input, which is why they fold. `surface` is a
 * CHECK-constrained identifier (`road` / `trail` / `mixed`), so
 * `catalogueSurfaces` does not fold-dedupe and the surface filter compares
 * verbatim — folding a database token would be inventing equivalences the
 * database does not have.
 */
function regionKey(region: string | null | undefined): string | null {
	const trimmed = region?.trim();
	return trimmed ? fold(trimmed) : null;
}

/** Distinct non-blank regions present in the catalogue, in display order. */
export function catalogueRegions(segments: readonly CatalogueSegment[]): string[] {
	const seen = new Map<string, string>();
	for (const s of segments) {
		const key = regionKey(s.region);
		if (key == null) continue;
		if (!seen.has(key)) seen.set(key, s.region!.trim());
	}
	return Array.from(seen.entries())
		.sort(([a], [b]) => (a === b ? 0 : a < b ? -1 : 1))
		.map(([, region]) => region);
}

/**
 * Distinct surfaces present in the catalogue, in the canonical `RouteSurface`
 * order rather than alphabetically — the dropdown then reads road / trail /
 * mixed everywhere, matching the route builder's own ordering. A value outside
 * the vocabulary (this client older than the database) is kept and sorted after
 * the known ones, so it stays selectable instead of silently vanishing from the
 * filter while its segments remain in the list.
 */
export function catalogueSurfaces(segments: readonly CatalogueSegment[]): string[] {
	const known = ENUM_VOCABULARIES.routeSurface as readonly string[];
	const present = new Set<string>();
	for (const s of segments) {
		const surface = s.surface?.trim();
		if (surface) present.add(surface);
	}
	const inOrder = known.filter((s) => present.has(s));
	const unknown = Array.from(present)
		.filter((s) => !known.includes(s))
		.sort((a, b) => {
			const fa = fold(a);
			const fb = fold(b);
			return fa === fb ? 0 : fa < fb ? -1 : 1;
		});
	return [...inOrder, ...unknown];
}

/**
 * Narrows the catalogue to the rows matching every supplied filter. The text
 * query matches a segment's name OR its region, so "Berlin" and "Tiergarten"
 * both find the same row. Region and surface are whole-value matches against
 * what `catalogueRegions` / `catalogueSurfaces` offered — region through
 * `regionKey` (see there for why one folds and the other does not), surface
 * verbatim.
 *
 * Returns a new array — the caller's list is a `$derived` source and must not
 * be mutated.
 */
export function filterCatalogue(
	segments: readonly CatalogueSegment[],
	filters: CatalogueFilters = {},
): CatalogueSegment[] {
	const query = fold(filters.query?.trim() ?? '');
	const region = regionKey(filters.region);
	const surface = filters.surface?.trim() || null;
	return segments.filter((s) => {
		if (region != null && regionKey(s.region) !== region) return false;
		if (surface != null && s.surface !== surface) return false;
		if (!query) return true;
		return fold(s.name).includes(query) || fold(s.region ?? '').includes(query);
	});
}

/**
 * Orders the catalogue for display. Returns a new array.
 *
 * A segment whose `distance_m` / `elevation_m` is absent or unparseable sorts
 * LAST under every numeric order, including the descending ones — an unknown
 * climb must never be presented as the biggest climb.
 */
export function sortCatalogue(
	segments: readonly CatalogueSegment[],
	sort: CatalogueSort,
): CatalogueSegment[] {
	const out = segments.slice();
	switch (sort) {
		case 'shortest':
			return out.sort((a, b) => compareNumeric(num(a.distance_m), num(b.distance_m), 1) || byName(a, b));
		case 'longest':
			return out.sort((a, b) => compareNumeric(num(a.distance_m), num(b.distance_m), -1) || byName(a, b));
		case 'climb':
			return out.sort((a, b) => compareNumeric(num(a.elevation_m), num(b.elevation_m), -1) || byName(a, b));
		case 'name':
		default:
			return out.sort(byName);
	}
}

/** `direction` is 1 for ascending, -1 for descending. Nulls always sort last. */
function compareNumeric(a: number | null, b: number | null, direction: 1 | -1): number {
	if (a == null && b == null) return 0;
	if (a == null) return 1;
	if (b == null) return -1;
	if (a === b) return 0;
	return a < b ? -direction : direction;
}
