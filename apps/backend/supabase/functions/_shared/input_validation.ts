/// Shape checks for caller-supplied scalars that are about to be handed
/// to PostgREST as a typed column value.
///
/// PostgREST does not validate; it casts. A body key that reaches
/// `.eq('id', x)` on a `uuid` column raises Postgres `22P02
/// invalid_input_syntax`, and a `timestamptz` column raises `22007
/// invalid_datetime_format` — both surface as a 500 (or a misleading
/// 404, when the caller collapses `error || !row`), page Sentry, and on
/// the anon-reachable functions burn a rate-limit slot on the way. None
/// of that is the caller's fault to diagnose: a malformed input is a
/// 400.
///
/// Keep this file pure — no `Deno.env`, no `serve`, no network — so a
/// `deno test` over it runs in milliseconds.

/// RFC 4122 v1-v5 UUID shape (8-4-4-4-12 hex).
export function isValidUuid(s: unknown): boolean {
  if (typeof s !== 'string') return false;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

const TIMESTAMPTZ_RE =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(?:[Zz]|([+-])(\d{2})(?::?(\d{2}))?)?$/;

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    return leap ? 29 : 28;
  }
  return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}

/// ISO-8601 date-time, the shape every client here produces
/// (`Date.prototype.toISOString`, Dart's `toIso8601String`, or a value
/// read back from PostgREST). Seconds and the UTC offset are both
/// optional because Postgres accepts them that way — a naive literal
/// resolves against the server's `TimeZone`, which is UTC on Supabase.
///
/// `Date.parse` is deliberately NOT the gate, in either direction. It
/// is too loose at the top — it accepts the JS `toString()` form ("Sat
/// Jan 01 2026 00:00:00 GMT+0000 (Coordinated Universal Time)") that
/// Postgres rejects — and too loose at the bottom, because V8 rolls a
/// day-of-month overflow forward instead of failing, so `2026-02-30`
/// parses fine here and 22007s on the wire. Every component is
/// therefore range-checked against the calendar directly.
export function isValidTimestamptz(s: unknown): boolean {
  if (typeof s !== 'string' || s.length > 40) return false;
  const m = TIMESTAMPTZ_RE.exec(s);
  if (!m) return false;

  const [year, month, day, hour, minute] = [m[1], m[2], m[3], m[4], m[5]].map(Number);
  const second = m[6] === undefined ? 0 : Number(m[6]);
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > daysInMonth(year, month)) return false;
  // 24:00:00 is a legal end-of-day literal, which Postgres also takes;
  // 24:00:01 is not. `:60` is the leap second.
  if (hour > 24 || (hour === 24 && (minute > 0 || second > 0))) return false;
  if (minute > 59 || second > 60) return false;

  if (m[8] !== undefined) {
    // Postgres tops out at ±15:59.
    const offsetHour = Number(m[8]);
    const offsetMinute = m[9] === undefined ? 0 : Number(m[9]);
    if (offsetHour > 15 || offsetMinute > 59) return false;
  }
  return true;
}
