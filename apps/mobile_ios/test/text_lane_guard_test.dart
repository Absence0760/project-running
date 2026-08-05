import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text-lane guard — fails any literal-width box drawn directly around text.
///
/// A `SizedBox(width: 56, child: Text(...))` is a bug waiting on a device
/// setting, and it is a *silent* one. Neither of the two axes that widen the
/// glyphs is visible to the author: the OS text scale (up to 2x on both
/// platforms) and the active locale. There is no exception and no overflow
/// stripe — a label with a break opportunity reflows inside the box and makes
/// its row taller than the rest of the column, and one without ("120:00",
/// "#999", "Desaquecimento") paints straight over the lane beside it.
///
/// The fix is `TextLane` from ui_kit, which reads the literal as a *floor*
/// scaled by `MediaQuery.textScalerOf` — 1.0x geometry preserved exactly, the
/// lane growing in step with the glyphs, and content that still outruns it
/// widening the lane instead of losing characters. Where a term and its value
/// genuinely cannot share a line at 2x, the row reflows (a `Wrap`) instead.
///
/// Deliberately narrow, so it does not fight the mechanisms §497 already
/// settled on: it fires only when the box's **direct** child is a `Text`, or a
/// `Column`/`Row` whose every child is a `Text`. A fixed-size *graphic* that
/// fits its text with `BoxFit.scaleDown` (the run screen's lap badge, the
/// calendar day dot), a box around an image, and a box around a spinner all
/// keep their literal dimension and are not matched.
///
/// Source-level (like `tap_target_guard_test.dart`) because several of these
/// lanes live inside private row builders whose screens need a live Supabase
/// client, or below the fold of a lazy list.

/// The balanced-paren span starting at the `(` at [open], skipping quoted
/// strings and comments so a paren inside either can't derail the depth count.
/// Returns the index of the matching `)`.
int _matchClose(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < src.length) {
        if (src[i] == r'\') {
          i++;
        } else if (src[i] == quote || src[i] == '\n') {
          break;
        }
        i++;
      }
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// The depth-0 comma-separated argument spans inside [body].
List<String> _args(String body) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(body.substring(start, i));
      start = i + 1;
    }
  }
  out.add(body.substring(start));
  return out;
}

final _literalWidth = RegExp(r'^\s*width:\s*-?[0-9][0-9._]*\s*$');
final _childArg = RegExp(r'^\s*child:\s*(?:const\s+)?([A-Za-z_][\w.]*)',
    dotAll: true);
final _textChild = RegExp(r'^\s*(?:const\s+)?Text\s*\(', dotAll: true);

/// True when every depth-0 child of a `children: [...]` list is a `Text(`.
bool _allChildrenAreText(String body) {
  final i = body.indexOf('children:');
  if (i < 0) return false;
  final open = body.indexOf('[', i);
  if (open < 0) return false;
  var depth = 0;
  var close = -1;
  for (var j = open; j < body.length; j++) {
    final c = body[j];
    if (c == '[' || c == '(' || c == '{') {
      depth++;
    } else if (c == ']' || c == ')' || c == '}') {
      depth--;
      if (depth == 0) {
        close = j;
        break;
      }
    }
  }
  if (close < 0) return false;
  final items = _args(body.substring(open + 1, close))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  return items.isNotEmpty && items.every((s) => _textChild.hasMatch(s));
}

void main() {
  test('no literal-width box is drawn directly around text', () {
    final offenders = <String>[];
    final boxCall = RegExp(r'(?<![\w.])(SizedBox|Container)\s*\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      for (final m in boxCall.allMatches(src)) {
        final open = m.end - 1;
        final close = _matchClose(src, open);
        if (close < 0) continue;
        final body = src.substring(open + 1, close);
        final args = _args(body);
        if (!args.any(_literalWidth.hasMatch)) continue;

        final childArg = args.firstWhere(
          (a) => _childArg.hasMatch(a),
          orElse: () => '',
        );
        if (childArg.isEmpty) continue;
        final kind = _childArg.firstMatch(childArg)!.group(1);

        final wrapsText = kind == 'Text' ||
            ((kind == 'Column' || kind == 'Row') &&
                _allChildrenAreText(childArg));
        if (!wrapsText) continue;

        final line = '\n'.allMatches(src.substring(0, open)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'A literal width around text crops silently once the OS text '
          'scale or the locale widens the glyphs. Use TextLane (ui_kit) so '
          'the literal becomes a scaled floor, reflow the row with a Wrap '
          'when a label and its value cannot share a line, or — if the box '
          'is a graphic whose size is load-bearing — keep the box and fit '
          'the text with BoxFit.scaleDown (§497). Offenders:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
