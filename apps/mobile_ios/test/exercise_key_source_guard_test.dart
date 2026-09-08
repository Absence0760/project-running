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

/// The trees this scan covers.
///
/// `lib/` alone stopped being the whole answer when the key derivation moved
/// into `core_models` so `api_client` could reach it (decisions § 1515): the
/// two packages hold the derivation itself and its one non-app caller, and a
/// scan that cannot see them is a scan that stopped covering the file the rule
/// is ABOUT. The paths are relative because `flutter test` runs from the app
/// directory; `rootExists` fails loudly if one moves, which is § 510's rule.
const List<String> _roots = <String>[
  'lib',
  '../../packages/core_models/lib',
  '../../packages/api_client/lib',
];

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
/// waived and each fold is judged on its own receiver instead.
///
/// `api_client.dart` is the archetype the web half's list was written for: one
/// 6,600-line typed client covering every table, so the exercise reads in it
/// say nothing about the people-search handle fold or the club-name emptiness
/// test three thousand lines away. Its exercise-name sites are judged on their
/// receivers like everyone else's — which is what caught `upsertGymRoutine`
/// deciding blankness with `trim()` the moment the scan reached this tree
/// (decisions § 1515).
const List<String> _broadModules = <String>[
  '../../packages/api_client/lib/src/api_client.dart',
];

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


/// An equality comparison, and only that: `>=` / `<=` / `=>` / `??=` and every
/// compound assignment are excluded by the surrounding character tests rather
/// than by listing them.
final _comparison = RegExp(r'(?<![<>=!])(?:==|!=)(?!=)');

/// The operand to the RIGHT of an operator at [at]: whitespace skipped, then a
/// primary expression — identifier/member chain with balanced call and index
/// groups walked over, and a quoted literal read whole. The mirror of
/// [_receiverOf], which reads the left.
String _operandAfter(String code, int at) {
  var i = at;
  while (i < code.length && _spaceChar.hasMatch(code[i])) {
    i++;
  }
  final start = i;
  if (i < code.length && (code[i] == "'" || code[i] == '"')) {
    final q = code[i];
    i++;
    while (i < code.length && code[i] != q) {
      i += code[i] == r'\' ? 2 : 1;
    }
    return code.substring(start, i + 1 > code.length ? code.length : i + 1);
  }
  while (i < code.length) {
    final c = code[i];
    if (_nameChar.hasMatch(c)) {
      i++;
      continue;
    }
    if (c == '(' || c == '[') {
      final close = c == '(' ? ')' : ']';
      var depth = 0;
      while (i < code.length) {
        if (code[i] == c) {
          depth++;
        } else if (code[i] == close) {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        i++;
      }
      continue;
    }
    break;
  }
  return code.substring(start, i);
}

/// An operand naming the free-text DISPLAY spelling of an exercise.
/// Deliberately narrower than [_namesAnExercise]: `exerciseId` and
/// `exerciseCount` are compared legitimately all over the tree, and only the
/// NAME is the value with two spellings.
final _namesASpelling = RegExp('exercise[_]?names?', caseSensitive: false);

/// A literal the other side of a comparison, which makes it a blankness or
/// sentinel test rather than an identity test between two spellings.
bool _isLiteral(String operand) {
  final t = operand.trim();
  if (t.isEmpty) return false;
  if (t.startsWith("'") || t.startsWith('"')) return true;
  return RegExp(r'^(null|true|false|-?\d)').hasMatch(t);
}

/// Every raw comparison of an exercise spelling in [source]. The Dart half of
/// the web scan of the same name, and it exists because the tree grew the shape
/// once already: `gym_detail_screen.dart` opened a new block on `last.name !=
/// s.exerciseName`, the display spelling, so one lift logged under two
/// spellings rendered as two blocks beside a header stat that counts one
/// (decisions 1322). Nothing on this rail could see that; the web half could
/// see its own, which is exactly the asymmetry a twinned invariant must not
/// have.
///
/// Each operand is judged on its DECLARATION as well as on itself, which is
/// what the first port of this scan lacked and what let the shape survive twice
/// rather than once: `gym_compose_sheet.dart` grouped on `last.name.text ==
/// name`, three lines under `final name = (s['exercise_name'] as String?) ??
/// ''`, and neither operand says "exercise" where the comparison is written.
/// The web half's own hole is the same one, closed in the same change.
///
/// Exported so the mutation test below can feed it planted violations, as
/// [foldHits] is.
List<_Hit> rawNameComparisonHits(String path, String source) {
  final code = _blankComments(source);
  final scan = blankNonCode(source);
  if (_broadModules.contains(path)) return const [];
  final lines = source.split('\n');
  final out = <_Hit>[];
  for (final m in _comparison.allMatches(scan)) {
    final at = m.start;
    final left = _originOf(code, _receiverOf(code, at));
    final right = _originOf(code, _operandAfter(code, at + m[0]!.length));
    // A folded operand is the fix, not the defect. Either side carrying the
    // canonical derivation means the comparison is already on the key.
    if (_folded.hasMatch(left) || _folded.hasMatch(right)) continue;
    if (!_namesASpelling.hasMatch(left) && !_namesASpelling.hasMatch(right)) {
      continue;
    }
    if (_isLiteral(left) || _isLiteral(right)) continue;
    final line = '\n'.allMatches(code.substring(0, at)).length + 1;
    out.add(
        _Hit(path, line, line - 1 < lines.length ? lines[line - 1].trim() : ''));
  }
  return out;
}

/// The canonical derivation, on either side of a comparison or in the
/// declaration a blankness test's subject came from.
final _folded = RegExp(r'normaliseExerciseName\s*\(|namesAnExercise\s*\(');

/// A field carrying the free-text DISPLAY spelling under a name that does not
/// say "exercise". Judged only inside a file that names one, the same
/// file-level rule that gives [foldHits] its teeth: the editors call their
/// blocks `ex` and `e`, so `ex.name` says nothing to a receiver test on its own
/// while saying everything inside `gym_compose_sheet.dart`.
final _namesADisplayField = RegExp(r'\.name\b');

/// A value whose OWN identifier is the display spelling, judged under the same
/// file-level rule. The scan trusted a `.name` READ and not a value called
/// `name`, which is the difference between a spelling taken off a row and one
/// TYPED by the user — and the typed one is the whole reason the catalogue
/// picker's create path exists. There the value reaches the test through a
/// getter over a `TextEditingController`, whose text carries no `.name` and no
/// "exercise", so no amount of chasing the declaration can reach it: the
/// evidence is the identifier the call site binds, exactly as on the web rail
/// (decisions § 1483).
///
/// Anchored at the START so `named`, whose `isEmpty` two lines under a `where`
/// that already filtered on the key is a count of blocks rather than a blank
/// name, is not swept in. Unlike the `.name` read it sits beside, this is
/// judged on the length shape too.
final _isANameIdentifier = RegExp(r'^name\b');

final _emptyLiteral = RegExp(r"""^(?:''|"")$""");

final _lengthTail = RegExp(r'\.length\s*$');

/// Dart's own spelling of the question, which the web half has no analogue for.
final _emptinessGetter = RegExp(r'\.is(?:Not)?Empty\b');

final _bareIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// The operand to the LEFT of an operator, a quoted literal included.
/// [_receiverOf] walks a member chain and stops dead at a quote, so `'' == name`
/// reads as no left operand at all — and the emptiness scan has to see the
/// literal whichever side it is written on.
String _leftOperand(String code, int at) {
  final chain = _receiverOf(code, at);
  if (chain.trim().isNotEmpty) return chain;
  var i = at - 1;
  while (i >= 0 && _spaceChar.hasMatch(code[i])) {
    i--;
  }
  if (i < 0) return chain;
  final q = code[i];
  if (q != "'" && q != '"') return chain;
  var j = i - 1;
  while (j >= 0 && code[j] != q) {
    j--;
  }
  return code.substring(j < 0 ? 0 : j, i + 1);
}

/// The value a comparison is testing for emptiness, or null if it is not an
/// emptiness test at all, paired with whether the subject may be judged on its
/// DECLARATION as well as on the operand itself.
///
/// `x == ''` and `x.length == 0` are the same question asked of a string, but
/// only the first says the subject is one. A list is emptied the same way, and
/// `named.length == 0` two lines under a `where` that filtered on a name is a
/// count of blocks, not a blank name — so the length shape is judged on the
/// operand alone, where the spelling has to be named outright.
({String subject, bool chase})? _emptinessSubject(String left, String right) {
  if (_emptyLiteral.hasMatch(right.trim())) {
    return (subject: left, chase: true);
  }
  if (_emptyLiteral.hasMatch(left.trim())) {
    return (subject: right, chase: true);
  }
  if (right.trim() == '0' && _lengthTail.hasMatch(left)) {
    return (subject: left.replaceAll(_lengthTail, ''), chase: false);
  }
  if (left.trim() == '0' && _lengthTail.hasMatch(right)) {
    return (subject: right.replaceAll(_lengthTail, ''), chase: false);
  }
  return null;
}

/// The right-hand side of a bare identifier's declaration, chased up to a few
/// hops so a value named by a `final` two lines up is still judged on where it
/// came from.
///
/// [foldHits] reaches that shape with [_statementAt], and a blankness test
/// cannot: `if (name.isEmpty)` names nothing in its own statement, and the
/// whole defect is that the declaration one line up read `ex.name.text.trim()`.
/// The chase stops at the first expression that is not a bare identifier, so a
/// value that arrives as a widget field or a getter is out of its reach.
String _originOf(String code, String operand) {
  var expr = operand.trim();
  final seen = <String>{};
  for (var hop = 0; hop < 4; hop++) {
    if (!_bareIdentifier.hasMatch(expr) || seen.contains(expr)) break;
    seen.add(expr);
    final m =
        RegExp(r'\b(?:final|const|var)\s+(?:[\w$<>?,]+\s+)?' + expr + r'\s*=([^;\n]*)')
            .firstMatch(code);
    if (m == null) break;
    expr = m[1]!.trim();
  }
  return expr;
}

/// Every blankness test in [source] taken on an exercise SPELLING rather than
/// on its key.
///
/// The third shape, and the one the other two scans exclude by construction.
/// [rawNameComparisonHits] deliberately spares a comparison against a literal —
/// that is what separates an identity test from a sentinel test — and there is
/// no case fold in `name.trim().isEmpty` for [foldHits] to see.
///
/// This rail answers the same as the key today, because Dart's `trim()` strips
/// exactly the folded class. That is a property of the runtime, not of the
/// code, and it is the one the class was spelled out to stop depending on: the
/// web twin's `trim()` leaves U+0085 in place, and its identical guards saved a
/// set whose server-stamped `exercise_key` is `''` (decisions 1367). The scan
/// is here so the two rails cannot drift apart again in silence.
List<_Hit> blankSpellingTestHits(String path, String source) {
  final code = _blankComments(source);
  final scan = blankNonCode(source);
  final fileNames =
      _namesAnExercise.hasMatch(scan) && !_broadModules.contains(path);
  final lines = source.split('\n');
  final found = <int, ({String subject, bool chase})>{};
  for (final m in _comparison.allMatches(scan)) {
    final s = _emptinessSubject(
        _leftOperand(code, m.start), _operandAfter(code, m.start + m[0]!.length));
    if (s != null) found[m.start] = s;
  }
  // `.isEmpty` is how this language asks the question, and it is a member read
  // rather than a comparison — so the port needs a second pattern the web half
  // has no analogue for. Judged on the receiver plus the declaration chase,
  // exactly as the `== ''` shape is.
  for (final m in _emptinessGetter.allMatches(scan)) {
    found[m.start] = (subject: _receiverOf(code, m.start), chase: true);
  }
  final out = <_Hit>[];
  for (final at in found.keys.toList()..sort()) {
    final f = found[at]!;
    final origin = f.chase ? _originOf(code, f.subject) : f.subject;
    // The fix itself, on either the operand or its declaration.
    if (_folded.hasMatch(origin)) continue;
    final spelling = _namesASpelling.hasMatch(origin) ||
        (fileNames && _isANameIdentifier.hasMatch(f.subject.trim())) ||
        (f.chase && fileNames && _namesADisplayField.hasMatch(origin));
    if (!spelling) continue;
    final line = '\n'.allMatches(code.substring(0, at)).length + 1;
    out.add(
        _Hit(path, line, line - 1 < lines.length ? lines[line - 1].trim() : ''));
  }
  return out;
}

List<_Hit> _scanTree(List<_Hit> Function(String, String) scan) {
  final out = <_Hit>[];
  for (final root in _roots) {
    for (final f in dartFiles(root)) {
      out.addAll(scan(f.path, f.readAsStringSync()));
    }
  }
  return out;
}

void main() {
  test('the guard scans a tree that is actually there', () {
    // §510: a guard whose root has moved reports nothing at all, which reads
    // as a clean sweep. Anchor on files the scan must always find.
    for (final root in _roots) {
      expect(rootExists(root), isTrue, reason: '$root has moved');
    }
    final paths = [
      for (final root in _roots) ...dartFiles(root).map((f) => f.path),
    ];
    expect(paths.length, greaterThan(200),
        reason: 'only ${paths.length} dart files scanned — has the tree moved?');
    expect(paths, contains('lib/gym_prs.dart'));
    expect(paths, contains('lib/screens/gym_screen.dart'));
    // The derivation itself and its one non-app caller. Both were outside this
    // scan for as long as the relocation took to land.
    expect(paths, contains('../../packages/core_models/lib/src/exercise_key.dart'));
    expect(paths, contains('../../packages/api_client/lib/src/api_client.dart'));
  });

  test('no mobile surface folds an exercise name with the runtime case mapping', () {
    final offenders =
        _scanTree(foldHits).where((h) => !_pending.containsKey(h.path)).toList();
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

  test('no mobile surface compares two exercise spellings raw', () {
    final offenders = _scanTree(rawNameComparisonHits);
    expect(
      offenders,
      isEmpty,
      reason: 'Compare exercise spellings through sameExerciseName / '
          'normaliseExerciseName from gym_prs.dart, never with ==. Adjacency '
          'measured on the display spelling renders one lift as two blocks '
          'beside a header stat that counts one (decisions 1322):'
          '\n${offenders.join('\n')}',
    );
  });

  test('the raw-comparison scan sees the shapes it bans, and spares the ones it must not',
      () {
    const caught = <String, List<String>>{
      'the block-grouping shape the detail screen had': [
        'lib/screens/gym_detail_screen.dart',
        'if (last != null && last.name != s.exerciseName) blocks.add(b);',
      ],
      'the same shape reversed': [
        'lib/widgets/gym_compose_sheet.dart',
        'if (s.exerciseName == last.name) last.sets.add(s);',
      ],
      'snake_case through a quoted index': [
        'lib/social.dart',
        "if (a['exercise_name'] == b.name) merge();",
      ],
      'a nullish default around the spelling': [
        'lib/social.dart',
        "if ((s.exerciseName ?? '') == last.name) merge();",
      ],
      'neither operand says exercise where the comparison is written': [
        'lib/widgets/gym_compose_sheet.dart',
        "final name = (s['exercise_name'] as String?) ?? '';\n    if (last.name.text == name) last.sets.add(row);",
      ],
    };
    caught.forEach((label, c) {
      expect(rawNameComparisonHits(c[0], c[1]).length, 1, reason: 'missed: $label');
    });

    const spared = <String, List<String>>{
      'the fix itself': [
        'lib/gym_prs.dart',
        'if (normaliseExerciseName(s.exerciseName) != key) continue;',
      ],
      'the fix with the fold on the right': [
        'lib/x.dart',
        'if (key != normaliseExerciseName(s.exerciseName)) continue;',
      ],
      'the helper, which is not a comparison at all': [
        'lib/y.dart',
        'if (sameExerciseName(last.name, s.exerciseName)) last.sets.add(s);',
      ],
      'a blankness test, which the blankness scan owns': [
        'lib/z.dart',
        "if (s.exerciseName == '') continue;",
      ],
      'a null test': ['lib/w.dart', 'if (s.exerciseName == null) continue;'],
      'an id compared, not a spelling': [
        'lib/v.dart',
        'if (a.exerciseId == b.exerciseId) merge();',
      ],
      'a count compared': [
        'lib/u.dart',
        'if (a.exerciseCount != b.exerciseCount) redraw();',
      ],
      'a comment describing the ban': [
        'lib/t.dart',
        '// never last.name == s.exerciseName',
      ],
      'a string mentioning it': [
        'lib/s.dart',
        "const doc = 'last.name == s.exerciseName';",
      ],
      'a greater-or-equal beside one': [
        'lib/r.dart',
        'if (s.exerciseName.length >= 1) keep();',
      ],
      'an arrow function': ['lib/q.dart', 'String f(s) => s.exerciseName;'],
    };
    spared.forEach((label, c) {
      expect(rawNameComparisonHits(c[0], c[1]), isEmpty,
          reason: 'false positive: $label');
    });
  });

  test('no mobile surface decides an exercise name is blank on the display spelling',
      () {
    final offenders = _scanTree(blankSpellingTestHits);
    expect(
      offenders,
      isEmpty,
      reason: 'Decide blankness with namesAnExercise from gym_prs.dart, never '
          "with `name.trim().isEmpty`. This runtime's trim() strips exactly the "
          'folded class, so the two agree HERE and the web twin they are '
          'twinned with saved a set whose exercise_key is empty (decisions '
          '1367):\n${offenders.join('\n')}',
    );
  });

  test('the blankness scan sees the shapes it bans, and spares the ones it must not',
      () {
    const caught = <String, List<String>>{
      'the compose sheet drop guard, named by a declaration one line up': [
        'lib/widgets/gym_compose_sheet.dart',
        'final ex = _EditExercise();\n    final name = ex.name.text.trim();\n    if (name.isEmpty) continue;',
      ],
      'the routine builder filter, named by the chain': [
        'lib/widgets/routine_builder_sheet.dart',
        'final named = _exercises.where((e) => e.name.text.trim().isNotEmpty);',
      ],
      'the receiver names one, the file otherwise does not': [
        'lib/social.dart',
        'if (s.exerciseName.isEmpty) continue;',
      ],
      'a placeholder chosen on the spelling': [
        'lib/social.dart',
        "Text(step.exerciseName.isEmpty ? '—' : step.exerciseName);",
      ],
      'the comparison spelling of the same question': [
        'lib/social.dart',
        "if (s.exerciseName == '') continue;",
      ],
      'the literal on the left': [
        'lib/social.dart',
        "if ('' == s.exerciseName) continue;",
      ],
      'a length test instead': [
        'lib/social.dart',
        'if (s.exerciseName.length == 0) continue;',
      ],
      'two declaration hops inside a file that names an exercise': [
        'lib/screens/composer.dart',
        'final e = Exercise();\n    final raw = block.name;\n    final name = raw;\n    if (name.isEmpty) continue;',
      ],
      // The picker's create path: the value arrives through a getter over a
      // TextEditingController, so the declaration chase cannot reach anything
      // that names an exercise and the subject identifier is the only evidence
      // there is (decisions § 1573).
      "the picker's create path, whose value came from a search box": [
        'lib/widgets/exercise_catalogue_picker.dart',
        'final e = exercise;\n    final name = _query;\n    if (name.isEmpty) return;',
      ],
      'the same call site written as a comparison': [
        'lib/widgets/exercise_catalogue_picker.dart',
        "final e = exercise;\n    final name = _query;\n    if (name == '') return;",
      ],
      'the same call site written as a length test': [
        'lib/widgets/exercise_catalogue_picker.dart',
        'final e = exercise;\n    final name = _query;\n    if (name.length == 0) return;',
      ],
    };
    caught.forEach((label, c) {
      expect(blankSpellingTestHits(c[0], c[1]).length, 1, reason: 'missed: $label');
    });

    const spared = <String, List<String>>{
      'the fix itself': [
        'lib/widgets/gym_compose_sheet.dart',
        'final ex = _EditExercise();\n    final name = ex.name.text.trim();\n    if (!namesAnExercise(name)) continue;',
      ],
      'the key tested directly, as every site that already holds one does': [
        'lib/screens/gym_screen.dart',
        'final key = normaliseExerciseName(raw);\n    if (key.isEmpty) continue;',
      ],
      'a title trimmed in a file full of exercises': [
        'lib/widgets/routine_builder_sheet.dart',
        'final exercises = [];\n    if (title.trim().isEmpty) return;',
      ],
      'a numeric field in a file full of exercises': [
        'lib/widgets/gym_compose_sheet.dart',
        'final step = exercise;\n    if (s.reps.text.trim().isNotEmpty) return true;',
      ],
      'a .name blank test in a file with nothing to do with exercises': [
        'lib/screens/club_detail_screen.dart',
        'if (club.name.trim().isEmpty) return;',
      ],
      'a count of blocks, whose declaration filtered on the key': [
        'lib/widgets/routine_builder_sheet.dart',
        'final named = _exercises.where((e) => namesAnExercise(e.name.text));\n    if (named.isEmpty) return const [];',
      ],
      'an identity test, which the raw-comparison scan owns': [
        'lib/y.dart',
        'if (last.name == s.exerciseName) merge();',
      ],
      'a null test': ['lib/z.dart', 'if (s.exerciseName == null) continue;'],
      'a comment describing the ban': [
        'lib/u.dart',
        '// never s.exerciseName.trim().isEmpty',
      ],
      'a string mentioning it': [
        'lib/t.dart',
        "const doc = 'exerciseName.isEmpty';",
      ],
    };
    spared.forEach((label, c) {
      expect(blankSpellingTestHits(c[0], c[1]), isEmpty,
          reason: 'false positive: $label');
    });
  });

  test('a regression at the picker create path fails the scan', () {
    // The picker's own file as it stands, plus the regression the three cases
    // above plant into it. Read from disk rather than restated, because what
    // makes the call site reachable is a property of the FILE — it names an
    // exercise, and the value under test is called `name` — and a restatement
    // would keep passing after the file stopped having it. § 1368 recorded that
    // this call site was out of the scan's reach on both rails; web closed its
    // half in § 1483 and this is the port.
    const picker = 'lib/widgets/exercise_catalogue_picker.dart';
    final source = File(picker).readAsStringSync();
    expect(blankSpellingTestHits(picker, source), isEmpty,
        reason: 'the picker create path is fixed');
    const fixed = '!namesAnExercise(name) ||';
    expect(source.contains(fixed), isTrue,
        reason: 'the create path moved — re-anchor this guard');
    expect(
        blankSpellingTestHits(picker, source.replaceFirst(fixed, 'name.isEmpty ||'))
            .length,
        1,
        reason: 'a regression at the picker create path must fail this scan');
  });
}
