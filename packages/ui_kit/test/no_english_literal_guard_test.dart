import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ui_kit has no localization catalogue and never will: it is imported by both
/// mobile twins and knows nothing about `AppLocalizations`. So a user-facing
/// string literal in here is not a string that needs translating later — it is
/// English shipped to all seven locales with no key to translate.
///
/// The trap this guard exists for is the *default*, not the literal. Every
/// caller of `ActivityLoader` passed a label, so `label ?? 'Loading'` was
/// invisible: nothing was broken, and the first caller to omit the argument
/// would have shipped English silently. A required parameter is the fix; this
/// guard is what keeps the next optional one from being added.
///
/// It fires two ways: on a word-bearing literal reaching a `Text(`, a
/// `label:`, a `semanticLabel:`, a `hintText:` or a `tooltip:`, and on any
/// `?? 'literal'` fallback, which is the shape the ActivityLoader default took
/// and the shape no sink pattern would have caught. Symbol-only literals ('?',
/// '—', '/') carry no language and are allowed, as are the empty string and
/// interpolations of caller-supplied values.
void main() {
  final dir = Directory('lib/src');

  /// A literal is language-bearing once it holds two consecutive letters.
  final hasWord = RegExp(r'[A-Za-z]{2}');

  final sinks = [
    RegExp(
      r"(?:Text\(|label:\s*|semanticLabel:\s*|hintText:\s*|tooltip:\s*)"
      r"(?:const\s+)?(?:Text\(\s*)?'([^'\\$]*)'",
    ),
    RegExp(r"\?\?\s*'([^'\\$]*)'"),
  ];

  test('no user-facing English literal reaches a ui_kit widget', () {
    final offenders = <String>[];
    for (final f in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final sink in sinks) {
        for (final m in sink.allMatches(src)) {
          final literal = m.group(1)!;
          if (!hasWord.hasMatch(literal)) continue;
          final line = src.substring(0, m.start).split('\n').length;
          offenders.add('${f.path}:$line — "$literal"');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'ui_kit cannot localize a string. Take it as a required '
            'parameter from the caller, which has a catalogue:\n'
            '${offenders.join('\n')}');
  });
}
