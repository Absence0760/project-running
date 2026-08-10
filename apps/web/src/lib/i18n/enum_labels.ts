import type { MessageKey } from './messages';

/// The narrow unions from `types.ts` whose values reach the UI as a NAME, each
/// mapped to the one catalogue namespace that names it.
///
/// Same contract `activityTypeKey` holds for `runs.activity_type` (decisions
/// § 547), generalised because the same defect had re-grown four more times:
/// `road` was "Asfalto" on the route builder and "Carretera" in the routes
/// filter in Spanish, `going` was "J'y vais" on an event and "Participe" on the
/// club home in French — and half a dozen surfaces skipped the vocabulary
/// entirely and printed the database token, which reads as English in all six
/// locales.
///
/// The value domain is the union declaration in `types.ts`, mirrored here and
/// pinned by `enum_vocabulary.test.ts` — a widened union fails the build until
/// the catalogues catch up. Keys are the value VERBATIM (`clubRole.race_director`,
/// not `clubRole.raceDirector`) so the key is derivable from the stored value
/// with no naming convention in between.
///
/// Registering a union here is what makes it guarded; a union whose values only
/// pick an icon or a CSS class does not belong (nothing names it).
export const ENUM_VOCABULARIES = {
	routeSurface: ['road', 'trail', 'mixed'],
	joinPolicy: ['open', 'request', 'invite'],
	clubRole: ['owner', 'admin', 'event_organiser', 'race_director', 'member'],
	rsvpStatus: ['going', 'maybe', 'declined', 'waitlisted'],
} as const satisfies Record<string, readonly string[]>;

export type EnumVocabulary = keyof typeof ENUM_VOCABULARIES;

/// The PascalCase `types.ts` union each vocabulary mirrors. Read by the guard,
/// which derives the value domain from the declaration rather than restating it.
export const ENUM_UNION_NAMES: Record<EnumVocabulary, string> = {
	routeSurface: 'RouteSurface',
	joinPolicy: 'JoinPolicy',
	clubRole: 'ClubRole',
	rsvpStatus: 'RsvpStatus',
};

export function enumLabelKey(vocab: EnumVocabulary, value: string): MessageKey {
	return `${vocab}.${value}` as MessageKey;
}

export function isEnumValue(vocab: EnumVocabulary, value: string): boolean {
	return (ENUM_VOCABULARIES[vocab] as readonly string[]).includes(value);
}
