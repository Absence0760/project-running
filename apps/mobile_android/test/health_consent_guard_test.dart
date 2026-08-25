import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every surface that turns the runner's age into a health inference reads the
// date through `healthUseDob` (decisions § 722). The rule is mechanical and
// the drift is silent — a new `dateOfBirth` read compiles, renders, and looks
// right, and nothing about it says it just spent the ungated child-safety
// record on an Art 9 purpose. So it is pinned here rather than remembered.
//
// This list is health-USE surfaces only. The preferences / body-metrics /
// setup-wizard screens read the column directly on purpose: they edit the age
// record itself, and gating the editor is what produced § 718's deadlock (a
// runner whose consent lapsed could neither save nor clear their own date).
// Screens reading the settings-bag mirror (`SettingsKeys.dateOfBirth`) need no
// gate either — the mirror already follows consent in both directions.
const _healthUseSurfaces = <String>[
  'lib/screens/dashboard_screen.dart',
  'lib/screens/nutrition_screen.dart',
  'lib/screens/nutrition_targets_screen.dart',
  'lib/training_service.dart',
];

void main() {
  for (final path in _healthUseSurfaces) {
    test('$path takes the age for health use through healthUseDob', () {
      // The settings-bag key is the consent-gated mirror, not the age
      // record, so its own name is not a violation of the rule.
      final source = File(path)
          .readAsStringSync()
          .replaceAll('SettingsKeys.dateOfBirth', 'SettingsKeys.<mirror>');
      expect(
        source.contains('healthUseDob'),
        isTrue,
        reason: '$path derives age for a health inference — it must go '
            'through healthUseDob',
      );
      expect(
        source.contains('dateOfBirth'),
        isFalse,
        reason: '$path reads dateOfBirth directly; the age record carries no '
            'consent term, so a health use must resolve it through '
            'healthUseDob instead',
      );
    });
  }
}
