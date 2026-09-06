/// The one place a stored date-time TEXT is turned into a value, for every
/// package and app in the tree.
///
/// `DateTime.tryParse` has two behaviours under one name. It refuses text it
/// cannot recognise as ISO 8601 — and it ROLLS OVER anything it can, through
/// the calendar, without complaint. `2026-13-45T99:99:99Z` is not an error, it
/// is 2027-02-18T04:40:39Z; `2026-06-32` is the 2nd of July; `2027-02-29` is
/// the 1st of March. `DateTime.parse` is the same function with a throw on the
/// unrecognisable half, so it rolls over identically. So an unusable column
/// does not yield "no value": it yields a confident WRONG one, which passes
/// every downstream non-null and `> 0` check the tree has and which no caller
/// can tell from a real answer. A timestamp that is wrong is worse than one
/// that is absent (decisions § 1344).
///
/// This refuses instead. Every component is range-checked against the calendar
/// it claims to be in, using the same anchored grammar `DateTime.parse` itself
/// accepts, so a string this rejects is one `tryParse` would have answered
/// WRONGLY and never one it would have answered correctly. The day bound is
/// the target month's own last day, so 29 February is accepted in a leap year
/// and refused otherwise.
///
/// Lives in `core_models` rather than beside its first caller because the
/// readers that need it sit in three trees — the mobile `OfflineSyncStore`
/// family, the services and stores beside it, and the row DTOs in this package
/// — and a copy per tree is the divergence this exists to remove
/// (decisions § 1377).
DateTime? parseIsoStrict(String text) {
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final m = _isoShape.firstMatch(text);
  // Unreachable while the pattern mirrors the SDK's: anything `tryParse`
  // answered matched it. Fail closed rather than admit an unchecked value if
  // the two ever drift.
  if (m == null) return null;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return null;
  final day = int.parse(m.group(3)!);
  if (day < 1 || day > DateTime.utc(int.parse(m.group(1)!), month + 1, 0).day) {
    return null;
  }
  if (!_within(m.group(4), 23)) return null;
  if (!_within(m.group(5), 59)) return null;
  if (!_within(m.group(6), 59)) return null;
  if (!_within(m.group(10), 23)) return null;
  if (!_within(m.group(11), 59)) return null;
  return parsed;
}

/// [parseIsoStrict] for a value read off a row map: a non-`String` or empty
/// field is absent rather than an error, which is what every row reader in the
/// tree spelled out for itself before this existed.
DateTime? parseIsoStrictValue(dynamic v) =>
    v is String && v.isNotEmpty ? parseIsoStrict(v) : null;

/// `DateTime.parse`'s own accepted shape, capturing every component so each
/// can be range-checked. Mirrors the SDK pattern exactly — a narrower one
/// would refuse text the platform accepts, which is a regression rather than a
/// hardening.
final RegExp _isoShape = RegExp(r'^([+-]\d{6}|\d{4})-?(\d\d)-?(\d\d)'
    r'(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?'
    r'( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$');

/// An absent optional component is in range; a present one must be `0..max`.
bool _within(String? raw, int max) {
  if (raw == null) return true;
  final n = int.parse(raw);
  return n >= 0 && n <= max;
}
