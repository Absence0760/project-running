import { m } from '$lib/i18n/store.svelte';
import { activityTypeKey, isActivityType } from './activity_type';

/// Localized label for a stored `activity_type`. A null/absent value is `run`
/// (the column default). Reading `m()` here makes every call site re-render on
/// a locale change; the pure half (value domain, icons, key builder) lives in
/// the rune-free `activity_type.ts` sibling so it stays tsx-testable.
///
/// An unrecognised value is returned VERBATIM rather than title-cased. The
/// CHECK constraint means it can only appear when this client is older than the
/// database, and a title-cased token ("Stroller") is indistinguishable from a
/// real translation — it hides the drift on exactly the surface where it would
/// be noticed. The raw token reads as data, and the vocabulary guard keeps the
/// case unreachable for every value the CHECK admits.
export function activityTypeLabel(value: string | null | undefined): string {
	const v = value ?? 'run';
	return isActivityType(v) ? m(activityTypeKey(v)) : v;
}
