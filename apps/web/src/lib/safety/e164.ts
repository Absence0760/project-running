/// Normalisation for the owner-stored safety-contact phone number
/// (`safety_contacts.contact_phone`, migration `20270410_001`).
///
/// The column carries a CHECK of `^\+[1-9][0-9]{6,14}$` — bare E.164, no
/// separators. Nobody types a phone number that way: they paste
/// `+44 7700 900123` off a contact card, or write the ITU access prefix
/// `0044…` instead of `+`. Validating the raw string against the CHECK
/// rejects all of those as "invalid", which reads to the owner as "this
/// number is wrong" when it is simply punctuated.
///
/// So the input is repaired first, and only then graded. The one repair that
/// is NOT cosmetic is the parenthesised trunk zero: `+44 (0) 7700 900123`
/// writes the national prefix a caller drops when dialling internationally.
/// Blindly stripping the brackets keeps the `0` and yields
/// `+4407700900123` — a *different, conforming* number, which is far worse
/// than a refusal, because it would silently send the overdue-run alert to
/// nobody. `(0)` is deleted whole, before any other bracket is touched.
///
/// Anything the repair cannot bring to E.164 is REFUSED rather than guessed:
/// a national-format number carries no country, and inventing one would arm
/// a safety escalation pointed at a stranger.
export const E164_PATTERN = /^\+[1-9][0-9]{6,14}$/;

/// The parenthesised national trunk prefix, e.g. the `(0)` in
/// `+44 (0) 7700 900123`. Deleted whole — see the note above.
const TRUNK_ZERO = /\(\s*0\s*\)/g;

/// Punctuation people write inside a phone number: ASCII and non-breaking
/// spaces, the hyphen family, brackets, dots and slashes.
const SEPARATORS = /[ \t\u00A0\u202F()\-\u2011\u2013./]/g;

/// Repair [raw] into bare E.164, or null when it cannot be. Null covers both
/// "nothing was entered" and "this is not a reachable international number";
/// callers treat an empty field as "no number on file" before calling.
export function normaliseE164(raw: string | null | undefined): string | null {
	if (raw == null) return null;
	let value = raw.trim().replace(TRUNK_ZERO, '').replace(SEPARATORS, '');
	if (value.startsWith('00')) value = `+${value.slice(2)}`;
	return E164_PATTERN.test(value) ? value : null;
}
