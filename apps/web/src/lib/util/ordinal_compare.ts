/**
 * Compare two strings by code unit, for values whose order is an ORDINAL and
 * not a reading order: an ISO-8601 timestamp, an ISO date, a BCP-47 tag.
 *
 * `localeCompare` is the wrong instrument for these and not merely a wasteful
 * one. It answers with a collation, and a collation orders punctuation by the
 * CLDR root's own table rather than by code point — `.` sorts BEFORE `+`
 * there, where the code unit order is the reverse. Postgres renders a
 * `timestamptz` with the fractional part TRIMMED, so two rows in the same
 * second differ in exactly that position:
 *
 *   '2026-01-05T18:00:00+00:00'.localeCompare('2026-01-05T18:00:00.482000+00:00') === 1
 *
 * i.e. the collation calls 18:00:00.000 the LATER of the two, in every locale
 * measured (en, sv, de, tr, ja, ar). A newest-first list built on it puts the
 * older row on top whenever two rows share a second and one lands on it
 * exactly — reachable wherever several rows are stamped by one action, such as
 * archiving a batch of coach threads or importing a set of routes.
 *
 * The result is also independent of the host's ICU data, which is what the
 * one caller that sorts locale TAGS actually needs: that sort exists only to
 * resolve two same-language guide variants deterministically, and a collation
 * makes the answer a property of the server rather than of the input.
 */
export function compareOrdinal(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}
