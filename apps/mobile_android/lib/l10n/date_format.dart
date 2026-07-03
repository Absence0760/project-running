import 'package:intl/intl.dart';

/// Locale-aware date formatting, centralising what used to be a dozen
/// hand-rolled English month/day arrays scattered across the screens. Every
/// helper takes an explicit BCP-47 locale [tag] so it stays pure and
/// unit-testable; call sites pass `Localizations.localeOf(context)` (turned
/// into a tag) where a `BuildContext` is in scope, and `activeLocaleTag`
/// (from `locale_support.dart`) where it isn't.
///
/// `intl`'s [DateFormat] needs `initializeDateFormatting()` to have run once
/// for non-`en` locales — `main.dart` does that at startup, tests do it in
/// `setUp`. Every helper uses CLDR skeletons (`yMMMd`, `MMMd`, `MMMEd`, …)
/// rather than explicit patterns, so field order follows each locale's own
/// convention: month-first for `en` (US), day-first for de/fr/es/pt,
/// year-first for ja.

/// Renders an instant in the device's local time zone before formatting.
///
/// Stored timestamps (`runs.started_at`, comment / review `created_at`, event
/// starts, coach-message stamps) reach these helpers as UTC `DateTime`s — they
/// come from `DateTime.parse` of a `Z`-suffixed ISO string. `DateFormat`
/// renders a `DateTime`'s raw wall-clock fields without any zone conversion,
/// so formatting a UTC instant directly shows the *UTC* calendar day, which
/// rolls a day early/late for a viewer behind/ahead of UTC (the "manual run
/// saved as tomorrow" report). Normalising here fixes every call site at once.
///
/// Synthetic calendar values — month-name and weekday labels built with the
/// local `DateTime(...)` constructor (`isUtc == false`) — pass through
/// untouched, and a caller that already did `.toLocal()` likewise hands in a
/// local value, so there is never a double conversion.
DateTime _local(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

/// Medium absolute date, locale-ordered: `May 15, 2026` (en), `15. Mai 2026`
/// (de), `2026年5月15日` (ja). Used for run titles, share cards, review
/// dates, manual-entry date chips.
String formatDateMed(DateTime dt, String tag) =>
    DateFormat.yMMMd(tag).format(_local(dt));

/// Short absolute date without the year, locale-ordered: `May 15` (en),
/// `15. Mai` (de), `5月15日` (ja). Used for period summaries, compact
/// run-list rows, event date chips, and chart axis endpoints.
String formatDateShort(DateTime dt, String tag) =>
    DateFormat.MMMd(tag).format(_local(dt));

/// Full month name: `May` short or `January` full — this is the full form,
/// `DateFormat.MMMM`. Used for the period-summary month title.
String formatMonthName(DateTime dt, String tag) =>
    DateFormat.MMMM(tag).format(_local(dt));

/// Abbreviated weekday: `Fri` (en). Used for calendar DOW headers and the
/// runs-list date line.
String formatDow(DateTime dt, String tag) => DateFormat.E(tag).format(_local(dt));

/// Narrow single-letter weekday: `M`/`T`/… (en), `月` (ja). Used for the
/// compact calendar DOW header row.
String formatDowNarrow(DateTime dt, String tag) =>
    DateFormat('EEEEE', tag).format(_local(dt));

/// Abbreviated month name: `May` (en), `Mai` (de), `5月` (ja). Used by the
/// dashboard charts' month-bucket axis labels.
String formatMonthAbbr(DateTime dt, String tag) =>
    DateFormat.MMM(tag).format(_local(dt));

/// Date + time, locale-ordered: `5/15/2026 9:30 AM` (en). Used for the
/// public-run timestamp.
String formatDateTime(DateTime dt, String tag) =>
    DateFormat.yMd(tag).add_jm().format(_local(dt));

/// Time-of-day only: `9:30 AM` (en), `09:30` (de). Used for the event-card
/// time line.
String formatTime(DateTime dt, String tag) => DateFormat.jm(tag).format(_local(dt));

/// Weekday + short date with no year, locale-ordered: `Fri, May 15` (en),
/// `Fr., 15. Mai` (de), `5月15日(金)` (ja). Used for the runs-screen date
/// subtitle.
String formatDowDateShort(DateTime dt, String tag) =>
    DateFormat.MMMEd(tag).format(_local(dt));
