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

/// Extract `{placeholder}` token names from a message value so we can check
/// translations didn't drop or rename an interpolation arg.
Set<String> _placeholders(String value) => RegExp(r'\{(\w+)')
    .allMatches(value)
    .map((m) => m.group(1)!)
    .toSet();

Map<String, dynamic> _readArb(String tag) {
  final raw = File('lib/l10n/app_$tag.arb').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
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
    });
  }
}
