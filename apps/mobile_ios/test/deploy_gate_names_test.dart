import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every cross-platform fail-closed deploy gate's env-var NAME, on both
/// platforms at once. Dart mirror of the web
/// `safety/deploy_gate_names.test.ts`.
///
/// The convention every mobile gate's header states is "web spells it
/// `PUBLIC_<X>`, mobile drops the web-only `PUBLIC_` prefix". It is an
/// operational claim rather than a style one: an operator flipping a gate for a
/// release reads one name and sets the other, so a pair whose STEMS differ
/// means they have signed one platform off and not the other, silently, in
/// exactly the direction the gate exists to prevent.
///
/// Nothing tested it, and it turned out to be false for one of the four. Web
/// reads `PUBLIC_WEIGH_IN_ENABLED`; mobile reads `WEIGH_IN_GATE`. The Dart
/// header meanwhile named `PUBLIC_WEIGH_IN_GATE`, a variable no file in the
/// repo reads or sets, so the one place a reader could have learned about the
/// exception told them the opposite (decisions § 1354).
///
/// The exception is therefore DECLARED and re-measured rather than the
/// convention being weakened to fit it, and the census walks for gate modules
/// rather than listing them — a list of names goes stale the same way the
/// header did.

/// Dart flag module -> its web counterpart.
const Map<String, String> _gates = {
  'lib/off_route_flag.dart': '../web/src/lib/safety/off_route_flag.ts',
  'lib/weigh_in_flag.dart': '../web/src/lib/runs/weigh_in_flag.ts',
  'lib/nearby_flag.dart': '../web/src/lib/social/nearby_flag.ts',
  'lib/adaptive_fitness_flag.dart': '../web/src/lib/training/adaptive_fitness_flag.ts',
};

/// Gates whose two names do NOT satisfy the convention, and why. An entry that
/// has stopped being a violation fails, so this can only shrink.
const Map<String, String> _knownExceptions = {
  'lib/weigh_in_flag.dart':
      'the stems differ, not just the prefix: PUBLIC_WEIGH_IN_ENABLED against '
          'WEIGH_IN_GATE. Both headers now say so outright (decisions § 1354).',
};

/// The shared parser, not a gate: it reads no env key of its own.
const String _parser = 'lib/env_flag.dart';

String _read(String path) => File(path).readAsStringSync();

/// The `PUBLIC_*` env key a web flag module reads.
String? _webKey(String source) =>
    RegExp(r'\benv\.(PUBLIC_[A-Z0-9_]+)\b').firstMatch(source)?.group(1);

/// The dart-define / dotenv key a Dart flag module reads, taken from its
/// `k…EnvKey` constant rather than from a `dotenv.env[...]` subscript, because
/// the modules deliberately name the key once and subscript with the constant.
String? _dartKey(String source) =>
    RegExp(r"const String k\w*EnvKey = '([A-Z0-9_]+)';").firstMatch(source)?.group(1);

void main() {
  test('the key readers find the key in every gate module on both platforms', () {
    // Without this, a reader that stopped matching would report every gate as
    // having no key and the convention test below would pass vacuously.
    for (final gate in _gates.entries) {
      expect(_dartKey(_read(gate.key)), isNotNull,
          reason: 'no k…EnvKey constant found in ${gate.key}');
      expect(_webKey(_read(gate.value)), isNotNull,
          reason: 'no PUBLIC_ key found in ${gate.value}');
    }
  });

  test('every deploy gate follows the dropped-prefix convention or is a declared exception', () {
    for (final gate in _gates.entries) {
      final dart = _dartKey(_read(gate.key));
      final web = _webKey(_read(gate.value));
      final follows = web == 'PUBLIC_$dart';
      if (_knownExceptions.containsKey(gate.key)) {
        expect(follows, false,
            reason: '${gate.key} reads $dart and ${gate.value} reads $web, which now DO '
                'satisfy the convention — delete the _knownExceptions entry, which is '
                'cover for nothing and hides the next one.');
        continue;
      }
      expect(follows, true,
          reason: '${gate.key} reads $dart but ${gate.value} reads $web. The convention '
              'is that mobile drops the web-only PUBLIC_ prefix and nothing else, so an '
              'operator who sets one has set both. If the difference is deliberate, '
              'declare it in _knownExceptions with the reason and say so in both headers '
              '— an undeclared one means a gate signed off on one platform and open on '
              'the other.');
    }
  });

  test('a name the repo reads nowhere is never stated as the counterpart', () {
    // The defect this file came from: the Dart header named
    // `PUBLIC_WEIGH_IN_GATE`, which no file reads or sets, so the exception was
    // documented as its opposite.
    final live = _gates.values.map((p) => _webKey(_read(p))).whereType<String>().toSet();
    for (final gate in _gates.entries) {
      for (final path in [gate.key, gate.value]) {
        for (final m in RegExp(r'\bPUBLIC_[A-Z0-9_]+\b').allMatches(_read(path))) {
          expect(live.contains(m.group(0)), true,
              reason: '$path names ${m.group(0)}, which no web gate module reads. A '
                  'counterpart name that exists nowhere is worse than none: it reads '
                  'as instructions.');
        }
      }
    }
  });

  test('the gate census names every Dart flag module in the tree', () {
    // `_gates` is a map, so it can go stale — a fifth mobile gate would simply
    // not be measured. This walks for `*_flag.dart` and fails on one the map
    // omits, the same population rule env_flag_test.dart applies to the parse.
    final found = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('_flag.dart'))
        .toList()
      ..sort();
    expect(found.length >= _gates.length + 1, true,
        reason: 'the flag-module walk stopped matching — a walk that finds nothing '
            'reports no gaps');
    for (final path in found) {
      if (path == _parser) continue;
      expect(_gates.containsKey(path), true,
          reason: '$path is a deploy gate that _gates does not carry, so its env-var '
              'name is compared with nothing. Add it with its web counterpart.');
    }
    // Every declared pair must still exist on the web side, or the comparison
    // above is against a file that moved.
    for (final web in _gates.values) {
      expect(File(web).existsSync(), true, reason: '$web no longer exists');
    }
  });
}
