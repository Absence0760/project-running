import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/date_format.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  final d = DateTime(2026, 5, 15, 9, 30); // a Friday

  group('formatDateMed', () {
    test('en is day-first with abbreviated month + year', () {
      expect(formatDateMed(d, 'en'), '15 May 2026');
    });
    test('de localises the month name', () {
      expect(formatDateMed(d, 'de'), '15 Mai 2026');
    });
    test('ja localises the month', () {
      expect(formatDateMed(d, 'ja'), contains('5月'));
      expect(formatDateMed(d, 'ja'), contains('2026'));
      expect(formatDateMed(d, 'ja'), contains('15'));
    });
  });

  group('formatDateShort', () {
    test('en day + abbreviated month, no year', () {
      expect(formatDateShort(d, 'en'), '15 May');
      expect(formatDateShort(DateTime(2026, 1, 5), 'en'), '5 Jan');
    });
    test('de localises the month', () {
      expect(formatDateShort(d, 'de'), '15 Mai');
    });
  });

  group('formatMonthName', () {
    test('en full month name', () {
      expect(formatMonthName(DateTime(2026, 1), 'en'), 'January');
      expect(formatMonthName(DateTime(2026, 6), 'en'), 'June');
      expect(formatMonthName(DateTime(2026, 12), 'en'), 'December');
    });
    test('de full month name', () {
      expect(formatMonthName(DateTime(2026, 5), 'de'), 'Mai');
    });
    test('ja full month name', () {
      expect(formatMonthName(DateTime(2026, 5), 'ja'), '5月');
    });
  });

  group('formatDow', () {
    test('en abbreviated weekday', () {
      expect(formatDow(d, 'en'), 'Fri');
    });
    test('de abbreviated weekday', () {
      expect(formatDow(d, 'de'), 'Fr');
    });
    test('ja abbreviated weekday', () {
      expect(formatDow(d, 'ja'), '金');
    });
  });

  group('formatDowNarrow', () {
    test('en single letters Monday-first', () {
      final mon = DateTime(2026, 1, 5); // Monday
      expect([for (var i = 0; i < 7; i++) formatDowNarrow(mon.add(Duration(days: i)), 'en')],
          ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    });
    test('ja narrow weekday', () {
      expect(formatDowNarrow(DateTime(2026, 1, 5), 'ja'), '月');
    });
  });

  group('formatMonthAbbr', () {
    test('en / de / ja', () {
      expect(formatMonthAbbr(d, 'en'), 'May');
      expect(formatMonthAbbr(d, 'de'), 'Mai');
      expect(formatMonthAbbr(d, 'ja'), '5月');
    });
  });

  group('formatDateTime', () {
    test('en includes date and time', () {
      final s = formatDateTime(d, 'en');
      expect(s, contains('2026'));
      expect(s, contains('9:30'));
    });
    test('ja orders year-first', () {
      expect(formatDateTime(d, 'ja'), startsWith('2026'));
    });
  });

  group('formatTime', () {
    test('en 12-hour, de 24-hour', () {
      // CLDR uses a narrow no-break space before AM/PM, so assert on the
      // pieces rather than the exact separator.
      final en = formatTime(d, 'en');
      expect(en, startsWith('9:30'));
      expect(en, endsWith('AM'));
      expect(formatTime(d, 'de'), '09:30');
    });
  });

  group('formatDowDateShort', () {
    test('en weekday + month + day', () {
      expect(formatDowDateShort(d, 'en'), 'Fri, May 15');
    });
  });

  group('formatMonthDayShort', () {
    test('en month + day', () {
      expect(formatMonthDayShort(d, 'en'), 'May 15');
    });
  });

  group('UTC instants render in local time', () {
    // Stored timestamps arrive as UTC `DateTime`s (parsed from `Z`-suffixed
    // ISO). The helpers must convert to local before formatting, else a run
    // recorded late in the evening shows the next UTC calendar day for a
    // viewer behind UTC — the "manual run saved as tomorrow" bug. We assert
    // the output equals formatting the explicitly-localized instant, which is
    // the contract regardless of the machine's zone (on a UTC CI box the two
    // coincide; on a developer box behind/ahead of UTC it would diverge if the
    // normalization were dropped).
    final utc = DateTime.utc(2026, 5, 15, 23, 30);

    test('formatDateShort matches the local-day equivalent', () {
      expect(formatDateShort(utc, 'en'), formatDateShort(utc.toLocal(), 'en'));
    });
    test('formatDateMed matches the local-day equivalent', () {
      expect(formatDateMed(utc, 'en'), formatDateMed(utc.toLocal(), 'en'));
    });
    test('formatDateTime matches the local equivalent', () {
      expect(formatDateTime(utc, 'en'), formatDateTime(utc.toLocal(), 'en'));
    });
    test('formatTime matches the local equivalent', () {
      expect(formatTime(utc, 'en'), formatTime(utc.toLocal(), 'en'));
    });
    test('formatDowDateShort matches the local equivalent', () {
      expect(
          formatDowDateShort(utc, 'en'), formatDowDateShort(utc.toLocal(), 'en'));
    });

    test('a synthetic local calendar value is untouched (no double shift)', () {
      // Month-name / weekday labels are built with the local `DateTime(...)`
      // constructor; normalization must be a no-op for them.
      final localMonth = DateTime(2026, 1, 15);
      expect(formatMonthName(localMonth, 'en'), 'January');
      expect(formatDateShort(localMonth, 'en'), '15 Jan');
    });
  });
}
