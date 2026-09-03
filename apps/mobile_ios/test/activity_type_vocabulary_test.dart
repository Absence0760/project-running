// The mobile half of the one `runs.activity_type` vocabulary: SQL CHECK →
// `ActivityType` enum → one ARB key per value in all SEVEN catalogues → no
// screen naming an activity any other way.
//
// Mobile carried THREE vocabularies for five values. Two were ARB-backed and
// disagreed within a locale — German `run` was "Laufen" (`prefsActivityRun`)
// and "Lauf" (`feedActivityRun`), Spanish `run` "Correr" and "Carrera",
// Spanish `walk` "Caminar" and "Caminata", French `hike` "Randonnée" and
// "Rando" — and both omitted `stroller`. The third was `ActivityType.label`,
// a hardcoded English getter reached from eight render sites (run detail, the
// runs filter chips, the add-run picker, two lock-screen notification titles,
// the run-list tile's title + semantics label, and the share card), so a
// German runner's notification read "Run" and their list rows "run".
//
// Web's `activity_type_vocabulary.test.ts` is the mirror of this file. The two
// share the value set (both derive it from the same CHECK constraint) and the
// canonical words per locale; the KEY names differ by convention — web carries
// dotted `activityType.run`, mobile the camelCase `activityTypeRun`.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show ActivityType;
import 'package:flutter_test/flutter_test.dart';


const _localeTags = ['en', 'de', 'fr', 'es', 'ja', 'pt', 'pt_BR'];

Map<String, dynamic> _readArb(String tag) =>
    jsonDecode(File('lib/l10n/app_$tag.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The authoritative value set, read out of the migration rather than restated
/// here — a migration that widens the CHECK must fail this file until the
/// catalogues catch up.
Set<String> _checkValues() {
  final dir = Directory('../backend/supabase/migrations');
  final re = RegExp(
    r'constraint\s+runs_activity_type_check\s*\n?\s*check\s*\(\s*activity_type\s+in\s*\(([^)]*)\)',
    caseSensitive: false,
  );
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  Set<String>? found;
  for (final f in files) {
    final m = re.firstMatch(f.readAsStringSync());
    if (m == null) continue;
    found = RegExp(r"'([^']+)'")
        .allMatches(m.group(1)!)
        .map((v) => v.group(1)!)
        .toSet(); // later migration wins
  }
  expect(found, isNotNull,
      reason: 'no migration declares runs_activity_type_check');
  return found!;
}

/// `activityTypeRun` for `run`.
String _keyFor(String value) =>
    'activityType${value[0].toUpperCase()}${value.substring(1)}';

void main() {
  _leafVocabularyTests();

  test('the ActivityType enum is exactly the CHECK-constraint value set', () {
    final sql = _checkValues();
    expect(sql, isNotEmpty,
        reason: 'parsed an EMPTY value set out of the CHECK constraint');
    expect(
      ActivityType.values.map((a) => a.name).toSet(),
      sql,
      reason: 'ActivityType drifted from runs_activity_type_check',
    );
  });

  test('every value has a non-empty label in every locale, and no locale '
      'names two values the same', () {
    final sql = _checkValues().toList()..sort();
    var checked = 0;
    for (final tag in _localeTags) {
      final arb = _readArb(tag);
      final seen = <String, String>{};
      for (final value in sql) {
        final key = _keyFor(value);
        final label = arb[key];
        expect(
          label is String && label.trim().isNotEmpty,
          isTrue,
          reason: '$tag has no non-empty label for activity_type "$value" '
              '($key). A missing key is a runtime English leak.',
        );
        final clash = seen[label as String];
        expect(clash, isNull,
            reason: '$tag labels both "$clash" and "$value" as "$label"');
        seen[label] = value;
        checked++;
      }
    }
    // Assert the population, not only the property — a walk that reached no
    // catalogue would pass every expectation above.
    expect(checked, _localeTags.length * sql.length,
        reason: 'checked $checked labels, expected '
            '${_localeTags.length * sql.length}');
  });

  // ── No catalogue re-grows a per-surface vocabulary ────────────────────────
  //
  // A duplicate is any key OUTSIDE the canonical prefix that names one of the
  // five values in the `<surface>Activity<Value>` shape both originals used.
  // Matching key NAMES is the only signal available (two ARB entries spelling
  // `hike` differently are both valid strings), so the matcher earns a
  // fixture table in both directions.

  final duplicateKey = RegExp(
    r'^(?!activityType)[a-z][A-Za-z]*Activity('
    '${ActivityType.values.map((a) => a.name).join('|')}'
    r')$',
    caseSensitive: false,
  );

  test('the duplicate-vocabulary matcher flags a surface-scoped value key and '
      'spares the canonical one', () {
    const fixtures = <String, bool>{
      // The two that existed, in both spellings that disagreed.
      'prefsActivityRun': true,
      'prefsActivityHike': true,
      'feedActivityRun': true,
      'feedActivityCycle': true,
      // A surface nobody has built yet, same shape.
      'someNewScreenActivityStroller': true,
      // The canonical keys must be spared or the guard eats the fix.
      'activityTypeRun': false,
      'activityTypeStroller': false,
      // `all` / `lift` are feed SCOPES, not activity_type values.
      'feedActivityAll': false,
      'feedActivityLift': false,
      'discoverActivityAll': false,
      // The body-metrics activity LEVEL shares the word and must not be swept.
      'bodyMetricsActivityLevel': false,
      'activitySedentary': false,
      // Not the shape: the value is not the whole tail.
      'feedActivityRunSplits': false,
      'challengesMetricActivityCount': false,
    };
    fixtures.forEach((key, flagged) {
      expect(duplicateKey.hasMatch(key), flagged,
          reason: 'must ${flagged ? "flag" : "spare"} $key');
    });
  });

  test('no catalogue carries a second, surface-scoped activity vocabulary', () {
    var keysScanned = 0;
    for (final tag in _localeTags) {
      final keys = _readArb(tag)
          .keys
          .where((k) => !k.startsWith('@'))
          .toList();
      keysScanned += keys.length;
      final strays = keys.where(duplicateKey.hasMatch).toList();
      expect(strays, isEmpty,
          reason: '$tag carries surface-scoped activity labels $strays. '
              'Resolve through activityTypeLabel() instead — a second '
              'vocabulary is how the originals drifted apart.');
    }
    expect(keysScanned, greaterThan(7 * 1000),
        reason: 'scanned only $keysScanned keys across all catalogues');
  });

  // ── No screen hand-capitalises an identifier in place of a label ──────────
  //
  // Web's sweep lives in `workout_labels.test.ts`; this is the Dart one, and it
  // must catch a shape web's cannot. The mobile defect was written as a STRING
  // TEMPLATE with no `+`:
  //   return '${s[0].toUpperCase()}${s.substring(1)}';
  // and through a one-letter alias, so a matcher keyed on an `activity`-ish
  // identifier would have spared the very line it exists for. The idiom is
  // matched everywhere instead, and each legitimate hit is named.

  final titleCaseIdiom = RegExp(
    r'(?:\.charAt\(0\)|\[0\])\s*\.toUpperCase\(\)'
    r'[\s\S]{0,60}?(?:\.substring\(1\)|\.slice\(1\))',
  );

  test('the hand-capitalisation matcher flags the idiom by shape, not by name',
      () {
    const fixtures = <String, bool>{
      // The exact pre-fix lines, one-letter alias and template form and all.
      r"return '${s[0].toUpperCase()}${s.substring(1)}';": true,
      r'return a[0].toUpperCase() + a.substring(1);': true,
      // Renamed variable, same shape.
      r'return zz[0].toUpperCase() + zz.substring(1);': true,
      // Spread across lines.
      'return kind[0].toUpperCase()\n        + kind.substring(1);': true,
      // Spared: an initial for an avatar capitalises nothing back on.
      r"final initial = name[0].toUpperCase();": false,
      r"parts.map((p) => p[0].toUpperCase()).join()": false,
      // Spared: upper-casing the whole string is a display transform.
      r'return code.toUpperCase();': false,
      // Spared: the fix.
      r'return activityTypeLabelFor(l10n, r.activityType);': false,
      r'return name.substring(1);': false,
    };
    fixtures.forEach((src, flagged) {
      expect(titleCaseIdiom.hasMatch(src), flagged,
          reason: 'must ${flagged ? "flag" : "spare"} ${jsonEncode(src)}');
    });
  });

  test('no lib/ source title-cases a token in place of a resolved label', () {
    // file -> why it cannot resolve a catalogue label instead.
    const allowed = <String, String>{
      // A snake_case settings-bag KEY rendered as a fallback label on the
      // device-override registry, behind the l10n `labelFor` switch. The key
      // space is open (any bag key a newer client writes), so no catalogue can
      // cover it — documented as intentionally-English in CLAUDE.md.
      // A FIT file's sub_sport is free-form vendor text with no closed value
      // domain, so no catalogue can cover it. Web allowlists the identical
      // line on `/runs/[id]` for the identical reason.
      'lib/screens/run_detail_screen.dart': 'Garmin FIT sub_sport',
      // `_toTitle` is the LAST-RESORT fallback under seven settings-bag label
      // switches whose value spaces are open (map style, pace format, …). The
      // activity-type switch that used to sit beside them is gone — it had a
      // closed domain, so it now resolves a real label.
      'lib/screens/settings_preferences_screen.dart':
          'open settings-bag value spaces, behind seven l10n switches',
    };

    final hits = <String, List<String>>{};
    var scanned = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Generated catalogues are not render sites.
      if (f.path.contains('/l10n/gen/')) continue;
      scanned++;
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final window = lines.skip(i).take(2).join('\n');
        if (!titleCaseIdiom.hasMatch(window)) continue;
        (hits[f.path] ??= []).add('${f.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(scanned, greaterThan(200),
        reason: 'the walk reached only $scanned files');

    final unexplained =
        hits.keys.where((k) => !allowed.containsKey(k)).toList()..sort();
    expect(
      unexplained.expand((k) => hits[k]!).toList(),
      isEmpty,
      reason: 'Title-casing a database identifier prints English on a '
          'localized screen. An activity type goes through '
          'activityTypeLabel(); anything else needs an entry in `allowed` '
          'saying why it cannot.',
    );
    // A stale allowlist means the guard measures less than it claims.
    allowed.forEach((path, reason) {
      expect(hits.containsKey(path), isTrue,
          reason: 'allowed entry $path ($reason) no longer matches — drop it');
    });
  });
}

/// The vocabulary is a LEAF, so a pure parser can reach it without dragging a
/// widget toolkit in behind it. decisions § 1013.
void _leafVocabularyTests() {
  test('the enum lives in core_models, which has no Flutter dependency', () {
    final leaf =
        File('../../packages/core_models/lib/src/activity_type.dart');
    expect(leaf.existsSync(), isTrue,
        reason: 'the ActivityType leaf moved — check_constraint_unions.mjs '
            'names this exact path as the rail for runs.activity_type, so a '
            'move needs the registry edited in the same change');
    // An IMPORT, not a mention — the file's own header explains why the icon
    // getter could not travel with it, and names the library to do so.
    expect(
      RegExp(r"^import 'package:flutter/", multiLine: true)
          .hasMatch(leaf.readAsStringSync()),
      isFalse,
      reason: 'core_models has no Flutter dependency at all; the icon getter '
          'is an extension in activity_type_labels.dart for this reason',
    );

    final pubspec =
        File('../../packages/core_models/pubspec.yaml').readAsStringSync();
    final deps = pubspec.substring(
      pubspec.indexOf('dependencies:'),
      pubspec.contains('dev_dependencies:')
          ? pubspec.indexOf('dev_dependencies:')
          : pubspec.length,
    );
    expect(deps.contains('flutter:'), isFalse,
        reason: 'core_models took a Flutter dependency, which is what kept the '
            'vocabulary out of it');
  });

  test('the CSV importer reaches the vocabulary without a widget toolkit', () {
    // It used to `import 'preferences.dart' show ActivityType`, and
    // preferences.dart imports package:flutter/material.dart for a SharedPrefs
    // cache and an IconData getter. Retyping the five values instead would
    // have made a second rail against `runs_activity_type_check` that the
    // constraint-union guard does not know to read.
    final src = File('lib/csv_run_importer.dart').readAsStringSync();
    expect(src.contains('ActivityType'), isTrue,
        reason: 'the importer no longer names the vocabulary — re-anchor');
    expect(src.contains("preferences.dart"), isFalse);
    expect(src.contains('package:flutter/material.dart'), isFalse);
  });
}
