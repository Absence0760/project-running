import 'package:flutter_test/flutter_test.dart';

import '../lib/locale_defaults.dart';

void main() {
  group('defaultUnitForLocale', () {
    test('mi for imperial regions, km otherwise', () {
      expect(defaultUnitForLocale('en-US'), 'mi');
      expect(defaultUnitForLocale('en-GB'), 'mi');
      expect(defaultUnitForLocale('en-LR'), 'mi');
      expect(defaultUnitForLocale('my-MM'), 'mi');
      expect(defaultUnitForLocale('de-DE'), 'km');
      expect(defaultUnitForLocale('fr-FR'), 'km');
      expect(defaultUnitForLocale('en-AU'), 'km');
      expect(defaultUnitForLocale('ja-JP'), 'km');
    });

    test('accepts POSIX underscore tags (Platform.localeName)', () {
      expect(defaultUnitForLocale('en_US'), 'mi');
      expect(defaultUnitForLocale('en_US.UTF-8'), 'mi');
      expect(defaultUnitForLocale('de_DE'), 'km');
    });

    test('defaults to km for a region-less / unparseable locale', () {
      expect(defaultUnitForLocale('en'), 'km');
      expect(defaultUnitForLocale(''), 'km');
      expect(defaultUnitForLocale('not-a-locale!!'), 'km');
    });
  });

  group('defaultWeekStartForLocale', () {
    test('sunday for US, monday for Europe', () {
      expect(defaultWeekStartForLocale('en-US'), 'sunday');
      expect(defaultWeekStartForLocale('en-CA'), 'sunday');
      expect(defaultWeekStartForLocale('de-DE'), 'monday');
      expect(defaultWeekStartForLocale('fr-FR'), 'monday');
      expect(defaultWeekStartForLocale('en-GB'), 'monday');
    });

    test('accepts POSIX underscore tags', () {
      expect(defaultWeekStartForLocale('en_US'), 'sunday');
      expect(defaultWeekStartForLocale('ja_JP'), 'sunday');
      expect(defaultWeekStartForLocale('pt_BR'), 'sunday');
      expect(defaultWeekStartForLocale('de_DE'), 'monday');
    });

    test('defaults to monday for a region-less locale', () {
      expect(defaultWeekStartForLocale('en'), 'monday');
      expect(defaultWeekStartForLocale(''), 'monday');
      expect(defaultWeekStartForLocale('fr'), 'monday');
    });
  });

  group('regionOfLocale', () {
    test('extracts the region across tag shapes', () {
      expect(regionOfLocale('en-US'), 'US');
      expect(regionOfLocale('en_us'), 'US');
      expect(regionOfLocale('zh-Hant-TW'), 'TW');
      expect(regionOfLocale('es-419'), '419');
      expect(regionOfLocale('en'), '');
      expect(regionOfLocale(''), '');
    });
  });

  test('defaultWeekStartForLocale agrees with the web twin on the CLDR set', () {
    // The hand-written 16-region table disagreed with CLDR for 19 regions, and
    // web consults Intl first while Dart cannot — so these locales seeded a
    // different week start per platform and `currentWeek` bucketed the
    // dashboard onto different seven days.
    for (final loc in [
      'pt-PT', 'th-TH', 'id-ID', 'en-SG', 'ar-SA', 'es-DO', 'es-GT', 'es-HN',
      'es-SV', 'es-NI', 'es-PA', 'es-PY', 'en-KE', 'am-ET', 'ur-PK', 'bn-BD',
    ]) {
      expect(defaultWeekStartForLocale(loc), 'sunday', reason: loc);
    }
    // Argentina is Monday-first in CLDR; the old table wrongly listed it.
    expect(defaultWeekStartForLocale('es-AR'), 'monday');
    // A Saturday-first region (firstDay 6) is modelled as monday on both sides.
    expect(defaultWeekStartForLocale('ar-EG'), 'monday');
  });
}
