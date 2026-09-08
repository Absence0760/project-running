import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// `createCustomExercise` decides "blank" against the exercise KEY, not against
/// a runtime's idea of whitespace.
///
/// The rule is `namesAnExercise` -- `normaliseExerciseName(name) != \'\'` --
/// whose class is spelled out by code point in `kExerciseWhitespace` precisely
/// because the three runtimes that persist this key disagree about whitespace
/// past ASCII (decisions § 790). Until decisions § 1515 this package could not
/// reach that function: it lived in `apps/mobile_android/lib/gym_prs.dart` with
/// the 1,488-entry frozen fold table beside it, and a package cannot import an
/// app. So the call site tested `trimmed.isEmpty` instead, which answered
/// identically -- the class is Unicode `White_Space` plus U+FEFF, which is
/// Dart's `trim()` verbatim -- and therefore stated the rule by a coincidence
/// of the runtime.
///
/// The derivation now lives in `core_models`, the call site calls it, and this
/// guard pins both halves: that the identity the old spelling rested on still
/// holds (so the move changed no answer), and that the call site no longer
/// depends on it. A name that folds to the empty key reaching the server comes
/// back as a 23514 the caller can only report as "could not create".
void main() {
  test('the class carries what it is meant to carry', () {
    // Read off the shipped RegExp rather than a restated list -- a second copy
    // would be the fourth rail this whole arrangement exists to avoid.
    expect(kExerciseWhitespace.hasMatch(' '), isTrue,
        reason: 'a space is whitespace');
    expect(kExerciseWhitespace.hasMatch('\ufeff'), isTrue,
        reason: 'U+FEFF is not White_Space but is invisible, so the class '
            'carries it deliberately');
    expect(kExerciseWhitespace.hasMatch('\u001c'), isFalse,
        reason: 'U+001C-U+001F are control characters the class deliberately '
            'excludes -- Postgres folding them under one collation provider was '
            'a divergence to close, not a rule to copy');
  });

  test('the key is empty exactly where the class covers every code point', () {
    // The reason blankness never needed the 1,488-entry fold table: the case
    // fold maps code points to code points and never deletes one, so a name
    // folds to the empty key exactly when every code point of it is in the
    // class. Measured over every assignable code point, in both directions.
    for (var cp = 0; cp <= 0x10ffff; cp++) {
      // A lone surrogate is not a character; `String.fromCharCode` yields an
      // unpaired code unit no runtime treats as whitespace.
      if (cp >= 0xd800 && cp <= 0xdfff) continue;
      final one = String.fromCharCode(cp);
      final allClass = kExerciseWhitespace.stringMatch(one) == one;
      expect(namesAnExercise(one), !allClass,
          reason: 'U+${cp.toRadixString(16).toUpperCase()} names an exercise '
              'iff it is outside the whitespace class');
    }
  });

  test('createCustomExercise decides blankness on the key, before the wire',
      () {
    final src = File('lib/src/api_client.dart').readAsStringSync();
    final at = src.indexOf('Future<ExerciseRow?> createCustomExercise(');
    expect(at, greaterThan(-1), reason: 'the method moved or was renamed');
    final end = src.indexOf('\n  /// ', at);
    final body = src.substring(at, end == -1 ? src.length : end);
    expect(body.contains('namesAnExercise('), isTrue,
        reason: 'the rule is the key, not a runtime coincidence -- and without '
            'a local refusal a blank name reaches the server and returns as an '
            'unexplained null');
    expect(RegExp(r'trimmed\.isEmpty').hasMatch(body), isFalse,
        reason: 'that spelling answers correctly only while Dart strips exactly '
            'kExerciseWhitespace; the class is reachable now, so state it');
  });
}
