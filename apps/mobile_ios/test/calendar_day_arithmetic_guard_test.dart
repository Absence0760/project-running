// Stepping a DATE by days must go through the calendar, not through a fixed
// 24-hour `Duration`.
//
// `DateTime.add(Duration(days: n))` on a local DateTime adds absolute time. A
// local calendar day is 23 or 25 hours across a DST transition, so a midnight
// cursor stepped this way lands at 23:00 the PREVIOUS day (fall-back) — the
// calendar day repeats, the last day of a window is never produced, and every
// offset after the transition is shifted by one. `DateTime(y, m, d + n)`
// normalises through the calendar and is right on both sides of a transition;
// it is also the form web's `Date.setDate()` twins take.
//
// The project has fixed this same shape repeatedly — `goals.weekStartLocal`,
// `streaks._previousLocalDay`, `recurrence._addDaysCalendar`, `plan_week`
// (issue #338), then the plan-detail week strip, the dashboard heatmap grid,
// `recap._mondayOf`, the nutrition day/trend windows, the period-summary
// pager and the "Yesterday" heading. Each was found by someone noticing a
// wrong date long after the fact, so the class is pinned in source.
//
// The scan asks only about `Duration(days:)` reached through `.add(` /
// `.subtract(`, which is date-cursor arithmetic. A `Duration(days:)` used as a
// VALUE — a retention period, a timeout, a window length — is not a date step
// and is not reported.
//
// A site that genuinely means "this many 24-hour blocks of ELAPSED TIME" opts
// out with an `// elapsed-time:` marker on the line or the line above, naming
// the reason. The marker is deliberately local rather than a file-level
// allowlist: several of these files carry both shapes, and an allowlist keyed
// on the file would have gone on covering the next offender added to it.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

const _marker = 'elapsed-time:';

final _dayStep = RegExp(r'\.(add|subtract)\(\s*(const\s+)?Duration\(\s*days\s*:');

/// A receiver that cannot be a local date cursor.
///
/// `DateTime.now()` is an instant, not a midnight, and `.toUtc()` has no DST
/// to drift across — stepping either by 24-hour blocks is exactly what the
/// code means (a query bound, a picker range, an absolute cutoff).
final _instantReceiver = RegExp(r'(DateTime\.now\(\)|\.toUtc\(\))\s*$');

/// Whether the 1-based [line] carries the opt-out marker, either inline or
/// anywhere in the contiguous `//` comment block directly above it. A reason
/// worth writing rarely fits on one line, and a marker that only counted on
/// the line above would push authors into cramming or repeating it.
bool _markedAt(List<String> lines, int line) {
  if (lines[line - 1].contains(_marker)) return true;
  for (var i = line - 2; i >= 0; i--) {
    final t = lines[i].trim();
    if (!t.startsWith('//')) return false;
    if (t.contains(_marker)) return true;
  }
  return false;
}

void main() {
  test('date arithmetic steps calendar days, not fixed 24-hour Durations', () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    final offenders = <String>[];
    for (final file in dartFiles(_root)) {
      final raw = file.readAsStringSync();
      final rel = file.path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');
      final code = blankNonCode(raw);
      final rawLines = raw.split('\n');
      for (final match in _dayStep.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        if (_markedAt(rawLines, line)) continue;
        // The receiver is whatever precedes the `.add(` / `.subtract(`.
        if (_instantReceiver.hasMatch(code.substring(0, match.start))) continue;
        offenders.add('$rel:$line  ${match.group(1)}(Duration(days: ...))');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Step a date with DateTime(y, m, d + n) instead — '
          '.add/.subtract(Duration(days:)) drifts across a DST transition. '
          'If the site really means elapsed time, mark it '
          '`// $_marker <why>`:\n${offenders.join('\n')}',
    );
  });

  test('the guard still sees the shape it exists to catch', () {
    // A scan that silently matches nothing — a moved root, a regex broken by a
    // refactor — passes the test above for the wrong reason. §510 found that
    // failure mode in `status_color`; prove the matcher still fires.
    const sample = '''
      final a = start.add(const Duration(days: 6));
      final b = start.subtract(Duration(days: 1));
    ''';
    expect(_dayStep.allMatches(sample).length, 2);
    expect(_instantReceiver.hasMatch('final c = DateTime.now()'), isTrue);
    expect(_instantReceiver.hasMatch('final d = now.toUtc()'), isTrue);
    expect(_instantReceiver.hasMatch('final e = start'), isFalse);
  });
}
