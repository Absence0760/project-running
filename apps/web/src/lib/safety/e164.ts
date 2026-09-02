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
///
/// The bracket set here MUST match the bracket set in `SEPARATORS`. A bracket
/// the separator class folds but this one does not turn `+44（0）7700900123`
/// into `+4407700900123` — a different, CONFORMING number — which is the exact
/// silent misdelivery the whole-deletion exists to prevent.
const TRUNK_ZERO = /[(\uFF08]\s*0\s*[)\uFF09]/g;

/// Punctuation people write inside a phone number, spelled out by code point
/// rather than left to `\s` or a `Dash_Punctuation` property, so both rails
/// fold exactly the same set (the convention `gym_prs`'s whitespace class
/// records).
///
/// The hyphen family is the reason: this used to carry three of its members
/// (U+002D, U+2011, U+2013) under a comment claiming the family, and the test
/// pinning it exercised two. A macOS or Word autocorrect turns a typed hyphen
/// into an EN DASH — folded — or an EM DASH, which was not, so the same
/// contact card pasted twice could be accepted once and refused once. A
/// number typed on a CJK keyboard carries U+FF0D, a spreadsheet export
/// U+2212. All eleven are folded now.
///
/// The space family runs U+2000..U+200D as one range, which also takes the
/// zero-width space, non-joiner and joiner: invisible characters a paste from
/// a web page carries and no reader can see to delete. U+00AD (soft hyphen)
/// and U+FEFF are the other two invisibles that survive a copy.
///
/// A separator that is NOT here is refused rather than guessed at, which is
/// the safe direction — the owner sees an error and retypes.
const SEPARATORS =
	/[ \t\u00A0\u00AD\u2000-\u200D\u202F\u205F\u3000\uFEFF\-\u2010-\u2015\u2212\uFE58\uFE63\uFF0D()\uFF08\uFF09./]/g;

/// Repair [raw] into bare E.164, or null when it cannot be. Null covers both
/// "nothing was entered" and "this is not a reachable international number";
/// callers treat an empty field as "no number on file" before calling.
export function normaliseE164(raw: string | null | undefined): string | null {
	if (raw == null) return null;
	let value = raw.trim().replace(TRUNK_ZERO, '').replace(SEPARATORS, '');
	if (value.startsWith('00')) value = `+${value.slice(2)}`;
	return E164_PATTERN.test(value) ? value : null;
}
