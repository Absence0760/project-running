// Source-scan guard for issue #666 C10. `useSafeArea` is not a theme field —
// it is decided per call — and its default is false, which lets a sheet paint
// under the status bar. That only becomes reachable once the sheet is allowed
// to exceed the 9/16-screen cap, so the rule is: `isScrollControlled: true`
// implies `useSafeArea: true`. Everything else about a sheet (background,
// shape, drag handle, clip) comes from AppTheme's bottomSheetTheme.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every scroll-controlled modal sheet opts into the safe area', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      var from = 0;
      while (true) {
        final start = source.indexOf('showModalBottomSheet', from);
        if (start < 0) break;
        from = start + 1;
        final open = source.indexOf('(', start);
        if (open < 0) break;
        var depth = 1;
        var i = open + 1;
        while (i < source.length && depth > 0) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') depth--;
          i++;
        }
        final args = source.substring(open + 1, i - 1);
        // Only the sheet's own arguments, not the builder's widget tree.
        final head = args.split('builder:').first;
        if (head.contains('isScrollControlled: true') &&
            !head.contains('useSafeArea: true')) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'add `useSafeArea: true` beside `isScrollControlled: true` '
            'so a tall sheet cannot slide under the status bar');
  });
}
