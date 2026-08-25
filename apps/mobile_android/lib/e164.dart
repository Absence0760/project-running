/// Normalisation for the owner-stored safety-contact phone number
/// (`safety_contacts.contact_phone`, migration `20270410_001`).
///
/// Dart twin of `apps/web/src/lib/safety/e164.ts` — keep in lockstep.
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
final RegExp e164Pattern = RegExp(r'^\+[1-9][0-9]{6,14}$');

/// The parenthesised national trunk prefix, e.g. the `(0)` in
/// `+44 (0) 7700 900123`. Deleted whole — see the note above.
final RegExp _trunkZero = RegExp(r'\(\s*0\s*\)');

/// Punctuation people write inside a phone number: ASCII and non-breaking
/// spaces, the hyphen family, brackets, dots and slashes.
final RegExp _separators = RegExp(r'[ \t\u00A0\u202F()\-\u2011\u2013./]');

/// Repair [raw] into bare E.164, or null when it cannot be. Null covers both
/// "nothing was entered" and "this is not a reachable international number";
/// callers treat an empty field as "no number on file" before calling.
String? normaliseE164(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().replaceAll(_trunkZero, '').replaceAll(_separators, '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  return e164Pattern.hasMatch(value) ? value : null;
}
