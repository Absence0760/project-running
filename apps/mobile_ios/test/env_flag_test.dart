// The mobile feature-flag contract: one parser, and every gate reachable in a
// release build.
//
// Two defects motivated this suite (decisions § 709). The parse was copied
// into four gates and one of the copies was narrower — `WEIGH_IN_GATE=yes`
// left the Art 9 weigh-in fields off while the same string turned every other
// gate on. And release builds never load `.env.development`, so a gate absent
// from main.dart's `String.fromEnvironment` bridge could not be flipped on in
// production at all, however the deploy passed it.

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
      .where((m) => blanked.substring(m.start, m.end).trim().isNotEmpty);
}

bool matchesInCode(String src, RegExp pattern) =>
    codeMatches(src, pattern).isNotEmpty;

/// Every dotenv key read anywhere under `lib/`, with the two indirections the
/// tree actually uses resolved: a file-local `const K = 'KEY'`, and a
/// same-file `String _env(String key)` accessor called with literals.
Set<String> dotenvKeysRead() {
  final consts = <String, String>{};
  final constDecl = RegExp(r"const\s+(?:String\s+)?(\w+)\s*=\s*'([A-Z0-9_]+)'\s*;");
  final files = dartFiles(_libRoot);
  for (final f in files) {
    for (final m in codeMatches(f.readAsStringSync(), constDecl)) {
      consts[m.group(1)!] = m.group(2)!;
    }
  }

  final keys = <String>{};
  for (final f in files) {
    final src = f.readAsStringSync();
    final blanked = blankNonCode(src);
    for (final m in RegExp(r'dotenv\.env\[').allMatches(blanked)) {
      final close = src.indexOf(']', m.end);
      expect(close, greaterThan(m.end),
          reason: 'unterminated dotenv.env[ in ${f.path}');
      final index = src.substring(m.end, close).trim();
      final literal = RegExp(r"^'([A-Z0-9_]+)'$").firstMatch(index);
      if (literal != null) {
        keys.add(literal.group(1)!);
        continue;
      }
      if (consts.containsKey(index)) {
        keys.add(consts[index]!);
        continue;
      }
      // A parameter: the enclosing accessor's own literal call sites are the
      // keys. Anything this cannot resolve is a read the guard would silently
      // miss, so it fails rather than passing over it.
      final accessor =
          RegExp(r'String\s+(\w+)\(String\s+\w+\)\s*\{').allMatches(src)
              .where((a) => a.start < m.start)
              .toList();
      expect(accessor, isNotEmpty,
          reason: 'dotenv.env[$index] in ${f.path} is indexed by neither a '
              'literal, a const, nor an accessor parameter — name the key so '
              'the release-reachability guard can see it.');
      final name = accessor.last.group(1)!;
      final calls = RegExp("$name\\('([A-Z0-9_]+)'\\)").allMatches(src);
      expect(calls, isNotEmpty,
          reason: '$name(...) in ${f.path} is never called with a literal key');
      for (final c in calls) {
        keys.add(c.group(1)!);
      }
    }
  }
  return keys;
}

/// Keys main.dart bridges from a `--dart-define` into dotenv. Both halves are
/// required: reading the define without merging it, or merging a name that is
/// never read, leaves the key unreachable just the same.
Set<String> bridgedKeys() {
  final main = File('lib/main.dart').readAsStringSync();
  final read = RegExp(r"String\.fromEnvironment\('([A-Z0-9_]+)'")
      .allMatches(main)
      .map((m) => m.group(1)!)
      .toSet();
  final merged = RegExp(r"'([A-Z0-9_]+)=\$")
      .allMatches(main)
      .map((m) => m.group(1)!)
      .toSet();
  return read.intersection(merged);
}

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

  group('every gate is reachable in a release build', () {
    // Release builds never load `.env.development` (pinned in
    // architecture_guards_test.dart), so main.dart's String.fromEnvironment
    // bridge is the ONLY way a value reaches dotenv in production. A key read
    // at runtime but absent from that bridge can never be set, whatever the
    // deploy passes — which is how OFF_ROUTE_ESCALATION_ENABLED and
    // ADAPTIVE_FITNESS_GATE sat unflippable behind their sign-offs.
    test('every dotenv key read under lib/ is bridged from a --dart-define', () {
      final read = dotenvKeysRead();
      expect(read.length, greaterThanOrEqualTo(12),
          reason: 'the dotenv-read scan found only ${read.length} keys — its '
              'shape assumptions broke and it is enforcing nothing.');

      final missing = read.difference(bridgedKeys()).toList()..sort();
      expect(missing, isEmpty,
          reason: 'dotenv key(s) read at runtime but absent from main.dart\'s '
              '--dart-define bridge: ${missing.join(', ')}. Release builds do '
              'not read .env.development, so these are unreachable in '
              'production. Add a String.fromEnvironment const and the matching '
              'entry to the loadFromString list.');
    });
  });
}
