import 'package:flutter_test/flutter_test.dart';
import '../lib/strava_importer.dart';

void main() {
  group('parseStravaDate', () {
    test('parses an ISO 8601 string verbatim', () {
      final out = parseStravaDate('2026-04-09T07:30:00Z');
      expect(out, isNotNull);
      expect(out!.toUtc(), DateTime.utc(2026, 4, 9, 7, 30, 0));
    });

    test('parses Strava 12-hour AM format', () {
      // "Apr 9, 2026, 7:30:00 AM" — the canonical Strava export shape.
      final out = parseStravaDate('Apr 9, 2026, 7:30:00 AM');
      expect(out, isNotNull);
      expect(out!.year, 2026);
      expect(out.month, 4);
      expect(out.day, 9);
      expect(out.hour, 7);
      expect(out.minute, 30);
    });

    test('parses Strava 12-hour PM format and shifts hour by 12', () {
      // 7:30 PM = 19:30, except 12:30 PM stays at 12:30.
      final pm = parseStravaDate('Apr 9, 2026, 7:30:00 PM');
      expect(pm!.hour, 19);
      final noon = parseStravaDate('Apr 9, 2026, 12:30:00 PM');
      expect(noon!.hour, 12);
    });

    test('parses 12 AM as midnight (hour 0)', () {
      final midnight = parseStravaDate('Apr 9, 2026, 12:30:00 AM');
      expect(midnight!.hour, 0);
      expect(midnight.minute, 30);
    });

    test('is case-insensitive for the month name', () {
      // The regex passes caseSensitive: false; lowercase / uppercase /
      // title-case all resolve to the same DateTime.
      final lower = parseStravaDate('apr 9, 2026, 7:30:00 am');
      final upper = parseStravaDate('APR 9, 2026, 7:30:00 AM');
      expect(lower, equals(upper));
    });

    test('accepts the long month name (matches first 3 chars)', () {
      // "April 9, 2026, ..." — the regex captures the whole word, then
      // we slice the first 3 chars for the lookup.
      final out = parseStravaDate('April 9, 2026, 7:30:00 AM');
      expect(out, isNotNull);
      expect(out!.month, 4);
    });

    test('returns null for a string that matches neither shape', () {
      expect(parseStravaDate(''), isNull);
      expect(parseStravaDate('not a date'), isNull);
      expect(parseStravaDate('2026'), isNull);
    });

    test('returns null when the month name is unknown', () {
      // The regex would match the shape, but the month lookup fails.
      expect(parseStravaDate('Xyz 1, 2026, 1:00:00 AM'), isNull);
    });

    test('parses 24-hour input by leaving the AM/PM marker off', () {
      // Without an AM/PM token, the hour passes through unchanged.
      final out = parseStravaDate('Apr 9, 2026, 19:45:30');
      expect(out, isNotNull);
      expect(out!.hour, 19);
      expect(out.minute, 45);
      expect(out.second, 30);
    });
  });
}
