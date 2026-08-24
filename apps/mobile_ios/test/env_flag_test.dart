// The mobile feature-flag contract: one parser, every gate.
//
// The parse used to be copied into four gates, and one of the copies was
// narrower — `WEIGH_IN_GATE=yes` left the Art 9 weigh-in fields off while the
// same string turned every other gate on (decisions § 709).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/env_flag.dart';
import 'source_scan.dart';

const _libRoot = 'lib';
const _canonical = 'lib/env_flag.dart';

/// The shape of the copied parse: a comparison chain opening on `'1'` and
/// naming one of the two literals only a full copy carries.
final _chainHead = RegExp(r"==\s*'1'\s*\|\|");
final _chainTail = RegExp(r"==\s*'(?:yes|on)'");

/// The matches of [pattern] in [src] that are real code rather than prose.
/// `blankNonCode` leaves code (and string delimiters) in place and blanks
/// comment bodies, so a match whose blanked span is empty was a mention.
Iterable<RegExpMatch> codeMatches(String src, RegExp pattern) {
  final blanked = blankNonCode(src);
  return pattern
      .allMatches(src)
      .whereType<RegExpMatch>()
      .where((m) => blanked.substring(m.start, m.end).trim().isNotEmpty);
}

bool matchesInCode(String src, RegExp pattern) =>
    codeMatches(src, pattern).isNotEmpty;

void main() {
  group('isTruthyFlagValue — the one accepted-affirmative set', () {
    test('accepts every affirmative literal', () {
      for (final v in ['1', 'true', 'yes', 'on']) {
        expect(isTruthyFlagValue(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('affirmatives are case-insensitive', () {
      for (final v in ['TRUE', 'True', 'YES', 'On', 'ON']) {
        expect(isTruthyFlagValue(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('surrounding whitespace is trimmed', () {
      for (final v in [' true ', '\t1', 'yes\n', '  on  ']) {
        expect(isTruthyFlagValue(v), isTrue, reason: '"$v" should enable');
      }
    });

    test('fail-closed for unset / empty', () {
      for (final v in [null, '', '   ']) {
        expect(isTruthyFlagValue(v), isFalse,
            reason: '"${v ?? '<null>'}" should stay off');
      }
    });

    test('fail-closed for negatives + junk', () {
      for (final v in ['0', 'false', 'no', 'off', 'enabled', 'y', 't', '2', 'truthy']) {
        expect(isTruthyFlagValue(v), isFalse, reason: '"$v" should stay off');
      }
    });
  });

  group('one parser, every gate', () {
    test('env_flag.dart is the only library that spells the set out', () {
      final canonical = File(_canonical).readAsStringSync();
      expect(
        matchesInCode(canonical, _chainHead) && matchesInCode(canonical, _chainTail),
        isTrue,
        reason: 'env_flag.dart no longer matches the chain pattern this guard '
            'looks for — the parse was rewritten and the guard checks nothing.',
      );

      final offenders = dartFiles(_libRoot)
          .where((f) => f.path != _canonical)
          .where((f) {
            final src = f.readAsStringSync();
            return matchesInCode(src, _chainHead) && matchesInCode(src, _chainTail);
          })
          .map((f) => f.path)
          .toList();

      expect(offenders, isEmpty,
          reason: 'Inline copy of the feature-flag affirmative set in '
              '${offenders.join(', ')}. Import isTruthyFlagValue from '
              'env_flag.dart instead — a second copy is how the accepted '
              'values drift apart between gates (decisions § 709).');
    });

    // Named individually because each is a fail-closed sign-off gate: a gate
    // that quietly narrows its accepted set is a deploy that looks flipped and
    // is not. `WEIGH_IN_GATE` was exactly that — `1`/`true` only.
    for (final gate in const {
      'lib/off_route_alert.dart': 'offRouteEscalationEnabled',
      'lib/plan_adaptive_replan.dart': 'adaptiveFitnessGateEnabled',
      'lib/nearby_flag.dart': 'nearbyRunnersEnabled',
      'lib/screens/checkpoint_checkin_screen.dart': '_weighInGate',
    }.entries) {
      test('${gate.value} delegates to isTruthyFlagValue', () {
        final src = File(gate.key).readAsStringSync();
        final at = src.indexOf(gate.value);
        expect(at, greaterThan(0),
            reason: '${gate.value} is gone from ${gate.key} — rename?');
        expect(src.contains('isTruthyFlagValue'), isTrue,
            reason: '${gate.key} must parse its flag through the canonical '
                'isTruthyFlagValue, not a private copy.');
      });
    }
  });
}
