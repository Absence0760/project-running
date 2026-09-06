// One reader for a timestamp column in the [OfflineSyncStore] family.
//
// The read used to exist nineteen times across the family in five spellings
// (decisions § 1289): six byte-identical `_parseTs` statics, a `_parseTime`
// and two inline `startedAt` getters that dropped the UTC normalisation, seven
// `fromJson` clock reads that cast the field before parsing it, and gear's
// `_parseDate`, whose MISSING normalisation is load-bearing because its
// columns are `date`. Nothing in the tree compared any of them, which is how a
// helper of that name came to mean two different things in one file family.
//
// So: inside the family, `DateTime.parse` / `DateTime.tryParse` may appear only
// in `parseServerTimestamp` itself, or on a site that states in a
// `zone-verbatim:` marker why it must keep the parsed value's own zone. The
// marker is local rather than a file allowlist because two of the files carry
// both shapes, and an allowlist keyed on the file would go on covering the next
// reader added to it.
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

/// The nearest top-level `DateTime …(` declaration at or above [line], or ''.
String _enclosingReader(List<String> lines, int line) {
  for (var i = line; i >= 0; i--) {
    final m = _topLevelReader.firstMatch(lines[i]);
    if (m != null) return m.group(1)!;
  }
  return '';
}

void main() {
  test('the store family reads a timestamp through one reader', () {
    expect(rootExists(_root), isTrue, reason: 'scan root $_root has moved');

    final files = _familyFiles();
    // The family was seven stores plus the base when this guard landed. A
    // count that has COLLAPSED means the derivation stopped matching, and a
    // guard scanning nothing passes for the wrong reason.
    expect(files.length, greaterThanOrEqualTo(8),
        reason: 'derived family is ${files.map((f) => f.path)}');

    final offenders = <String>[];
    for (final file in files) {
      final raw = file.readAsStringSync();
      final code = blankNonCode(raw);
      final rawLines = raw.split('\n');
      final codeLines = code.split('\n');
      for (var i = 0; i < codeLines.length; i++) {
        if (!_parseCall.hasMatch(codeLines[i])) continue;
        if (file.path == _shared &&
            _enclosingReader(codeLines, i) == 'parseServerTimestamp') {
          continue;
        }
        final marked = rawLines[i].contains(_marker) ||
            (i > 0 && rawLines[i - 1].contains(_marker));
        if (marked) continue;
        offenders.add('${file.path}:${i + 1}: ${rawLines[i].trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'read the column through parseServerTimestamp, or state a '
            '`$_marker` reason why this site must keep the parsed zone:\n'
            '${offenders.join('\n')}');
  });

  test('the shared readers exist and the family actually uses them', () {
    final shared = File(_shared).readAsStringSync();
    expect(shared.contains('DateTime? parseServerTimestamp(dynamic v) {'), isTrue);
    expect(shared.contains('DateTime storedClockOrNow(dynamic v) =>'), isTrue);

    var timestampSites = 0;
    var clockSites = 0;
    for (final file in _familyFiles()) {
      final code = blankNonCode(file.readAsStringSync());
      timestampSites += 'parseServerTimestamp('.allMatches(code).length;
      clockSites += 'storedClockOrNow('.allMatches(code).length;
    }
    // Declarations included: 16 timestamp reads + 1 declaration, 7 clock reads
    // + 1 declaration when this landed. A drop to the declarations alone means
    // a store went back to open-coding the read past this guard's blind spot.
    expect(timestampSites, greaterThanOrEqualTo(12));
    expect(clockSites, greaterThanOrEqualTo(8));
  });
}
