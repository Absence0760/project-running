// A widget test waits on a condition with a deadline that fails, never on a
// duration that hopes (decisions § 715), and § 723 worked the residue down to
// a set that each has a stated reason. Nothing held that line.
//
// The failure mode is not that anyone reintroduces a sleep on purpose — it is
// that the next test is written by copying the one beside it, which is the
// same way the four inline flag parsers grew (§ 709). A doc comment does not
// catch that; a scan does.
//
// Two rules, both derived from the tree rather than transcribed:
//   1. A `Future.delayed` inside `tester.runAsync` is a real-clock wait. Every
//      one that remains is listed here with the reason § 723 recorded for it,
//      and a site that is neither listed nor converted fails the suite.
//   2. A file-local wrapper that takes the PREDICATE per call site must take
//      its `describe` too. A deadline that expires has to say which condition
//      never held; a wrapper answering "the screen to reach the expected
//      state" for eight different waits has given that away.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _testRoot = 'test';

/// The helper itself: its 5 ms slice IS the real-loop turn every conversion
/// depends on, so it can never appear in the residue.
const _helper = 'test/pump_until.dart';

/// Every real-clock wait § 723 left standing, with the reason it left it.
/// A file listed here whose sites have all been converted is a stale
/// exemption and fails, exactly as the wrist's activity-vocabulary guard
/// holds its own exemption non-stale.
const Map<String, String> _documentedDelays = <String, String>{
  'test/checkpoint_checkin_screen_test.dart':
      'absence assertion — a refused stamp writes nothing, so every predicate '
          'already holds before the tap',
  'test/gym_screen_test.dart':
      'teardown drain — runs after the last assertion, before the temp dir is '
          'deleted',
  'test/import_screen_paths_test.dart':
      'absence assertion — a pick carrying no readable path returns before the '
          'screen sets any state',
  'test/nutrition_log_sheet_test.dart':
      "absence assertion — a cancelled scan's only state change is _scanning "
          'true-then-false',
  'test/pump_until_test.dart':
      'the delay IS the subject — it is the real-loop work the helper must '
          'turn the loop to see, not plumbing around an assertion',
  'test/plan_new_screen_test.dart':
      'shared helper whose callers want different things; the common case is a '
          'template read resolving to nothing',
  'test/roadbook_screen_test.dart':
      'shared helper — the race-plan adoption read resolves to null in most of '
          'its callers, so no predicate is ever false',
  'test/route_detail_watch_course_test.dart':
      'shared helper — same race-plan adoption read as roadbook_screen_test',
  'test/routes_screen_fab_double_tap_test.dart':
      'zero-duration microtask flush after completing a picker, not a timed '
          'wait',
  'test/run_screen_recording_flow_test.dart':
      'models elapsed time — the 11 s GPS blackout § 715 named; plus the paired-'
          'belt read whose only assertion is an absence',
  'test/run_screen_test.dart':
      'drain of the mocked, in-memory preference store the assertions read '
          'straight back',
  'test/watch_live_screen_test.dart':
      'cancelling the sim-watch frame generator never completes under the fake '
          'clock, so teardown has to run on the real one',
  'test/watch_screens_editor_screen_test.dart':
      'drain of the mocked, in-memory preference store — any predicate over it '
          'holds the moment setString is called',
};

/// Every `tester.runAsync(...)` body in [src] that contains a `delayed(`,
/// as (line, snippet) pairs. Bracket-matched over the blanked source so a
/// mention in a comment or a string is not a site.
List<({int line, String snippet})> realClockWaits(String src) {
  final blanked = blankNonCode(src);
  final out = <({int line, String snippet})>[];
  for (final m in RegExp(r'runAsync\s*\(').allMatches(blanked)) {
    var depth = 0;
    var i = m.end - 1;
    while (i < blanked.length) {
      final c = blanked[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    if (i >= blanked.length) continue;
    final body = blanked.substring(m.end, i);
    if (!body.contains('delayed(')) continue;
    out.add((
      line: '\n'.allMatches(src.substring(0, m.start)).length + 1,
      snippet: src.substring(m.end, i).trim().replaceAll('\n', ' '),
    ));
  }
  return out;
}

void main() {
  group('no test sleeps where it could wait on a condition (§ 715 / § 723)',
      () {
    test('the scan still sees the tree it is scanning', () {
      expect(rootExists(_testRoot), isTrue,
          reason: 'the test root moved and this guard is checking nothing');
      expect(File(_helper).existsSync(), isTrue,
          reason: 'pump_until.dart is the alternative every rule below points '
              'at — if it moved, this guard points nowhere');
      expect(dartFiles(_testRoot).length, greaterThan(400),
          reason: 'the file walk collapsed — a guard that finds nothing '
              'certifies nothing');
    });

    test('every real-clock wait left standing is one § 723 named', () {
      final offenders = <String>[];
      var found = 0;
      for (final f in dartFiles(_testRoot)) {
        if (f.path == _helper) continue;
        final sites = realClockWaits(f.readAsStringSync());
        if (sites.isEmpty) continue;
        found += sites.length;
        if (_documentedDelays.containsKey(f.path)) continue;
        for (final s in sites) {
          offenders.add('${f.path}:${s.line}  ${s.snippet.substring(0, s.snippet.length.clamp(0, 90))}');
        }
      }

      expect(found, greaterThanOrEqualTo(_documentedDelays.length),
          reason: 'the runAsync/delayed scan found $found sites for '
              '${_documentedDelays.length} documented files — its bracket '
              'matching broke and it is enforcing nothing');
      expect(offenders, isEmpty,
          reason: 'a fixed real-clock delay is doing synchronisation work '
              'here. Wait on the thing you are actually waiting for with '
              'pumpUntil (test/pump_until.dart): its timeout is a FAILURE '
              'bound, so a regression is loud instead of slept through. If '
              'the wait genuinely has no condition that is ever false, add '
              'the file to _documentedDelays with the reason:\n'
              '${offenders.join('\n')}');
    });

    test('no documented exemption has outlived its site', () {
      final stale = <String>[];
      for (final path in _documentedDelays.keys) {
        final file = File(path);
        if (!file.existsSync()) {
          stale.add('$path (file is gone)');
          continue;
        }
        if (realClockWaits(file.readAsStringSync()).isEmpty) {
          stale.add('$path (no real-clock wait left)');
        }
      }
      expect(stale, isEmpty,
          reason: 'these exemptions no longer describe anything. Remove them '
              'so the list keeps meaning what it says:\n${stale.join('\n')}');
    });
  });

  group('every deadline names its own condition', () {
    test('no file-local wrapper bakes in one description for every wait', () {
      // Named `_pumpUntil` in two files and `_settleUntil` in two more, so
      // the rule is about the SHAPE, not the name: any private wrapper that
      // takes the PREDICATE per call site and still passes one literal
      // describe answers the same sentence for every wait in its file. A
      // wrapper that owns both its predicate and its description is fine —
      // every call site there is waiting for the same thing.
      final offenders = <String>[];
      var wrappersSeen = 0;
      for (final f in dartFiles(_testRoot)) {
        if (f.path == _helper) continue;
        final src = f.readAsStringSync();
        final blanked = blankNonCode(src);
        for (final m in RegExp(r'Future<void>\s+(_\w+)\s*\(').allMatches(blanked)) {
          var depth = 0;
          var i = m.end - 1;
          while (i < blanked.length) {
            if (blanked[i] == '(') depth++;
            if (blanked[i] == ')') {
              depth--;
              if (depth == 0) break;
            }
            i++;
          }
          if (i >= blanked.length) continue;
          final params = blanked.substring(m.end, i);
          if (!params.contains('bool Function()')) continue;
          final body = src.substring(i, (i + 600).clamp(0, src.length));
          if (!RegExp(r'\bpumpUntil\(').hasMatch(body)) continue;
          wrappersSeen++;
          if (RegExp(r"describe:\s*'").hasMatch(body) &&
              !params.contains('required String describe')) {
            offenders.add('${f.path} (${m.group(1)})');
          }
        }
      }
      expect(wrappersSeen, greaterThanOrEqualTo(4),
          reason: 'the wrapper scan found only $wrappersSeen predicate-taking '
              'wrappers — its shape assumptions broke and it is enforcing '
              'nothing');
      expect(offenders, isEmpty,
          reason: 'a wrapper that takes the predicate per call site and bakes '
              'in one describe means an expired deadline no longer says which '
              'condition never held. Take `required String describe` and pass '
              'it through: ${offenders.join(', ')}');
    });

    test('no call site passes an empty description', () {
      final offenders = <String>[];
      final describe = RegExp(r"describe:\s*'([^']*)'");
      for (final f in dartFiles(_testRoot)) {
        final src = f.readAsStringSync();
        final blanked = blankNonCode(src);
        for (final m in describe.allMatches(src)) {
          // Blanked source keeps the delimiters and empties the body, so a
          // match whose body survives blanking is a real argument.
          if (blanked.substring(m.start, m.end).trim().isEmpty) continue;
          if (m.group(1)!.trim().length < 4) {
            offenders.add('${f.path}: "${m.group(1)}"');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a deadline whose message says nothing is a sleep wearing a '
              'different hat: ${offenders.join(', ')}');
    });
  });
}
