// Dart twin of web's `messages_parity.test.ts`. Reads every `app_*.arb`
// catalogue from disk and asserts each locale carries exactly the English
// template's key set, with no empty values and faithful `{placeholder}`
// sets. `runs.metadata` aside, the ARB files are the only cross-locale
// contract on mobile — this test is what stops a locale silently drifting
// a key (which would crash gen-l10n or leave a fallback-to-English hole).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pull the real message keys out of a parsed ARB map — drop `@@locale`
/// and the `@key` metadata entries.
Set<String> _messageKeys(Map<String, dynamic> arb) => arb.keys
    .where((k) => !k.startsWith('@'))
    .toSet();

/// Extract `{placeholder}` argument names from a message value so we can
/// check translations didn't drop or rename an interpolation arg.
///
/// ICU-plural aware: a real argument is `{name}` (simple interpolation) or
/// `{name, plural, ...}` (the head of a plural/select block). The literal
/// text inside `one{...}` / `other{...}` branches is NOT an argument, so we
/// only accept a `{` followed by an identifier that is immediately followed
/// by `}` or `,`. This keeps the contract on the args that actually flow in
/// (e.g. `count`) without flagging translated branch wording ("vor", "há")
/// as a spurious placeholder.
Set<String> _placeholders(String value) => RegExp(r'\{(\w+)\s*[},]')
    .allMatches(value)
    .map((m) => m.group(1)!)
    .toSet();

Map<String, dynamic> _readArb(String tag) {
  final raw = File('lib/l10n/app_$tag.arb').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// The shortest run of 3+ characters that appears twice back-to-back in [s],
/// or null when none does. "your your run" yields "your ".
String? _adjacentRepeat(String s) {
  for (var len = 3; len <= s.length ~/ 2; len++) {
    for (var i = 0; i + 2 * len <= s.length; i++) {
      if (s.substring(i, i + len) == s.substring(i + len, i + 2 * len)) {
        return s.substring(i, i + len);
      }
    }
  }
  return null;
}

void main() {
  // Every catalogue file present in lib/l10n. `pt` is the base fallback
  // gen-l10n requires for `pt_BR`; both are validated.
  const localeTags = ['en', 'de', 'fr', 'es', 'ja', 'pt', 'pt_BR'];

  final en = _readArb('en');
  final enKeys = _messageKeys(en);

  test('English template has keys', () {
    expect(enKeys, isNotEmpty);
  });

  for (final tag in localeTags) {
    group('locale $tag', () {
      final arb = _readArb(tag);
      final keys = _messageKeys(arb);

      test('declares its @@locale', () {
        expect(arb['@@locale'], isNotNull,
            reason: 'app_$tag.arb is missing the @@locale marker');
      });

      test('key set matches the English template exactly', () {
        final missing = enKeys.difference(keys);
        final extra = keys.difference(enKeys);
        expect(missing, isEmpty, reason: 'app_$tag.arb is missing keys');
        expect(extra, isEmpty, reason: 'app_$tag.arb has keys not in en');
      });

      test('no value is empty or whitespace-only', () {
        for (final key in keys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$key is not a string');
          expect((value as String).trim(), isNotEmpty,
              reason: '$key is empty in app_$tag.arb');
        }
      });

      test('placeholder sets are faithful to the English value', () {
        for (final key in enKeys) {
          if (!keys.contains(key)) continue;
          final expected = _placeholders(en[key] as String);
          final actual = _placeholders(arb[key] as String);
          expect(actual, equals(expected),
              reason: '$key placeholders differ in app_$tag.arb');
        }
      });

      // `profileNotifYourRun` is the {dist} fallback for a notification whose
      // run distance is unknown, and every template that consumes {dist}
      // already supplies the possessive ("your {dist}", "deinem {dist}",
      // "à sua {dist}", "あなたの{dist}"). A fallback that carries its own
      // therefore renders it twice — "gave kudos to your your run" — which
      // shipped in all seven locales until it was measured.
      //
      // Pinned as a derivation rather than per-locale copy: substitute the
      // fallback in and assert nothing in the result repeats back-to-back.
      // That is language-agnostic, needs no possessive vocabulary, and holds
      // for the space-free ja catalogue too.
      test('the {dist} fallback does not double the template possessive', () {
        final fallback = arb['profileNotifYourRun'] as String;
        for (final key in ['profileNotifKudos', 'profileNotifComment']) {
          final rendered = (arb[key] as String)
              .replaceAll('{name}', 'Ana')
              .replaceAll('{dist}', fallback);
          final repeat = _adjacentRepeat(rendered);
          expect(repeat, isNull,
              reason: '$key repeats "$repeat" in app_$tag.arb: $rendered');
        }
      });
    });
  }
}
