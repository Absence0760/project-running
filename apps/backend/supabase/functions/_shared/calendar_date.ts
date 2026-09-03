/// A bare `YYYY-MM-DD` calendar date, checked against the real calendar.
///
/// Shared rather than duplicated: `race-results-import` needs it because a
/// listing date it cannot parse would append the synthetic start clock to
/// garbage and 22007 the whole batch insert, and `race-listings-sync` needs it
/// because the date it writes IS the listing — a wrong one puts a race on the
/// public calendar on a day it is not held.
///
/// Deliberately narrower than a timestamptz check: this is the date half only,
/// and a value carrying its own time would produce two clocks in one literal.
export function isIsoCalendarDate(v: unknown): boolean {
  if (typeof v !== 'string') return false;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (!m) return false;
  const [year, month, day] = [m[1], m[2], m[3]].map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1) return false;
  const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= lengths[month - 1];
}
