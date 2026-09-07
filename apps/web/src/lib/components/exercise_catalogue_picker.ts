/**
 * The exercise-catalogue picker's decision logic, separated from its markup.
 *
 * `ExerciseCataloguePicker.svelte` renders three mutually exclusive things —
 * a result list, an explanation, or a create-custom affordance — and which
 * one it renders is a question about the catalogue, not about the DOM. Held
 * inside `$derived` expressions it was answerable only by a browser:
 * [§ 1278](../../../../../docs/architecture/decisions.md) recorded that
 * `apps/web` runs its unit suite under `tsx --test`, which cannot compile a
 * Svelte component, so the fix that closed § 1276's dead end shipped with no
 * behavioural pin at all. Moved here it is an ordinary pure module the
 * existing harness can hold, and the pin costs no new runner and no new
 * dependency.
 *
 * The logic is not the `String.includes` glue § 1278 declined to extract for.
 * The picker has a THIRD state that neither `matches` nor `canCreate` can
 * express on its own: a query naming an entry the category filter is hiding.
 *
 * Pure module — no Svelte, no i18n, no Supabase. Entries are matched
 * structurally, so the caller's row type needs no relationship to this file.
 */

import { normaliseExerciseName } from '../gym/gym_prs';

/// The three fields the picker's decisions read. Declared structurally rather
/// than as `$lib/types`' `Exercise`, so this module stays importable by the
/// unit runner (which resolves no `$lib` alias) and testable without a
/// twenty-column fixture.
export interface CatalogueEntry {
	id: string;
	name: string;
	category: string;
}

/// The picker's two inputs. `category` is a catalogue category id or the
/// UI-only `'all'` sentinel.
export interface CatalogueFilter {
	query: string;
	category: string;
}

export interface CataloguePickerView<E extends CatalogueEntry> {
	/// Entries to list: category- and query-filtered, in display order.
	matches: E[];
	/// Whether a custom may be created under the typed name. False while the
	/// query is blank, and false whenever the catalogue ALREADY holds that
	/// name — under any category, because `exercises` is keyed on the folded
	/// name and a second row under it is a duplicate whichever category it
	/// claims. Narrowing this to the visible set would trade § 1276's dead end
	/// for a duplicate-key write.
	canCreate: boolean;
	/// The entry the query names exactly while the category filter hides it,
	/// else null. This is the state that has no honest rendering without it:
	/// `matches` is empty and `canCreate` is false, which the markup used to
	/// resolve to a bare "No exercises match." beside no create button and no
	/// explanation — the exercise existed, was not shown, and could not be
	/// added (the residual half of § 1276). Always null under `'all'`, where a
	/// key EQUAL to the query necessarily contains it and the entry is
	/// therefore in `matches`.
	hiddenExact: E | null;
}

/**
 * Total order on display names.
 *
 * Compares with `localeCompare` over the DISPLAY name, not with the folded
 * key: ordering a human-facing list is not keying it, and a code-unit compare
 * over folded keys files every accented name after `z` (§ 1276). Ties break on
 * `id` so the answer is a total order — `localeCompare` reports 0 for names a
 * collation considers equivalent, and resolving those by input order makes the
 * list depend on the order the server happened to return.
 */
function byName<E extends CatalogueEntry>(a: E, b: E): number {
	const c = a.name.localeCompare(b.name);
	if (c !== 0) return c < 0 ? -1 : 1;
	if (a.id !== b.id) return a.id < b.id ? -1 : 1;
	return 0;
}

/**
 * What the picker should show for `entries` under `filter`.
 *
 * Both sides of every name comparison fold through `normaliseExerciseName`,
 * the one derivation of the exercise grouping key (§ 1175). That is what makes
 * the empty-list and no-create states consistent with each other: an entry
 * whose key EQUALS the query's key necessarily contains it, so an exact match
 * can only be missing from `matches` because the category filter removed it —
 * which is exactly what `hiddenExact` reports.
 */
export function cataloguePickerView<E extends CatalogueEntry>(
	entries: readonly E[],
	filter: CatalogueFilter,
): CataloguePickerView<E> {
	const key = normaliseExerciseName(filter.query);
	const inCategory = (e: E) => filter.category === 'all' || e.category === filter.category;

	const matches = entries
		.filter(inCategory)
		.filter((e) => key === '' || normaliseExerciseName(e.name).includes(key))
		.sort(byName);

	if (key === '') return { matches, canCreate: false, hiddenExact: null };

	const exact = entries.filter((e) => normaliseExerciseName(e.name) === key);
	const shown = exact.find(inCategory);
	return {
		matches,
		canCreate: exact.length === 0,
		hiddenExact: shown === undefined ? (exact[0] ?? null) : null,
	};
}
