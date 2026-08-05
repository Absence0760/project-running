// Shared source-scanning machinery for the Dart-source architecture guards.
//
// Three of these guards ask the same two questions of a source file — "is this
// occurrence real code or a mention in a comment?" and "what constructor
// encloses it?" — and the second one is the load-bearing part: a `Text(...)`
// that CLOSED earlier in the same argument list is a sibling, not an encloser,
// so only brackets still open at the offset may cast a verdict. That bracket
// bookkeeping is the whole boundary between these guards and a backwards
// regex, and it belongs in one place rather than once per guard.

import 'dart:io';

/// Comments and string literals blanked to spaces, offsets preserved so
/// reported line numbers survive. A prose mention of a token in a doc comment
/// is not a use of it, and a guard that cannot tell the difference reports the
/// header that explains the rule.
String blankNonCode(String src) {
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
    } else if (src[i] == "'" || src[i] == '"') {
      final q = src[i];
      final triple = src.startsWith(q * 3, i);
      final delim = triple ? q * 3 : q;
      final raw = i > 0 && src[i - 1] == 'r';
      var j = i + delim.length;
      while (j < src.length) {
        if (!raw && src[j] == r'\') {
          j += 2;
          continue;
        }
        if (src.startsWith(delim, j)) break;
        if (!triple && src[j] == '\n') break;
        j++;
      }
      blank(i + delim.length, j);
      i = j + delim.length;
    } else {
      i++;
    }
  }
  return out.join();
}

/// Whether a scanned root is still there. A guard whose root has moved reports
/// nothing at all, which is the failure mode §510 found in `status_color`.
bool rootExists(String root) => Directory(root).existsSync();

/// Every `.dart` file under [root], sorted, or empty when the root is absent.
List<File> dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// The dotted name-chains of the brackets still OPEN at [at], innermost first.
///
/// `Border.all(color: x)` yields `['Border', 'all']`, so a caller can decide on
/// the trailing segment (`…bodySmall?.copyWith` is type) or on any segment (a
/// mark reached through a named factory). A bracket with no name before it —
/// a grouping paren, a list literal, a block — yields `['']`.
///
/// Lazy on purpose: a caller that returns on the innermost match never pays for
/// the rest of the walk, and stopping early is what makes "innermost wins".
Iterable<List<String>> enclosingHosts(String src, int at) sync* {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = src[i];
    if (c == ')' || c == ']' || c == '}') {
      depth++;
    } else if (c == '(' || c == '[' || c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      var j = i - 1;
      while (j >= 0 && _isSpace(src[j])) {
        j--;
      }
      var k = j;
      while (k >= 0 && _isNamePart(src[k])) {
        k--;
      }
      yield src
          .substring(k + 1, j + 1)
          .replaceAll(RegExp(r'[?!]'), '')
          .split('.');
    }
  }
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

final _namePart = RegExp(r'[A-Za-z0-9_$.?!]');

bool _isNamePart(String c) => _namePart.hasMatch(c);
