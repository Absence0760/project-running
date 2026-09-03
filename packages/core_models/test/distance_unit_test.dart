import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  test('the vocabulary is exactly what the CHECK constraint holds', () {
    // The guard that enforces this on every PR is
    // `apps/web/scripts/check_constraint_unions.mjs`, which reads this enum
    // against `user_profiles_preferred_unit_check`. This case is the local
    // half: it fails here, in the package that owns the vocabulary, rather
    // than only in a web script a Dart-only change never runs.
    final sql = File(
      '../../apps/backend/supabase/migrations/'
      '20260505_001_narrow_union_check_constraints.sql',
    ).readAsStringSync();
    final m = RegExp(
      r"add constraint user_profiles_preferred_unit_check\s*"
      r"check \(preferred_unit in \(([^)]*)\)\)",
      dotAll: true,
    ).firstMatch(sql);
    expect(m, isNotNull,
        reason: 'user_profiles_preferred_unit_check is no longer declared in '
            '20260505_001 — find the migration that declares it and re-anchor '
            'this');
    final values = RegExp("'([a-z_]+)'")
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1))
        .toSet();
    expect(DistanceUnit.values.map((u) => u.name).toSet(), values);
  });

  test('a mile is the statute mile, once', () {
    expect(kMetresPerMile, 1609.344);
  });

  group('ActivityType.splitIntervalMetresFor', () {
    // Folded back onto the enum when DistanceUnit became a leaf; it was an
    // extension in `preferences.dart` only because the unit was declared
    // there. That file imports `package:flutter/material.dart`, so this suite
    // — in a package with no Flutter dependency — is what proves the fold.
    test('a split is a landmark in the runner\'s own unit', () {
      expect(ActivityType.run.splitIntervalMetresFor(DistanceUnit.km), 1000);
      expect(ActivityType.run.splitIntervalMetresFor(DistanceUnit.mi),
          kMetresPerMile);
    });

    test('cycling gets a five-unit interval, everything else one', () {
      expect(ActivityType.cycle.splitIntervalMetresFor(DistanceUnit.km), 5000);
      expect(ActivityType.cycle.splitIntervalMetresFor(DistanceUnit.mi),
          5 * kMetresPerMile);
      for (final a in ActivityType.values.where((a) => a != ActivityType.cycle)) {
        expect(a.splitIntervalMetresFor(DistanceUnit.km), 1000, reason: a.name);
      }
    });
  });
}
