// Unit tests for `lib/strava_importer.dart`'s pure date parser.
//
// `parseStravaDate` translates the date strings Strava emits in
// `activities.csv` — which mix ISO 8601 with a US-locale shape
// (`"Apr 9, 2026, 7:30:00 AM"`) — into a [DateTime]. Strava's CSV
// is the per-activity timestamp source-of-truth when the per-file
// GPX / TCX track header is missing or wrong; a regression in this
// parser would mis-attribute every import row's date.
//
// The full `StravaImporter.importFromZip` path is gated on real ZIP
// bytes + compute() isolate setup; the architecture-guard suite
// already pins it (`StravaImporter.importFromZip` must dispatch to
// `compute()` so the UI thread stays free during large imports).
// This file covers the date parser's edge cases that suite can't
// reach.

import 'package:flutter_test/flutter_test.dart';

import '../lib/strava_importer.dart';

void main() {
  group('parseStravaDate — ISO 8601 path', () {
    test('plain ISO 8601 UTC parses cleanly', () {
      // Strava sometimes emits ISO directly (older export formats /
      // some activity types). The function tries DateTime.tryParse
      // first so this is the fast path.
      final d = parseStravaDate('2026-05-19T08:00:00Z');
      expect(d, isNotNull);
      expect(d!.toUtc().toIso8601String(), '2026-05-19T08:00:00.000Z');
    });

    test('ISO with millisecond precision parses cleanly', () {
      final d = parseStravaDate('2026-05-19T08:00:00.500Z');
      expect(d, isNotNull);
      expect(d!.toUtc().toIso8601String(), '2026-05-19T08:00:00.500Z');
    });

    test('ISO with timezone offset parses cleanly', () {
      // +10:00 (Sydney) — DateTime.parse handles offsets natively.
      final d = parseStravaDate('2026-05-19T08:00:00+10:00');
      expect(d, isNotNull);
      expect(d!.toUtc().toIso8601String(), '2026-05-18T22:00:00.000Z');
    });
  });

  group('parseStravaDate — US-locale path', () {
    test('full Strava format "Apr 9, 2026, 7:30:00 AM"', () {
      // The canonical shape Strava emits in activities.csv for the
      // English / metric default user.
      final d = parseStravaDate('Apr 9, 2026, 7:30:00 AM');
      expect(d, isNotNull);
      // Strava's CSV dates have no timezone — we construct a local
      // DateTime. Pin year/month/day/hour to avoid TZ-flake.
      expect(d!.year, 2026);
      expect(d.month, 4);
      expect(d.day, 9);
      expect(d.hour, 7);
      expect(d.minute, 30);
      expect(d.second, 0);
    });

    test('PM marker shifts hour by +12', () {
      // 7:30 PM → 19:30 in 24-hour. A regression here would render
      // every afternoon run as a 7am one.
      final d = parseStravaDate('Apr 9, 2026, 7:30:00 PM');
      expect(d!.hour, 19);
    });

    test('12:00 PM (noon) stays as hour=12', () {
      // The `ampm == 'PM' && hour < 12` guard intentionally skips
      // the +12 shift when hour==12. Without this, noon would shift
      // to 24 → next day.
      final d = parseStravaDate('Apr 9, 2026, 12:00:00 PM');
      expect(d!.hour, 12);
      expect(d.day, 9, reason: 'noon must not roll to the next day');
    });

    test('12:00 AM (midnight) becomes hour=0', () {
      // `ampm == 'AM' && hour == 12` shifts to 0 (the start of the
      // day, not noon). A regression would render midnight runs at
      // noon.
      final d = parseStravaDate('Apr 9, 2026, 12:00:00 AM');
      expect(d!.hour, 0);
    });

    test('24-hour format (no AM/PM marker) parses as-is', () {
      // Strava exports for users with 24-hour locales drop the
      // AM/PM marker; the regex's `[AP]M)?` makes that optional.
      // The hour shifts must NOT fire — 19:30 stays 19:30.
      final d = parseStravaDate('Apr 9, 2026, 19:30:00');
      expect(d!.hour, 19);
      expect(d.minute, 30);
    });

    test('full month name (April) parses (3-letter prefix match)', () {
      // The regex captures `\w+` for the month then takes the
      // first 3 chars lowercased to look up. "April" → "apr" →
      // month 4. A regression that required an exact 3-char
      // length would break full-month-name exports.
      final d = parseStravaDate('April 9, 2026, 7:30:00 AM');
      expect(d, isNotNull);
      expect(d!.month, 4);
    });

    test('every month abbreviation maps to its 1-12 number', () {
      // Pin all 12 so a typo'd month table fails per-row instead
      // of all-at-once.
      const cases = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      for (final e in cases.entries) {
        final d = parseStravaDate('${e.key} 1, 2026, 7:30:00 AM');
        expect(d?.month, e.value, reason: '${e.key} → ${e.value}');
      }
    });

    test('two-digit day works (Apr 09 vs Apr 9)', () {
      // `\d{1,2}` — both single and double digit days. A regression
      // that hard-coded 1-digit would lose every double-digit day
      // (the majority of the month).
      final d1 = parseStravaDate('Apr 9, 2026, 7:30:00 AM');
      final d2 = parseStravaDate('Apr 09, 2026, 7:30:00 AM');
      expect(d1, isNotNull);
      expect(d2, isNotNull);
      expect(d1!.day, 9);
      expect(d2!.day, 9);
    });

    test('two-digit day in the upper-half (Apr 23) works', () {
      final d = parseStravaDate('Apr 23, 2026, 7:30:00 AM');
      expect(d!.day, 23);
    });

    test('case-insensitive month + AM/PM markers', () {
      // The regex has `caseSensitive: false`. Pin both lower-case
      // month and lowercase pm — Strava's exporter has shipped
      // both casings over time.
      final d = parseStravaDate('apr 9, 2026, 7:30:00 pm');
      expect(d, isNotNull);
      expect(d!.month, 4);
      expect(d.hour, 19);
    });
  });

  group('parseStravaDate — failure paths', () {
    test('unparseable garbage returns null', () {
      expect(parseStravaDate('not a date'), isNull);
      expect(parseStravaDate(''), isNull);
      expect(parseStravaDate('!!!'), isNull);
    });

    test('unknown month name returns null', () {
      // The month-table lookup falls through to null when the
      // first-3-chars-lowercased doesn't match. Defensive: a future
      // Strava locale switch shipping non-English months would
      // surface as null here, NOT a crash that drops the import.
      // (The caller falls back to the per-track-file timestamp.)
      expect(parseStravaDate('Foo 9, 2026, 7:30:00 AM'), isNull);
    });

    test('partial match (missing year) returns null', () {
      // Regex requires year + h:m:s — partial inputs must fail.
      expect(parseStravaDate('Apr 9, 7:30:00 AM'), isNull);
      expect(parseStravaDate('Apr 9, 2026'), isNull);
    });
  });
}
