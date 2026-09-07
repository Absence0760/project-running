// One reader for a timestamp column in the [OfflineSyncStore] family.
//
// The read used to exist nineteen times across the family in five spellings
// (decisions § 1289): six byte-identical `_parseTs` statics, a `_parseTime`
// and two inline `startedAt` getters that dropped the UTC normalisation, seven
// `fromJson` clock reads that cast the field before parsing it, and gear's
// `_parseDate` (now the shared `parseCalendarDate`), whose MISSING
// normalisation is load-bearing because its
// columns are `date`. Nothing in the tree compared any of them, which is how a
// helper of that name came to mean two different things in one file family.
//
// So: inside the family, `DateTime.parse` / `DateTime.tryParse` may appear only
// in `parseIsoStrict` itself, or on a site that states in a `zone-verbatim:`
// marker why it must keep the parsed value's own zone. The marker is local
// rather than a file allowlist because two of the files carry both shapes, and
// an allowlist keyed on the file would go on covering the next reader added to
// it.
//
// `parseIsoStrict` is where the raw parse lives since § 1344, because
// `tryParse` ROLLS OVER an out-of-range component rather than refusing it
// (`2026-06-32` is the 2nd of July) and the family needs that refused in one
// place, not in each reader. `parseServerTimestamp` and `parseCalendarDate`
// both go through it and differ only in the `.toUtc()` — which gear's `date`
// columns must not have.
//
// Since § 1377 that reader lives in `core_models`, not in this family, because
// the same rollover reaches the stores' NEIGHBOURS — `local_run_store`,
// `social_service`, `race_controller` — which are not stores and could never
// be derived from `extends OfflineSyncStore<`. So the family carries zero raw
// parses now, and the owner-file claim below reads the package file.
//
// The family is DERIVED from `extends OfflineSyncStore<`, not listed, so an
// eighth store is covered the day it lands rather than the day someone
// remembers to register it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

const _marker = 'zone-verbatim:';

const _shared = 'lib/offline_sync_store.dart';

/// Where the one raw parse in the tree's stored-date-time path lives.
const _owner = '../../packages/core_models/lib/src/iso_parse.dart';

final _parseCall = RegExp(r'DateTime\.(try)?[Pp]arse\(');

final _topLevelReader = RegExp(r'^DateTime\??\s+(\w+)\(');

/// `offline_sync_store.dart` plus every store that extends it.
List<File> _familyFiles() {
  final shared = File(_shared);
  final out = <File>[if (shared.existsSync()) shared];
  for (final f in dartFiles(_root)) {
    if (f.path == _shared) continue;
    if (f.readAsStringSync().contains('extends OfflineSyncStore<')) out.add(f);
  }
  return out;
}

/// The files the rule covers: the store family, plus every file under [_root]
/// that reads a stored date-time through the strict reader.
///
/// The second half is what carries the rule past a family it could never
/// have described — `local_run_store`, `social_service` and `race_controller`
/// are not stores and no derivation from `extends OfflineSyncStore<` reaches
/// them (decisions § 1377). A file joins by USING the reader rather than by
/// being listed, so the next file a lane hardens is covered the day it lands;
/// and having joined, it may not keep a raw parse beside the checked one,
/// which is the regression this exists to refuse. Dropping the last strict
/// read to leave again is caught by the call-site floor below, not here.
List<File> _coveredFiles() {
  final out = _familyFiles();
  final seen = out.map((f) => f.path).toSet();
  for (final f in dartFiles(_root)) {
    if (seen.contains(f.path)) continue;
    if (blankNonCode(f.readAsStringSync()).contains('parseIsoStrict')) {
      out.add(f);
    }
  }
  return out;
}

/// The nearest top-level `DateTime …(` declaration at or above [line], or ''.
String _enclosingReader(List<String> lines, int line) {
  for (var i = line; i >= 0; i--) {
    final m = _topLevelReader.firstMatch(lines[i]);
    if (m != null) return m.group(1)!;
  }
  return '';
}

void main() {
  test('every covered file reads a date-time through one reader', () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    // The family was seven stores plus the base when this guard landed, and
    // three more files joined by using the reader in § 1377. A count that has
    // COLLAPSED means a derivation stopped matching, and a guard scanning
    // nothing passes for the wrong reason.
    expect(_familyFiles().length, greaterThanOrEqualTo(8),
        reason: 'derived family is ${_familyFiles().map((f) => f.path)}');
    final files = _coveredFiles();
    expect(files.length, greaterThanOrEqualTo(14),
        reason: 'covered set is ${files.map((f) => f.path)}');

    final offenders = <String>[];
    for (final file in files) {
      final raw = file.readAsStringSync();
      final code = blankNonCode(raw);
      final rawLines = raw.split('\n');
      final codeLines = code.split('\n');
      for (var i = 0; i < codeLines.length; i++) {
        if (!_parseCall.hasMatch(codeLines[i])) continue;
        final marked = rawLines[i].contains(_marker) ||
            (i > 0 && rawLines[i - 1].contains(_marker));
        if (marked) continue;
        offenders.add('${file.path}:${i + 1}: ${rawLines[i].trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'read the column through parseServerTimestamp / '
            'parseIsoStrictValue, or state a `$_marker` reason why this site '
            'must keep the parsed zone:\n${offenders.join('\n')}');
  });

  test('the strict reader is still called where those files were hardened',
      () {
    // The covered-set floor above catches a file leaving the set outright.
    // This catches the subtler half: a file that keeps ONE strict read as a fig
    // leaf while reverting the rest, which leaves the set the same size and the
    // rule doing nothing. Anchored on the COUNT for the reason § 1344 anchored
    // its own — removing the check cannot remove the expectation. Seventeen
    // when § 1377 landed: `social_service` 11, `race_controller` 3,
    // `offline_sync_store` 2 (the two named readers), `local_run_store` 1.
    // Twenty-four since § 1430 added `backup` 4, `watch_ingest_queue` 2 and
    // `training_service` 1.
    var sites = 0;
    for (final f in dartFiles(_root)) {
      final code = blankNonCode(f.readAsStringSync());
      sites += RegExp(r'parseIsoStrict(Value|Required)?\(')
          .allMatches(code)
          .length;
    }
    expect(sites, greaterThanOrEqualTo(22),
        reason: 'a file that stops calling the strict reader leaves the '
            'covered set, so this floor is what keeps it in');
  });

  test('the shared readers exist and the family actually uses them', () {
    final shared = File(_shared).readAsStringSync();
    expect(
        shared.contains(
            'DateTime? parseServerTimestamp(dynamic v) => '
            'parseIsoStrictValue(v)?.toUtc();'),
        isTrue,
        reason: 'the .toUtc() IS what separates the two readers');
    expect(
        shared.contains(
            'DateTime? parseCalendarDate(dynamic v) => parseIsoStrictValue(v);'),
        isTrue,
        reason: 'a `date` column must NOT be normalised to UTC — § 1344');
    expect(shared.contains('DateTime storedClockOrEpoch(dynamic v) =>'), isTrue);

    var timestampSites = 0;
    var dateSites = 0;
    var clockSites = 0;
    for (final file in _familyFiles()) {
      final code = blankNonCode(file.readAsStringSync());
      timestampSites += 'parseServerTimestamp('.allMatches(code).length;
      dateSites += 'parseCalendarDate('.allMatches(code).length;
      clockSites += 'storedClockOrEpoch('.allMatches(code).length;
    }
    // Declarations included: 16 timestamp reads + 1 declaration, 3 date reads
    // + 1 declaration, 7 clock reads + 1 declaration when this landed. A drop
    // to the declarations alone means a store went back to open-coding the
    // read past this guard's blind spot.
    expect(timestampSites, greaterThanOrEqualTo(12));
    expect(dateSites, greaterThanOrEqualTo(4));
    expect(clockSites, greaterThanOrEqualTo(8));
  });

  test('the raw parse exists exactly once in the tree, inside its owner', () {
    // The claim `parseIsoStrict` is built to make: every reader that goes
    // through it is range-checked because there is nowhere else the text can
    // be parsed. A second call anywhere in the owner file — a "quick"
    // unchecked read beside the checked one — is what this refuses, and it is
    // anchored on the COUNT so removing the check cannot remove the
    // expectation with it.
    expect(File(_owner).existsSync(), isTrue,
        reason: '$_owner has moved; this guard would check nothing');
    final code = blankNonCode(File(_owner).readAsStringSync());
    final lines = code.split('\n');
    final sites = <int>[
      for (var i = 0; i < lines.length; i++)
        if (_parseCall.hasMatch(lines[i])) i,
    ];
    expect(sites, hasLength(1),
        reason: 'raw parse sites in $_owner: '
            '${sites.map((i) => i + 1).toList()}');
    expect(_enclosingReader(lines, sites.single), 'parseIsoStrict');
  });
}
