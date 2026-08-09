// A `setState` reached after an `await` must be preceded by a `mounted` check.
//
// The async gap is the whole problem: between the await and the resume the
// user can pop the route, sign out, or have the screen rebuilt away, and
// `setState` on a defunct State throws — a crash on a path that only shows up
// when someone leaves mid-request, which is exactly the path nobody exercises
// by hand. Issue #734 found the shape in nine places, several of them with the
// guard present but ONE LINE TOO LATE.
//
// The scan is deliberately structural rather than a backwards regex. It walks
// the file tracking a frame per `{`, records the last `await` and the last
// `mounted` on the innermost enclosing FUNCTION frame, and reports a
// `setState` whose frame chain carries an await with no later `mounted`.
// Three properties earn their complexity:
//
//   * a closure body starts a fresh frame — an await in the enclosing method
//     says nothing about a callback that runs later;
//   * a block that escapes (`return` / `throw` / `break` / `continue` as its
//     last statement) does not hand its awaits to the parent, so
//     `if (x) { await f(); return; }` followed by a `setState` is not a hit;
//   * a `mounted` seen anywhere before the setState in the same chain counts,
//     so `if (!mounted) return;`, `if (mounted) setState(...)` and
//     `if (!context.mounted) return;` all read as guarded.
//
// It is tuned for precision over recall: a guard that lives in a helper the
// method calls, or one branch of a conditional, is not seen and the site is
// let through. That is the right trade — a noisy guard gets suppressed, a
// quiet one keeps catching the next instance.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

/// Sites this guard is knowingly not asking about. Empty is the goal — add an
/// entry only with the reason the async gap cannot reach a disposed State.
const _allowlist = <String>{};

const _controlKeywords = {
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'do',
  'else',
  'try',
  'finally',
  'return',
  'assert',
};

const _escapeKeywords = {'return', 'throw', 'break', 'continue'};

class _Frame {
  _Frame(this.isFunction);

  final bool isFunction;
  int? lastAwait;
  int? lastGuard;
}

final _nameChar = RegExp(r'[A-Za-z0-9_$]');

bool _isNamePart(String c) => _nameChar.hasMatch(c);

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

String _wordBefore(String src, int at) {
  var j = at - 1;
  while (j >= 0 && _isSpace(src[j])) {
    j--;
  }
  if (j < 0) return '';
  var k = j;
  while (k >= 0 && _isNamePart(src[k])) {
    k--;
  }
  return src.substring(k + 1, j + 1);
}

int _matchOpenParen(String src, int at) {
  var depth = 0;
  for (var i = at; i >= 0; i--) {
    final c = src[i];
    if (c == ')') depth++;
    if (c == '(') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Whether the `{` at [braceAt] opens a function body rather than a plain
/// block. `foo() {`, `() async {` and `f() async* {` do; `if (x) {`,
/// `catch (e) {`, `class Foo {` and a bare `{` do not.
bool _opensFunctionBody(String src, int braceAt) {
  var j = braceAt - 1;
  while (j >= 0 && _isSpace(src[j])) {
    j--;
  }
  if (j < 0) return false;
  final word = _wordBefore(src, braceAt);
  if (word == 'async' || word == 'sync') return true;
  if (src[j] == '*') {
    final before = _wordBefore(src, j);
    if (before == 'async' || before == 'sync') return true;
  }
  if (src[j] != ')') return false;
  final open = _matchOpenParen(src, j);
  if (open < 0) return false;
  return !_controlKeywords.contains(_wordBefore(src, open));
}

/// Whether the block spanning [openAt]..[closeAt] ends in an escape statement,
/// which is what makes its awaits invisible to the code that follows it.
bool _blockEscapes(String src, int openAt, int closeAt) {
  var end = closeAt - 1;
  while (end > openAt && _isSpace(src[end])) {
    end--;
  }
  if (end <= openAt || src[end] != ';') return false;
  var k = end - 1;
  var depth = 0;
  while (k > openAt) {
    final c = src[k];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[') depth--;
    if (c == '{') {
      if (depth == 0) break;
      depth--;
    }
    if (depth == 0 && c == ';') break;
    k--;
  }
  var start = k + 1;
  while (start < end && _isSpace(src[start])) {
    start++;
  }
  var word = start;
  while (word < end && _isNamePart(src[word])) {
    word++;
  }
  return _escapeKeywords.contains(src.substring(start, word));
}

int _lineOf(String src, int offset) =>
    '\n'.allMatches(src.substring(0, offset)).length + 1;

List<String> unguardedPostAwaitSetState(String src, String label) {
  final hits = <String>[];
  final code = blankNonCode(src);
  final frames = <_Frame>[_Frame(true)];
  final opens = <int>[-1];
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    if (c == '{') {
      frames.add(_Frame(_opensFunctionBody(code, i)));
      opens.add(i);
      continue;
    }
    if (c == '}') {
      if (frames.length > 1) {
        final popped = frames.removeLast();
        final openAt = opens.removeLast();
        if (!popped.isFunction && !_blockEscapes(code, openAt, i)) {
          final parent = frames.last;
          if (popped.lastAwait != null &&
              (parent.lastAwait == null ||
                  parent.lastAwait! < popped.lastAwait!)) {
            parent.lastAwait = popped.lastAwait;
          }
          if (popped.lastGuard != null &&
              (parent.lastGuard == null ||
                  parent.lastGuard! < popped.lastGuard!)) {
            parent.lastGuard = popped.lastGuard;
          }
        }
      }
      continue;
    }
    if (!_isNamePart(c)) continue;
    if (i > 0 && _isNamePart(code[i - 1])) continue;
    var end = i;
    while (end < code.length && _isNamePart(code[end])) {
      end++;
    }
    final word = code.substring(i, end);
    i = end - 1;
    if (word == 'await') {
      frames.last.lastAwait = i;
    } else if (word == 'mounted') {
      frames.last.lastGuard = i;
    } else if (word == 'setState') {
      int? awaitAt;
      int? guardAt;
      for (var d = frames.length - 1; d >= 0; d--) {
        final frame = frames[d];
        if (frame.lastAwait != null &&
            (awaitAt == null || awaitAt < frame.lastAwait!)) {
          awaitAt = frame.lastAwait;
        }
        if (frame.lastGuard != null &&
            (guardAt == null || guardAt < frame.lastGuard!)) {
          guardAt = frame.lastGuard;
        }
        if (frame.isFunction) break;
      }
      if (awaitAt != null && (guardAt == null || guardAt < awaitAt)) {
        hits.add('$label:${_lineOf(code, i)} '
            '(await at line ${_lineOf(code, awaitAt)})');
      }
    }
  }
  return hits;
}

void main() {
  test('the scan distinguishes a real async gap from the shapes that look '
      'like one', () {
    String only(String body) =>
        unguardedPostAwaitSetState('class S { $body }', 'x')
            .map((h) => h.split(' ').first.split(':').last)
            .join(',');

    expect(only('Future<void> f() async { await g(); setState(() {}); }'), '1',
        reason: 'the bare shape the guard exists for');
    expect(
        only('Future<void> f() async { await g(); if (!mounted) return; '
            'setState(() {}); }'),
        '',
        reason: 'an early-return guard covers everything after it');
    expect(
        only('Future<void> f() async { await g(); '
            'if (mounted) setState(() {}); }'),
        '',
        reason: 'a positive guard reads the same way');
    expect(
        only('Future<void> f() async { await g(); if (!context.mounted) '
            'return; setState(() {}); }'),
        '',
        reason: 'a BuildContext guard counts');
    expect(only('void f() { setState(() {}); await_ = 1; }'), '',
        reason: 'an await AFTER the setState opens no gap');
    expect(
        only('Future<void> f() async { if (x) { await g(); return; } '
            'setState(() {}); }'),
        '',
        reason: 'a block that escapes never returns to the setState');
    expect(
        only('Future<void> f() async { await g(); '
            'run(() { setState(() {}); }); }'),
        '',
        reason: 'a closure body is its own frame, not a continuation');
    expect(
        only('Future<void> f() async { try { await g(); } catch (e) {} '
            'setState(() {}); }'),
        '1',
        reason: 'an await inside a try still gaps the code after it');
    expect(
        only('Future<void> f() async { try { await g(); } '
            'catch (e) { setState(() {}); } }'),
        '1',
        reason: 'a catch body runs strictly after the await it caught');
    expect(only('Future<void> f() async { await g(); /* setState(() {}); */ }'),
        '',
        reason: 'a commented-out mention is not a call');
  });

  test('no setState in lib/ is reached across an unguarded async gap', () {
    expect(rootExists(_root), isTrue,
        reason: 'the scanned root moved — this guard is reporting nothing');
    final hits = <String>[];
    for (final file in dartFiles(_root)) {
      final label = file.path.replaceFirst(RegExp('^$_root/'), '');
      hits.addAll(unguardedPostAwaitSetState(file.readAsStringSync(), label)
          .where((h) => !_allowlist.contains(h.split(' ').first)));
    }
    expect(
      hits,
      isEmpty,
      reason: 'Each of these calls setState after an await with no mounted '
          'check in between, so leaving the screen mid-request throws. Add '
          '`if (!mounted) return;` immediately after the await (not after the '
          'setState). See issue #734.\n${hits.join('\n')}',
    );
  });
}
