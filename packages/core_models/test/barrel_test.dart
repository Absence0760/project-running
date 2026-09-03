import 'dart:io';

import 'package:test/test.dart';

/// The two properties of the `core_models` barrel that nothing else fails on.
///
/// A name-COLLISION guard deliberately does not live here. The hazard is real —
/// `geolocator_apple` exports an `ActivityType` of its own, so `run_recorder`
/// carries `hide ActivityType` (decisions § 1013 / § 1014) — but it is already
/// caught, by a better instrument, and the guard that was filed for it would
/// have missed exactly that case. Measured 2026-09-03 and recorded in
/// decisions § 1043.
void main() {
  test('every library under src/ is reachable through the barrel', () {
    // A leaf added to `src/` and forgotten in the barrel is invisible until a
    // consumer imports it, and the failure then reads as "that name does not
    // exist" rather than "the barrel is missing a line". Both leaves added on
    // 2026-09-03 needed one.
    final barrel = File('lib/core_models.dart').readAsStringSync();
    final exported = RegExp(r"export 'src/([A-Za-z0-9_/.]+)';")
        .allMatches(barrel)
        .map((m) => m.group(1)!)
        .toSet();
    expect(exported, isNotEmpty,
        reason: 'the barrel exports nothing — its shape changed and this guard '
            'is checking nothing');

    final present = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceFirst('lib/src/', ''))
        .where((p) => p.endsWith('.dart'))
        // `part` files (`*.g.dart`) belong to the library that declares them.
        .where((p) => !p.endsWith('.g.dart'))
        .toSet();
    expect(present.difference(exported), isEmpty,
        reason: 'these libraries exist under src/ but no barrel line exports '
            'them, so no consumer can reach their names');
    expect(exported.difference(present), isEmpty,
        reason: 'the barrel exports a library that is not on disk');
  });

  test('the package still has no Flutter dependency', () {
    // This is the property BOTH leaf moves rest on: `activity_type.dart` and
    // `distance_unit.dart` left `preferences.dart` so that a pure parser could
    // reach a CHECK-constrained vocabulary without importing
    // `package:flutter/material.dart` (decisions § 1013 / § 1040). A
    // `dart pub add` here would compile fine and quietly end that, with the two
    // ADRs' reasoning left standing in the doc comments.
    //
    // It is also why the `IconData get icon` getter and the localized label are
    // extensions on the Flutter side rather than members of the enum.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final deps = RegExp(r'^dependencies:$(.*?)^[a-z_]+:', multiLine: true, dotAll: true)
        .firstMatch(pubspec);
    expect(deps, isNotNull, reason: 'pubspec.yaml has no dependencies block');
    expect(deps!.group(1), isNot(contains('flutter')),
        reason: 'core_models depends on Flutter again — every leaf that exists '
            'so a pure parser can reach a vocabulary has lost its reason');
  });
}
