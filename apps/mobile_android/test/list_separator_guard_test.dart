// Source-scan guard for issue #666 C18: card-list separators.
//
// The finding read "8 dp everywhere except `clubs_screen.dart:236` (10)". The
// exception is three files, not one: `clubs_screen` and `plans_screen` at 10
// and `feed_screen` at 12, against nine lists at 8. Two sibling tabs of the
// same hub disagreeing by 2 dp is exactly the drift a reader cannot name but
// can feel when switching between them.
//
// A `Divider` separator is a different thing — a drawn rule, not a gap — and
// four lists use one deliberately, so this measures only the `SizedBox` form.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _roots = ['lib'];
const _gap = 8;

final _sizedBoxSeparator = RegExp(
  r'separatorBuilder:\s*\([^)]*\)\s*=>\s*(?:const\s+)?SizedBox\(\s*height:\s*(\d+)',
  dotAll: true,
);

void main() {
  test('every list separator is the same gap', () {
    final offenders = <String>[];
    var measured = 0;

    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _sizedBoxSeparator.allMatches(src)) {
          measured++;
          if (int.parse(m.group(1)!) == _gap) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line height: ${m.group(1)}');
        }
      }
    }

    // §534: the assertion must not pass over an empty set.
    expect(measured, greaterThan(8),
        reason: 'found only $measured SizedBox separators — the scan is '
            'probably broken rather than the lists having gone away');
    expect(offenders..sort(), isEmpty,
        reason: 'these lists separate their rows by something other than '
            '$_gap dp. A Divider is a different thing and is not measured '
            'here; a gap is a gap.');
  });
}
