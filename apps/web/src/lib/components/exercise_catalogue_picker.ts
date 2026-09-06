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
 * Pure module — no Svelte, no runes, no Supabase, and it resolves no
 * user-facing string. Entries are matched structurally, so the caller's row
 * type needs no relationship to this file.
 */

import { normaliseExerciseName } from '../gym/gym_prs';
import { compareFoldedNames } from '../segments/catalogue_browse';

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
 * Delegates to `catalogue_browse`'s `compareFoldedNames`, the one comparator
 * the product orders a name list with — the famous-segment catalogue, the
 * routes list on both platforms (§ 1337) and the mobile twin of this very
 * picker (§ 1334) already read it. This module was the last name list still
 * collating.
 *
 * § 1276 chose `localeCompare` here on the grounds that ordering a
 * human-facing list is not keying it, which is true and is not what decided
 * it. A collation is answered by the HOST's ICU data, so the web picker's
 * order is a property of the reader's browser; `compareFoldedNames` is
 * answered by a table committed beside the code, so it is a property of the
 * catalogue. Measured over the 43 seeded globals exactly as
 * `20270222_001` inserts them the two instruments are indistinguishable —
 * identical order, zero discordant pairs, and identical under every one of
 * ten host locales. They part the moment a user creates a custom with a
 * letter outside ASCII: over those 43 plus nine plausible non-English
 * customs, 118 of 1,326 pairs are ordered oppositely and the FIRST row of the
 * list differs, while the collation itself then disagrees with itself across
 * `sv-SE`, `da-DK`, `tr-TR` and `pl-PL`. So the choice is not between a right
 * order and a wrong one but between one order and per-reader orders, and a
 * catalogue holding names from several languages has no locale that is
 * correct for all of them anyway.
 *
 * Here that is more than a consistency preference, because this list's order
 * has a persisted consequence. A user may shadow a seeded global with a
 * custom of the same folded name (`api_database.md`, the two partial
 * uniques), and `GymEditor`'s `catalogueByKey` resolves a typed name to ONE
 * `exercises.id` by walking the catalogue — so which row a logged set binds
 * to follows from list order. An order that differs between the phone and the
 * browser is then two answers to that question.
 *
 * The residual is the one § 1334 states: a fold is not a collation, so the
 * letters with no canonical decomposition (`ø`, `đ`, `ł`, `ß`, `æ`) still file
 * after `z` where ICU interleaves them. That is deliberate and is the same
 * trade `catalogue_browse` took.
 *
 * Ties break on `id` inside the shared comparator, so the answer is a total
 * order — the fold calls two spellings of one name equal, and resolving those
 * by input order makes the list depend on the order the server returned.
 */
function byName<E extends CatalogueEntry>(a: E, b: E): number {
	return compareFoldedNames(a.name, a.id, b.name, b.id);
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
