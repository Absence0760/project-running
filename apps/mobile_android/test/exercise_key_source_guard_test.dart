// Source-level guard: nothing under `lib/` folds an exercise name with Dart's
// own `toLowerCase()`.
//
// The exercise grouping key has one derivation — `normaliseExerciseName`,
// which collapses the named whitespace class and lower-cases through the
// FROZEN Unicode table (decisions § 1175). `trim().toLowerCase()` is neither:
// it splits an internal whitespace run, and Dart's own case table answers a
// different letter from the frozen one at 465 of its 1,488 code points. Seven
// surfaces folded that way anyway, and the ones that were LOOKUPS wrote a key
// under one spelling and read it back under another, so the badge, the hint or
// the suggestion simply did not appear, with no failure anywhere (§ 1248).
//
// Nothing stopped an eighth being written, which is why this scan exists: the
// defect is invisible at runtime, so source is the only place it can be seen.
// The web half is `apps/web/src/lib/gym/exercise_key_source_guard.test.ts`;
// the two carry the same rule.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _libRoot = 'lib';

/// A file that names an exercise anywhere in its CODE is banned from the
/// runtime fold outright, rather than only where the receiver happens to name
/// the value it is folding.
///
/// This is the rule that gives the scan teeth, and it is anchored to what the
/// file DOES rather than to where it sits: the gym surfaces call their locals
/// `raw`, `q` and `s`, so a receiver test alone reads the composer's
/// `q.toLowerCase()` as unrelated to exercises and walks straight past it. A
/// hand-listed set of gym paths would have the same hole one rename later.
/// Prose does not count — comments and string literals are blanked first, so
/// a doc comment saying "exercise the enhance path" leaves the file unbanned,
/// which is exactly what `route_detail_screen.dart` and `shared_file_import
/// .dart` say.
final _namesAnExercise = RegExp('exercise', caseSensitive: false);

/// Dart's runtime case fold, however it is spelled. Only the LOWER half is
/// bannable file-wide: upper-casing is a presentation transform this tree uses
/// on nine section labels (`label.toUpperCase()`, `l10n.gymNotes
/// .toUpperCase()`), never to derive a key. An upper-case fold applied to
/// something the code calls an exercise is still reported, on the receiver
/// rule below — a key derived that way would be just as wrong.
final _runtimeFold = RegExp(r'\.to(?<case>Lower|Upper)Case\s*\(');

/// Modules that serve every domain, so naming an exercise somewhere says
/// nothing about what any one fold in them is folding. The file-level ban is
/// waived and each fold is judged on its own receiver instead. Empty today —
/// the list exists because the web half needs one and the two rules are meant
/// to read the same; the staleness test below keeps a dead entry out.
const List<String> _broadModules = <String>[];

/// Files that still fold an exercise name, with why the fix is not here. Empty
/// today: every Dart site the round-39 audit named, and the two it missed, are
/// closed in this change.
const Map<String, String> _pending = <String, String>{};

class _Hit {
  final String path;
  final int line;
  final String text;
  const _Hit(this.path, this.line, this.text);
  @override
  String toString() => '$path:$line  $text';
}

/// Comment bodies blanked, string literals LEFT IN PLACE, offsets preserved.
/// [blankNonCode] blanks both, and the receiver test needs the strings: the
/// value being folded is routinely reached through a quoted map index
/// (`s['exercise_name']`), and blanking that hides the only thing that names
/// it.
String _blankComments(String src) {
  final out = List<String>.from(src.split(''));
  void blank(int from, int to) {
    for (var i = from; i < to && i < out.length; i++) {
      if (out[i] != '\n') out[i] = ' ';
    }
  }

  var i = 0;
  while (i < src.length) {
    if (src.startsWith('//', i)) {
      final end = src.indexOf('\n', i);
      blank(i, end < 0 ? src.length : end);
      i = end < 0 ? src.length : end;
    } else if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      blank(i, end < 0 ? src.length : end + 2);
      i = end < 0 ? src.length : end + 2;
    } else {
      i++;
    }
  }
  return out.join();
}

final _nameChar = RegExp(r'[A-Za-z0-9_$.?!]');
final _spaceChar = RegExp(r'\s');

/// The receiver expression a fold is applied to: the member chain immediately
/// left of the `.`, with balanced call and index groups walked over so
/// `(s['exercise_name'] as String?).trim().toLowerCase()` reports the whole
/// chain rather than stopping at `.trim()`.
String _receiverOf(String code, int at) {
  var i = at - 1;
  while (i >= 0) {
    final c = code[i];
    if (_spaceChar.hasMatch(c) || _nameChar.hasMatch(c)) {
      i--;
      continue;
    }
    if (c == ')' || c == ']') {
      final open = c == ')' ? '(' : '[';
      var depth = 0;
      while (i >= 0) {
        if (code[i] == c) {
          depth++;
        } else if (code[i] == open) {
          depth--;
          if (depth == 0) {
            i--;
            break;
          }
        }
        i--;
      }
      continue;
    }
    break;
  }
  return code.substring(i + 1, at);
}

/// The statement a fold sits in — back to the nearest `;`, `,`, `{` or `}`.
/// Catches the shape the receiver alone cannot, where the value was named by
/// the declaration rather than by the chain.
///
/// The comma is load-bearing on this platform: a Flutter build method is one
/// enormous comma-separated argument list with no semicolons in it, so a walk
/// that stops only at `;` runs backwards past a dozen sibling widgets and
/// reads `_exerciseBlock(...)` four lines up as context for a section label's
/// `toUpperCase()`.
String _statementAt(String code, int at) {
  var i = at - 1;
  while (i >= 0 &&
      code[i] != ';' &&
      code[i] != ',' &&
      code[i] != '{' &&
      code[i] != '}') {
    i--;
  }
  return code.substring(i + 1, at);
}

/// Every runtime case fold in [source] this guard objects to. Takes the source
/// rather than reading it, so the mutation test can feed it a planted one.
List<_Hit> foldHits(String path, String source) {
  final code = _blankComments(source);
  final scan = blankNonCode(source);
  final fileNames =
      _namesAnExercise.hasMatch(scan) && !_broadModules.contains(path);
  final lines = source.split('\n');
  final out = <_Hit>[];
  for (final m in _runtimeFold.allMatches(scan)) {
    final at = m.start;
    final named = _namesAnExercise.hasMatch(_receiverOf(code, at)) ||
        _namesAnExercise.hasMatch(_statementAt(code, at));
    final lowering = m.namedGroup('case') == 'Lower';
    if (!(lowering && fileNames) && !named) continue;
    final line = '\n'.allMatches(code.substring(0, at)).length + 1;
    out.add(_Hit(path, line, line - 1 < lines.length ? lines[line - 1].trim() : ''));
  }
  return out;
}

List<_Hit> _scanTree() {
  final out = <_Hit>[];
  for (final f in dartFiles(_libRoot)) {
    out.addAll(foldHits(f.path, f.readAsStringSync()));
  }
  return out;
}

void main() {
  test('the guard scans a tree that is actually there', () {
    // §510: a guard whose root has moved reports nothing at all, which reads
    // as a clean sweep. Anchor on files the scan must always find.
    expect(rootExists(_libRoot), isTrue);
    final paths = dartFiles(_libRoot).map((f) => f.path).toList();
    expect(paths.length, greaterThan(200),
        reason: 'only ${paths.length} dart files under lib/ — has the tree moved?');
    expect(paths, contains('lib/gym_prs.dart'));
    expect(paths, contains('lib/screens/gym_screen.dart'));
  });

  test('no mobile surface folds an exercise name with the runtime case mapping', () {
    final offenders =
        _scanTree().where((h) => !_pending.containsKey(h.path)).toList();
    expect(
      offenders,
      isEmpty,
      reason: 'Fold an exercise name with normaliseExerciseName from '
          'gym_prs.dart, never Dart\'s own case mapping — it splits an internal '
          'whitespace run and answers a different letter from the frozen table '
          'at 465 code points:\n${offenders.join('\n')}',
    );
  });

  test('every exemption still names a real fold', () {
    for (final entry in _pending.entries) {
      final hits = foldHits(entry.key, File(entry.key).readAsStringSync());
      expect(hits, isNotEmpty,
          reason: '${entry.key} no longer folds an exercise name — delete its '
              '_pending entry so the next one cannot hide behind it.');
    }
    for (final rel in _broadModules) {
      final scan = blankNonCode(File(rel).readAsStringSync());
      expect(_namesAnExercise.hasMatch(scan), isTrue,
          reason: '$rel no longer names an exercise in code — delete its '
              '_broadModules entry.');
    }
  });

  test('the scan sees the shapes it bans, and spares the ones it must not', () {
    // Planted violations, each a shape the tree could plausibly grow. A scan is
    // the only instrument that can see this defect, so a shape it misses is a
    // shape that returns. The first two are the ones a path-anchored or a
    // receiver-anchored rule alone would each walk past.
    const caught = <String, List<String>>{
      'the file names an exercise, the fold names a neutral local': [
        'lib/widgets/picker.dart',
        'final names = exerciseNames;\n  final q = value.text.trim().toLowerCase();',
      ],
      'the file names an exercise, the fold is a bare block name': [
        'lib/screens/anything.dart',
        'final e = Exercise();\n  final k = block.name.trim().toLowerCase();',
      ],
      'the receiver names one, the file otherwise does not': [
        'lib/social.dart',
        'final k = s.exerciseName.trim().toLowerCase();',
      ],
      'the receiver names one through a quoted index': [
        'lib/social.dart',
        "final k = (s['exercise_name'] as String?)!.toLowerCase();",
      ],
      'the receiver names one across a broken chain': [
        'lib/social.dart',
        'final k = row.exerciseName\n      .trim()\n      .toLowerCase();',
      ],
      'upper-cased instead': [
        'lib/social.dart',
        'final k = s.exerciseName.toUpperCase();',
      ],
      'named by the declaration rather than the chain': [
        'lib/social.dart',
        'final exerciseKey = n.trim().toLowerCase();',
      ],
    };
    caught.forEach((label, c) {
      expect(foldHits(c[0], c[1]).length, 1, reason: 'missed: $label');
    });

    const spared = <String, List<String>>{
      'a comment describing the ban': [
        'lib/social.dart',
        '// never exerciseName.trim().toLowerCase()',
      ],
      'a doc comment using the word as a verb': [
        'lib/screens/route_detail_screen.dart',
        '/// a stub to exercise the enhance path\nfinal q = query.trim().toLowerCase();',
      ],
      'nothing names an exercise at all': [
        'lib/social.dart',
        'final q = query.trim().toLowerCase();',
      ],
      'a section label upper-cased for presentation': [
        'lib/screens/gym_records_screen.dart',
        'final e = Exercise();\n  Text(label.toUpperCase());',
      ],
    };
    spared.forEach((label, c) {
      expect(foldHits(c[0], c[1]), isEmpty, reason: 'false positive: $label');
    });
  });
}
