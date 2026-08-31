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

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/adaptive_fitness_flag.dart';
import '../lib/env_flag.dart';
import '../lib/nearby_flag.dart';
import '../lib/off_route_flag.dart';
import '../lib/weigh_in_flag.dart';
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
      'lib/weigh_in_flag.dart': 'weighInEnabled',
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

  group('every gate fails closed on an uninitialised dotenv', () {
    // `dotenv.env` throws NotInitializedError until something loads it, so an
    // unguarded gate does not report "off" — it throws, and what happens next
    // is the caller's error handling rather than the flag's answer. main.dart
    // loads dotenv before runApp, so this is unreachable in the app today; it
    // is reachable from a test, from a second entry point, and from any future
    // caller that reads a gate before the bootstrap has run.
    final gates = <String, bool Function()>{
      'nearbyRunnersGate': () => nearbyRunnersGate,
      'offRouteEscalationGate': () => offRouteEscalationGate,
      'adaptiveFitnessGate': () => adaptiveFitnessGate,
      'weighInGate': () => weighInGate,
    };

    setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
    tearDownAll(() => dotenv.clean());

    for (final gate in gates.entries) {
      test('${gate.key} returns false rather than throwing', () {
        dotenv.clean();
        expect(dotenv.isInitialized, isFalse,
            reason: 'the precondition this test exists for must hold');
        expect(gate.value(), isFalse);
      });
    }

    test('and each gate still turns on once dotenv carries an affirmative', () {
      // Without this the group above would pass against four gates hard-wired
      // to false.
      dotenv.clean();
      dotenv.loadFromString(
        envString: [
          '$kNearbyRunnersEnvKey=yes',
          '$kOffRouteEscalationEnvKey=yes',
          '$kAdaptiveFitnessGateEnvKey=yes',
          '$kWeighInEnvKey=yes',
        ].join('\n'),
      );
      for (final gate in gates.entries) {
        expect(gate.value(), isTrue, reason: '${gate.key} should be on');
      }
    });
  });

  group('a gate\'s env read lives in its own flag module', () {
    // The guard the asymmetry actually needed. Three of the four gates spelled
    // their own `dotenv.env[...]` read at the call site, in two different
    // fail-closed idioms, and two of those were duplicates of each other — so
    // "does this key fail closed" was a question about five call sites rather
    // than about one module. A fifth caller copying the read is what would
    // reintroduce it.
    const owners = <String, String>{
      'ENABLE_NEARBY_RUNNERS': 'lib/nearby_flag.dart',
      'OFF_ROUTE_ESCALATION_ENABLED': 'lib/off_route_flag.dart',
      'ADAPTIVE_FITNESS_GATE': 'lib/adaptive_fitness_flag.dart',
      'WEIGH_IN_GATE': 'lib/weigh_in_flag.dart',
    };

    for (final owner in owners.entries) {
      test('${owner.key} is read only by ${owner.value}', () {
        final readers = <String>[];
        for (final f in dartFiles(_libRoot)) {
          final src = f.readAsStringSync();
          // `blankNonCode` empties string BODIES, so the key has to be read
          // out of the raw source at a position the blanked copy calls code —
          // exactly how `dotenvKeysRead` resolves an index.
          final blanked = blankNonCode(src);
          for (final m in RegExp(r'dotenv\.env\[').allMatches(blanked)) {
            final close = src.indexOf(']', m.end);
            if (close <= m.end) continue;
            if (src.substring(m.end, close).trim() == "'${owner.key}'") {
              readers.add(f.path);
            }
          }
        }
        // The owner reads it through its own key const, not a literal, so a
        // literal read anywhere is by definition somebody else's copy.
        expect(readers, isEmpty,
            reason: '${owner.key} is read directly in ${readers.join(', ')}. '
                'Read the gate getter from ${owner.value} instead — a gate '
                'spelled at the call site is a gate whose fail-closed guard '
                'is only as good as that call site.');
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

  group('the bridge wires each define to its own key', () {
    // `bridgedKeys()` above intersects the set of names READ with the set of
    // names MERGED, which catches a key that is only half-bridged. It cannot
    // see a key wired to the WRONG variable: `'WEIGH_IN_GATE=$tileUrlTemplateDef'`
    // leaves both sets containing WEIGH_IN_GATE while the value a release
    // build actually receives is somebody else's. The gates are exactly the
    // flags nobody exercises before shipping, so nothing else would notice.
    late Map<String, String> consts;
    late Map<String, String> merges;

    setUpAll(() {
      final main = File('lib/main.dart').readAsStringSync();
      consts = <String, String>{
        for (final m in RegExp(
                "const\\s+(\\w+)\\s*=\\s*\\n?\\s*String\\.fromEnvironment\\('([A-Z0-9_]+)'\\)")
            .allMatches(main))
          m.group(1)!: m.group(2)!,
      };
      merges = <String, String>{
        for (final m in RegExp(r"'([A-Z0-9_]+)=\$(\w+)'").allMatches(main))
          m.group(1)!: m.group(2)!,
      };
    });

    test('the extractors still see the bridge they are reading', () {
      expect(consts.length, greaterThanOrEqualTo(15),
          reason: 'only ${consts.length} String.fromEnvironment consts found '
              'in main.dart — the extractor broke and every check below is '
              'vacuous');
      expect(merges.length, greaterThanOrEqualTo(15),
          reason: 'only ${merges.length} dotenv merge entries found');
    });

    test('every merged key comes from the define of the same name', () {
      final crossed = <String>[];
      for (final entry in merges.entries) {
        final source = consts[entry.value];
        if (source == null) {
          crossed.add('${entry.key} is merged from ${entry.value}, which is '
              'not a String.fromEnvironment const');
        } else if (source != entry.key) {
          crossed.add('${entry.key} is merged from ${entry.value}, which '
              'reads $source');
        }
      }
      expect(crossed, isEmpty,
          reason: 'a define wired to the wrong key hands a release build '
              'somebody else\'s value while both halves of the reachability '
              'scan still see the name:\n${crossed.join('\n')}');
    });

    test('every declared define is actually merged', () {
      final unused = consts.entries
          .where((e) => merges[e.value] != e.key)
          .map((e) => '${e.value} (const ${e.key})')
          .toList()
        ..sort();
      expect(unused, isEmpty,
          reason: 'these are read from --dart-define and never reach dotenv, '
              'so passing them at build time does nothing: '
              '${unused.join(', ')}');
    });

    // Named one at a time because each is a documented sign-off gate or a
    // deploy override, and each was unreachable in a release build at some
    // point (decisions § 709). A set-level assertion would go on passing if
    // one of them quietly left the bridge.
    for (final key in const [
      'ENABLE_NEARBY_RUNNERS',
      'OFF_ROUTE_ESCALATION_ENABLED',
      'ADAPTIVE_FITNESS_GATE',
      'WEIGH_IN_GATE',
      'TILE_URL_TEMPLATE',
      'USDA_FDC_API_KEY',
    ]) {
      test('$key survives into a release build', () {
        expect(merges.containsKey(key), isTrue,
            reason: '$key is not merged into dotenv — a release build cannot '
                'read it however the deploy passes it');
        expect(consts[merges[key]], key,
            reason: '$key is merged from a const that reads a different key');
      });
    }
  });


  group('the nearby gate reads its own flag, fail-closed', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      dotenv.loadFromString(isOptional: true);
    });
    tearDown(() => dotenv.env.remove(kNearbyRunnersEnvKey));

    // The one gate with an env-reading accessor of its own. Driven end to end
    // rather than by reading its source: `yes` is the value that separates
    // the shared parser from the narrow copy the audit found, and the whole
    // surface is Art 9-adjacent person-location.
    test('unset is off, `yes` is on, junk is off', () {
      expect(nearbyRunnersGate, isFalse,
          reason: 'an unset sign-off gate must fail closed');
      dotenv.env[kNearbyRunnersEnvKey] = 'yes';
      expect(nearbyRunnersGate, isTrue);
      dotenv.env[kNearbyRunnersEnvKey] = 'YES';
      expect(nearbyRunnersGate, isTrue, reason: 'case-insensitive');
      dotenv.env[kNearbyRunnersEnvKey] = ' on ';
      expect(nearbyRunnersGate, isTrue, reason: 'trimmed');
      for (final junk in const ['enabled', '0', 'false', 'y', '']) {
        dotenv.env[kNearbyRunnersEnvKey] = junk;
        expect(nearbyRunnersGate, isFalse,
            reason: '"$junk" must never open a location surface');
      }
    });
  });
}
