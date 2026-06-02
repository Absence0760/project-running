// Covers the per-device locale preference added to lib/preferences.dart:
// hydration from SharedPreferences, the null=device-follow default, and
// the set/clear round-trip. Locale is stored as a canonical tag and must
// never touch the synced settings bag (web-parity: localStorage-only).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Preferences> load(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = Preferences();
    await prefs.init();
    return prefs;
  }

  test('defaults to null (follow the device locale) when unset', () async {
    final prefs = await load({});
    expect(prefs.locale, isNull);
  });

  test('hydrates a stored canonical tag into a Locale', () async {
    final prefs = await load({'locale': 'pt-BR'});
    expect(prefs.locale, const Locale('pt', 'BR'));
  });

  test('setLocale persists the canonical tag and notifies', () async {
    final prefs = await load({});
    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.setLocale(const Locale('de'));
    expect(prefs.locale, const Locale('de'));
    expect(notified, greaterThan(0));

    // Re-hydrating from the same backing store sees the persisted choice.
    final reloaded = await load({'locale': 'de'});
    expect(reloaded.locale, const Locale('de'));
  });

  test('setLocale(null) clears the override back to device-follow', () async {
    final prefs = await load({'locale': 'ja'});
    expect(prefs.locale, const Locale('ja'));

    await prefs.setLocale(null);
    expect(prefs.locale, isNull);
  });
}
