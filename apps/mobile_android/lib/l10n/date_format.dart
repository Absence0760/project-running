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
/// `setUp`. The day-first explicit patterns (`d MMM`, `d MMM y`) preserve the
/// exact English output the app shipped before this migration while still
/// localising the month names for the other five locales.

/// Medium absolute date: `15 May 2026` (en), `15. Mai 2026`-style for other
/// locales (localised month name, day-first). Used for run titles, share
/// cards, review dates, manual-entry date chips.
String formatDateMed(DateTime dt, String tag) =>
    DateFormat('d MMM y', tag).format(dt);

/// Short absolute date without the year: `15 May` (en). Used for period
/// summaries and compact run-list rows.
String formatDateShort(DateTime dt, String tag) =>
    DateFormat('d MMM', tag).format(dt);

/// Full month name: `May` short or `January` full — this is the full form,
/// `DateFormat.MMMM`. Used for the period-summary month title.
String formatMonthName(DateTime dt, String tag) =>
    DateFormat.MMMM(tag).format(dt);

/// Abbreviated weekday: `Fri` (en). Used for calendar DOW headers and the
/// runs-list date line.
String formatDow(DateTime dt, String tag) => DateFormat.E(tag).format(dt);

/// Narrow single-letter weekday: `M`/`T`/… (en), `月` (ja). Used for the
/// compact calendar DOW header row.
String formatDowNarrow(DateTime dt, String tag) =>
    DateFormat('EEEEE', tag).format(dt);

/// Abbreviated month name: `May` (en), `Mai` (de), `5月` (ja). Used by the
/// dashboard charts' month-bucket axis labels.
String formatMonthAbbr(DateTime dt, String tag) =>
    DateFormat.MMM(tag).format(dt);

/// Date + time, locale-ordered: `5/15/2026 9:30 AM` (en). Used for the
/// public-run timestamp.
String formatDateTime(DateTime dt, String tag) =>
    DateFormat.yMd(tag).add_jm().format(dt);

/// Time-of-day only: `9:30 AM` (en), `09:30` (de). Used for the event-card
/// time line.
String formatTime(DateTime dt, String tag) => DateFormat.jm(tag).format(dt);

/// Weekday + short date with no year: `Fri, May 15` (en). Used for the
/// runs-screen date subtitle.
String formatDowDateShort(DateTime dt, String tag) =>
    DateFormat('EEE, MMM d', tag).format(dt);

/// Short month + day, month-first: `May 15` (en). Used for event date chips
/// and the runs-screen heatmap tooltip.
String formatMonthDayShort(DateTime dt, String tag) =>
    DateFormat.MMMd(tag).format(dt);
