// `instance_start` reaches the wire through one helper on the phone too.
//
// decisions § 1343 made `instanceStartKey` the single serialiser for the
// recurring-occurrence KEY and enforced it — in `api_client` only, where the
// six offending sites were. The rest of the tree was measured correct and left
// alone, which is a fact about that day rather than a property of the code:
// `race_controller.dart` still wrote four of its sites with a bare
// `toIso8601String()`, safe purely because every input to them happened to be
// UTC by construction, and nothing said so or would notice if it stopped being
// true (decisions § 1378).
//
// A bare `toIso8601String()` writes NO zone designator for a local `DateTime`,
// Postgres resolves a zone-less literal in the session's own TimeZone, and
// `expandInstances` mints exactly such a local instant for a legacy event
// declaring no timezone. So the failure is silent and asymmetric: the row is
// written under a key no other reader computes, and the RSVP, the attendee
// list and the race arm-state simply do not find each other.
//
// Anchored on both halves. The line-level rule catches a NEW site written the
// old way; the count floor catches the old way returning by deleting the
// helper's callers, which the line rule alone would read as an empty tree.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

/// The column, as it is spelled in a string literal, an `…Row.col…` constant
/// and a Dart identifier.
final _mentionsInstance = RegExp(r'instance_start|[iI]nstance[sS]tart');

void main() {
  test('no lib site serialises an instance_start with a bare toIso8601String',
      () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    final offenders = <String>[];
    for (final file in dartFiles(_root)) {
      final raw = file.readAsStringSync();
      // The CALL has to be real code — a doc comment naming the method is not
      // a use of it — while the COLUMN is a string literal, which `blankNonCode`
      // erases. So the two halves are read from different renderings of the
      // same line, deliberately.
      final codeLines = blankNonCode(raw).split('\n');
      final rawLines = raw.split('\n');
      for (var i = 0; i < codeLines.length; i++) {
        if (!codeLines[i].contains('toIso8601String()')) continue;
        final window = '${i > 0 ? rawLines[i - 1] : ''}\n${rawLines[i]}';
        if (!_mentionsInstance.hasMatch(window)) continue;
        offenders.add('${file.path}:${i + 1}: ${rawLines[i].trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'send instance_start through instanceStartKey — a bare '
            'toIso8601String writes no zone designator for a local DateTime '
            'and Postgres re-anchors it (decisions § 1343 / § 1378):\n'
            '${offenders.join('\n')}');
  });

  test('the helper is still what those sites call', () {
    // Twenty-three when § 1378 landed — eighteen in `social_service.dart`,
    // five in `race_controller.dart`. Anchored on the COUNT so removing the
    // normalisation cannot remove the expectation with it: a tree that stopped
    // calling the helper satisfies the rule above vacuously.
    var sites = 0;
    for (final file in dartFiles(_root)) {
      sites += 'instanceStartKey('
          .allMatches(blankNonCode(file.readAsStringSync()))
          .length;
    }
    expect(sites, greaterThanOrEqualTo(23),
        reason: 'the instance_start writers have moved, been renamed, or gone '
            'back to serialising the value themselves');
  });

  test('the helper the phone calls is the one api_client declares', () {
    // Both trees must normalise identically or the phone and the web write two
    // keys again; the declaration is pinned in `api_client`'s own suite, and
    // this asserts the phone reaches THAT one rather than a local copy of the
    // name.
    final api =
        File('../../packages/api_client/lib/src/api_client.dart').readAsStringSync();
    expect(
        api.contains('String instanceStartKey(DateTime at) => '
            'at.toUtc().toIso8601String();'),
        isTrue,
        reason: 'the .toUtc() IS the fix; a helper without it is a rename');
    for (final path in ['lib/social_service.dart', 'lib/race_controller.dart']) {
      final src = File(path).readAsStringSync();
      expect(src.contains("import 'package:api_client/api_client.dart';"), isTrue,
          reason: '$path calls instanceStartKey; it must be api_client\'s');
      expect(src.contains('String instanceStartKey('), isFalse,
          reason: '$path must not declare its own copy of the helper');
    }
  });
}
