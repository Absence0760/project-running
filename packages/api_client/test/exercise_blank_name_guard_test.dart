import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Why `createCustomExercise` may decide "blank" with `name.trim()`.
///
/// The rule it is applying is not Dart's idea of whitespace — it is
/// `namesAnExercise`, i.e. `normaliseExerciseName(name) != ''`, whose class is
/// spelled out by code point in `kExerciseWhitespace` precisely because the
/// three runtimes that persist this key disagree about whitespace past ASCII
/// (decisions § 790). This package cannot reach that function: it lives in
/// `apps/mobile_android/lib/gym_prs.dart` with the 1,488-entry frozen fold
/// table beside it, and a package cannot import an app.
///
/// It does not have to. The case fold maps code points to code points and never
/// deletes one, so `normaliseExerciseName(s)` is empty exactly when every code
/// point of `s` is in that class — the fold table is irrelevant to BLANKNESS,
/// only to grouping. So the blank test needs the class alone, and `trim()`
/// answers it if and only if Dart strips exactly that set.
///
/// That was true when the call site was written and true by coincidence: the
/// class is Unicode `White_Space` plus U+FEFF, which is Dart's `trim()`
/// verbatim, and nothing said so. Here it is measured, in both directions and
/// over every assignable code point — so widening the class (U+001C is
/// deliberately outside it, and Postgres folds it under one collation provider)
/// fails here rather than silently letting a name that folds to `''` reach the
/// server and come back as a 23514 the caller reports as "could not create".
void main() {
  const source = '../../apps/mobile_android/lib/gym_prs.dart';

  /// The code points `kExerciseWhitespace` matches, read out of its own
  /// declaration rather than restated here — a second copy would be the fourth
  /// rail this guard exists to avoid.
  Set<int> declaredClass() {
    final src = File(source).readAsStringSync();
    final at = src.indexOf('kExerciseWhitespace = RegExp(');
    if (at < 0) {
      throw StateError('$source no longer declares kExerciseWhitespace — the '
          'class moved and this guard is reading nothing');
    }
    final open = src.indexOf('[', at);
    final close = src.indexOf(']', open);
    if (close <= open) throw StateError('the character class is unclosed');
    final body = src.substring(open + 1, close);

    final escape = RegExp(r'\\\\u([0-9a-fA-F]{4})');
    final out = <int>{};
    var i = 0;
    final matches = escape.allMatches(body).toList();
    while (i < matches.length) {
      final start = int.parse(matches[i].group(1)!, radix: 16);
      final between = i + 1 < matches.length
          ? body.substring(matches[i].end, matches[i + 1].start)
          : '';
      if (between == '-') {
        final end = int.parse(matches[i + 1].group(1)!, radix: 16);
        for (var c = start; c <= end; c++) {
          out.add(c);
        }
        i += 2;
      } else {
        out.add(start);
        i += 1;
      }
    }
    return out;
  }

  final declared = declaredClass();

  test('the class was parsed, not merely matched', () {
    expect(declared, contains(0x0020), reason: 'a space is whitespace');
    expect(declared, contains(0xfeff),
        reason: 'U+FEFF is not White_Space but is invisible, so the class '
            'carries it deliberately');
    expect(declared, isNot(contains(0x001c)),
        reason: 'U+001C-U+001F are control characters the class deliberately '
            'excludes; if that changed, the identity below is what breaks');
  });

  test("Dart's trim() strips exactly the declared class", () {
    final stripped = <int>{};
    for (var cp = 0; cp <= 0x10ffff; cp++) {
      // A lone surrogate is not a character and `String.fromCharCode` yields an
      // unpaired code unit that no runtime treats as whitespace.
      if (cp >= 0xd800 && cp <= 0xdfff) continue;
      if (String.fromCharCode(cp).trim().isEmpty) stripped.add(cp);
    }
    expect(stripped.difference(declared), isEmpty,
        reason: 'trim() strips code points the exercise class does not, so a '
            'name that is NOT blank by the persisted rule is refused here');
    expect(declared.difference(stripped), isEmpty,
        reason: 'the exercise class folds code points trim() keeps, so a name '
            'that folds to an empty key passes this blank test and reaches '
            'the server, which refuses it with a 23514 the caller cannot act '
            'on. Decide blankness against the class, not against trim()');
  });

  test('createCustomExercise still decides blankness before the wire', () {
    final src = File('lib/src/api_client.dart').readAsStringSync();
    final at = src.indexOf('Future<ExerciseRow?> createCustomExercise(');
    expect(at, greaterThan(-1), reason: 'the method moved or was renamed');
    final end = src.indexOf('\n  /// ', at);
    final body = src.substring(at, end == -1 ? src.length : end);
    expect(body.contains('trimmed.isEmpty'), isTrue,
        reason: 'without the local refusal a blank name reaches the server and '
            'returns as an unexplained null; the identity above is what makes '
            'this spelling the persisted rule');
  });
}
