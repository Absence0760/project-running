// The locale tables have five homes and only four were ever held together.
//
// § 761 settled the tag rule as "web's `locale.ts`, verbatim, in all four
// places" and gave the Go worker, `auth-email`, `delete-account` and watchOS
// each a guard. The PHONE is the fifth copy — `lib/l10n/locale_support.dart`
// — and nothing reads the two rails against each other, so `pt` could point
// at European Portuguese in the browser and Brazilian on the phone with every
// suite on both platforms staying green. That is § 787's class exactly: a
// vocabulary with more than one home, where at least one home is not the
// language the other is written in, and four of those had already drifted.
//
// Every value below is READ FROM SOURCE on both sides. Nothing is
// transcribed, because a registry written down twice can disagree with
// itself (§ 604's own lesson, one level along), and anti-vacuity is enforced
// in both directions: a table that parses to nothing is the guard going
// blind, not the two rails agreeing.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/locale_support.dart';

const _webLocale = '../web/src/lib/i18n/locale.ts';

String _webSource() {
  final f = File(_webLocale);
  expect(f.existsSync(), isTrue,
      reason: '$_webLocale is gone — the web half of the locale contract '
          'moved and this guard is reading nothing. Point it at the new '
          'home rather than deleting the check.');
  return f.readAsStringSync();
}

/// The text between the bracket [marker] ends on and its match.
String _literalAfter(String source, String marker) {
  final at = source.indexOf(marker);
  expect(at, isNonNegative,
      reason: 'could not find "$marker" in $_webLocale — renamed? Update this '
          'guard rather than letting it certify agreement it never checked.');
  final open = marker[marker.length - 1];
  final close = open == '[' ? ']' : (open == '(' ? ')' : '}');
  var depth = 1;
  var i = at + marker.length;
  while (depth > 0 && i < source.length) {
    if (source[i] == open) depth++;
    if (source[i] == close) depth--;
    i++;
  }
  return source.substring(at + marker.length, i - 1);
}

/// Ordered single-quoted strings in a TS array literal.
List<String> _tsStrings(String literal) =>
    RegExp(r"'([^']+)'").allMatches(literal).map((m) => m.group(1)!).toList();

/// `key: 'value'` / `'key': 'value'` pairs of a TS object literal, in order.
Map<String, String> _tsRecord(String literal) {
  final out = <String, String>{};
  for (final m
      in RegExp(r"""(?:'([\w-]+)'|([\w-]+))\s*:\s*'([^']*)'""").allMatches(literal)) {
    out[m.group(1) ?? m.group(2)!] = m.group(3)!;
  }
  return out;
}

void main() {
  late String web;

  setUpAll(() => web = _webSource());

  group('the shipped set is one list, in one order', () {
    test('web and the phone ship the same locales, spelled the same way', () {
      final webTags = _tsStrings(_literalAfter(web, 'SUPPORTED_LOCALES = ['));
      final phoneTags = supportedLocales.map(localeToTag).toList();

      expect(webTags, isNotEmpty,
          reason: 'SUPPORTED_LOCALES parsed to nothing — the extractor broke');
      expect(phoneTags.toSet(), webTags.toSet(),
          reason: 'a catalogue that ships on one client and not the other is '
              'a reader who gets their own language in the browser and '
              'English on the phone (or the reverse)');
    });

    test('the ORDER is identical, because on the phone it decides an answer',
        () {
      // Following the device locale leaves MaterialApp.locale null and Flutter
      // resolves against supportedLocales itself, taking the first entry
      // matching on LANGUAGE alone. Web never negotiates off the order and
      // keeps it identical on purpose, so a reorder on either side is a
      // divergence even though only one side changes behaviour.
      final webTags = _tsStrings(_literalAfter(web, 'SUPPORTED_LOCALES = ['));
      expect(supportedLocales.map(localeToTag).toList(), webTags);
    });

    test('pt-PT precedes pt-BR, which is what sends a bare pt to Portugal', () {
      final tags = supportedLocales.map(localeToTag).toList();
      expect(tags.indexOf('pt-PT'), lessThan(tags.indexOf('pt-BR')),
          reason: 'reversing the pair silently routes a bare-`pt` device to '
              'Brazilian while _baseToLocale still says European — measured, '
              'and invisible to every catalogue-content test');
    });

    test('each shipped locale resolves to a catalogue of its own', () {
      final byType = <String, String>{};
      for (final locale in supportedLocales) {
        final tag = localeToTag(locale);
        final type = lookupAppLocalizations(locale).runtimeType.toString();
        expect(byType.containsKey(type), isFalse,
            reason: '$tag and ${byType[type]} both resolve to $type — one of '
                'the two catalogues is unreachable and its translation work '
                'goes nowhere');
        byType[type] = tag;
      }
      expect(byType, hasLength(supportedLocales.length));
    });
  });

  group('the endonyms are one table', () {
    test('every picker label matches web character for character', () {
      final webLabels = _tsRecord(_literalAfter(web, 'LOCALE_LABELS: Record<Locale, string> = {'));
      expect(webLabels, isNotEmpty,
          reason: 'LOCALE_LABELS parsed to nothing — the extractor broke');
      expect(localeLabels, webLabels,
          reason: 'the picker names a language in its own script; two clients '
              'naming it differently is the same defect as two catalogues');
    });
  });

  group('the tag rule is one rule', () {
    test('every exact tag web carries resolves the same way on the phone', () {
      final exact = _tsRecord(_literalAfter(web, 'EXACT: Record<string, Locale> = {'));
      expect(exact, isNotEmpty,
          reason: 'EXACT parsed to nothing — the extractor broke');
      for (final entry in exact.entries) {
        expect(isSupportedTag(entry.key), isTrue,
            reason: '${entry.key} is an exact tag on web and unknown on the '
                'phone');
        expect(
          localeToTag(negotiateLocale(null, [localeFromTag(entry.key)!])),
          entry.value,
          reason: '${entry.key} reaches ${entry.value} on web',
        );
      }
    });

    test('every base-language fallback resolves the same way on the phone', () {
      final base = _tsRecord(_literalAfter(web, 'BASE_TO_LOCALE: Record<string, Locale> = {'));
      expect(base, isNotEmpty,
          reason: 'BASE_TO_LOCALE parsed to nothing — the extractor broke');
      for (final entry in base.entries) {
        expect(
          localeToTag(negotiateLocale(null, [Locale(entry.key)])),
          entry.value,
          reason: 'a bare ${entry.key} reaches ${entry.value} on web',
        );
      }
    });

    test('the bare pt is European on both rails — the one genuine judgement',
        () {
      final base = _tsRecord(_literalAfter(web, 'BASE_TO_LOCALE: Record<string, Locale> = {'));
      expect(base['pt'], 'pt-PT',
          reason: 'CLDR gives `pt` Brazilian default content; this project '
              'points it at European because Brazil always sends the region '
              'and Portugal shares its orthography with pt-AO / pt-MZ / '
              'pt-CV, which we do not carry (§ 755). If web changed its mind, '
              'the phone has to change with it, not silently disagree.');
      expect(localeToTag(negotiateLocale(null, const [Locale('pt')])), 'pt-PT');
    });

    test('the European-orthography regions land where § 761 put them', () {
      for (final region in const ['AO', 'MZ', 'CV']) {
        expect(
          localeToTag(negotiateLocale(null, [Locale('pt', region)])),
          'pt-PT',
          reason: 'pt-$region shares Portugal\'s orthography and has nowhere '
              'else to land',
        );
      }
    });

    test('the RTL switch-point is the same set on both rails', () {
      final rtl = _tsStrings(_literalAfter(web, "RTL_BASES = new Set(["));
      expect(rtl, isNotEmpty,
          reason: 'RTL_BASES parsed to nothing — the extractor broke');
      for (final base in rtl) {
        expect(dirForLocale(Locale(base)), TextDirection.rtl,
            reason: '$base is RTL on web and LTR on the phone');
      }
      for (final locale in supportedLocales) {
        expect(rtl, isNot(contains(locale.languageCode)),
            reason: 'a shipped locale appearing in RTL_BASES means the two '
                'tables disagree about what we actually ship');
      }
    });
  });

  group('the two Portuguese catalogues are actually two', () {
    // § 755 measured `app_pt.arb` as a tenth European; § 782 closed the rest.
    // The negotiation tests above prove a pt-PT reader is SENT to the European
    // catalogue; these prove the catalogue they arrive at is European. Both
    // halves are needed — a correct resolver pointing at a Brazilian copy
    // reads identically to a broken one.
    late AppLocalizations pt;
    late AppLocalizations br;

    setUpAll(() {
      pt = lookupAppLocalizations(const Locale('pt', 'PT'));
      br = lookupAppLocalizations(const Locale('pt', 'BR'));
    });

    test('the curated European vocabulary is what a pt-PT reader gets', () {
      // Each pair is one of the substitutions § 755's corpus was derived from,
      // read off a live key rather than asserted in the abstract.
      expect(pt.authPasswordLabel, 'Palavra-passe');
      expect(br.authPasswordLabel, 'Senha');
      expect(pt.runTreadmillModeLabel, 'Modo passadeira');
      expect(br.runTreadmillModeLabel, 'Modo esteira');
      expect(pt.safetyTitle, 'Contactos de segurança');
      expect(br.safetyTitle, 'Contatos de segurança');
    });

    test('a bare pt device reads European, not Brazilian', () {
      final resolved =
          lookupAppLocalizations(negotiateLocale(null, const [Locale('pt')]));
      expect(resolved.authPasswordLabel, pt.authPasswordLabel);
      expect(resolved.authPasswordLabel, isNot(br.authPasswordLabel));
    });

    test('the two catalogues differ broadly, not on a handful of strings', () {
      // A guard on three keys would survive a catalogue re-copied from its
      // sibling with those three patched back. The § 755 / § 782 measurement
      // is a ~30% divergence across the whole file; anything near zero means
      // one catalogue has been overwritten with the other.
      final ptArb = File('lib/l10n/app_pt.arb').readAsStringSync();
      final brArb = File('lib/l10n/app_pt_BR.arb').readAsStringSync();
      final ptLines = ptArb.split('\n');
      final brLines = brArb.split('\n');
      expect(ptLines.length, brLines.length,
          reason: 'the two catalogues no longer carry the same key set');
      var differing = 0;
      for (var i = 0; i < ptLines.length; i++) {
        if (ptLines[i] != brLines[i]) differing++;
      }
      expect(differing, greaterThan(500),
          reason: 'only $differing of ${ptLines.length} lines differ between '
              'app_pt.arb and app_pt_BR.arb — European Portuguese has been '
              'flattened back into a Brazilian copy');
    });
  });
}
