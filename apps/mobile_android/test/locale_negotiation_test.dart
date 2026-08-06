// Dart twin of web's `locale.test.ts`. Covers the pure locale negotiation
// helpers in lib/l10n/locale_support.dart — the logic that decides which of
// the six catalogues a device or stored preference resolves to.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/locale_support.dart';

void main() {
  group('localeToTag / localeFromTag', () {
    test('round-trips language-only tags', () {
      expect(localeToTag(const Locale('en')), 'en');
      expect(localeFromTag('en'), const Locale('en'));
    });

    test('round-trips region tags', () {
      expect(localeToTag(const Locale('pt', 'BR')), 'pt-BR');
      expect(localeFromTag('pt-BR'), const Locale('pt', 'BR'));
    });

    test('accepts underscore separators and upper-cases the region', () {
      expect(localeFromTag('pt_br'), const Locale('pt', 'BR'));
    });

    test('returns null for null / empty', () {
      expect(localeFromTag(null), isNull);
      expect(localeFromTag('  '), isNull);
    });
  });

  group('negotiateLocale', () {
    test('falls back to English with no stored pref and no device match', () {
      expect(negotiateLocale(null, const [Locale('it')]), defaultLocale);
      expect(negotiateLocale(null, const []), defaultLocale);
    });

    test('stored canonical preference wins outright', () {
      expect(
        negotiateLocale('pt-BR', const [Locale('de')]),
        const Locale('pt', 'BR'),
      );
      expect(negotiateLocale('ja', const [Locale('en')]), const Locale('ja'));
    });

    test('a regional tag we do not carry resolves to its base language', () {
      expect(negotiateLocale('fr-CA', const []), const Locale('fr'));
      expect(negotiateLocale('de-AT', const []), const Locale('de'));
      expect(negotiateLocale('es-MX', const []), const Locale('es'));
    });

    test('device locale is used when no stored pref', () {
      expect(negotiateLocale(null, const [Locale('de')]), const Locale('de'));
    });

    test('device list is walked in priority order, exact-then-base per entry',
        () {
      // fr-CA is the top preference; we ship fr by base. It must win over the
      // lower-priority exact en, not lose to it.
      expect(
        negotiateLocale(null, const [Locale('fr', 'CA'), Locale('en')]),
        const Locale('fr'),
      );
    });

    test('unsupported stored pref falls through to the device list', () {
      expect(
        negotiateLocale('it', const [Locale('es')]),
        const Locale('es'),
      );
    });
  });

  group('dirForLocale', () {
    test('every shipped locale is left-to-right', () {
      for (final locale in supportedLocales) {
        expect(dirForLocale(locale), TextDirection.ltr);
      }
    });

    test('an RTL base flips direction (switch-point for future catalogues)',
        () {
      expect(dirForLocale(const Locale('ar')), TextDirection.rtl);
      expect(dirForLocale(const Locale('he')), TextDirection.rtl);
    });
  });

  group('isSupportedTag', () {
    test('recognises the seven canonical tags case-insensitively', () {
      expect(isSupportedTag('en'), isTrue);
      expect(isSupportedTag('PT-BR'), isTrue);
      expect(isSupportedTag('pt'), isTrue);
      expect(isSupportedTag('it'), isFalse);
      expect(isSupportedTag(null), isFalse);
    });
  });

  // `app_pt.arb` shipped 3478 European-Portuguese strings, 247 of which
  // genuinely differ from the Brazilian catalogue, and NONE of them could be
  // reached: `pt` was absent from `supportedLocales` and `_baseToLocale`
  // mapped the base onto `pt-BR`, so `negotiate('pt-PT')` measured `pt-BR`.
  // Every case below is one of the measurements taken when closing that.
  group('Portuguese ships as two reachable catalogues', () {
    test('pt-PT reaches the European catalogue, not the Brazilian one', () {
      expect(
        negotiateLocale(null, const [Locale('pt', 'PT')]),
        const Locale('pt'),
      );
    });

    test('a bare pt reaches the European catalogue', () {
      expect(negotiateLocale(null, const [Locale('pt')]), const Locale('pt'));
    });

    test('pt-BR still matches Brazil exactly', () {
      expect(
        negotiateLocale(null, const [Locale('pt', 'BR')]),
        const Locale('pt', 'BR'),
      );
    });

    test('pt-AO reaches European Portuguese (Angola uses that orthography)',
        () {
      expect(
        negotiateLocale(null, const [Locale('pt', 'AO')]),
        const Locale('pt'),
      );
    });

    test('both variants are offered, and each has a picker endonym', () {
      expect(supportedLocales, contains(const Locale('pt')));
      expect(supportedLocales, contains(const Locale('pt', 'BR')));
      // A locale the picker cannot name is a blank row, so the label table is
      // part of shipping a locale, not decoration.
      for (final locale in supportedLocales) {
        final label = localeLabels[localeToTag(locale)];
        expect(label, isNotNull, reason: 'no endonym for $locale');
        expect(label, isNotEmpty);
      }
      expect(localeLabels.length, supportedLocales.length);
    });
  });
}
