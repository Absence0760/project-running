import { m } from './store.svelte';
import { enumLabelKey, isEnumValue, type EnumVocabulary } from './enum_labels';

/// Localized name for a stored narrow-union value. Reading `m()` here makes
/// every call site re-render on a locale change; the value domain and the key
/// builder live in the rune-free `enum_labels.ts` sibling so they stay
/// tsx-testable.
///
/// An unrecognised value is returned VERBATIM, and an absent one as the empty
/// string, for the reason `activityTypeLabel` gives: the CHECK constraints mean
/// a stray value can only appear when this client is older than the database,
/// and a prettified token is indistinguishable from a real translation — it
/// hides the drift on exactly the surface where it would be noticed.
function label(vocab: EnumVocabulary, value: string | null | undefined): string {
	if (!value) return '';
	return isEnumValue(vocab, value) ? m(enumLabelKey(vocab, value)) : value;
}

export function routeSurfaceLabel(value: string | null | undefined): string {
	return label('routeSurface', value);
}

export function joinPolicyLabel(value: string | null | undefined): string {
	return label('joinPolicy', value);
}

export function clubRoleLabel(value: string | null | undefined): string {
	return label('clubRole', value);
}

export function rsvpStatusLabel(value: string | null | undefined): string {
	return label('rsvpStatus', value);
}
