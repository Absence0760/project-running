import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One reader for a stored date-time in this package, and it is the strict one.
///
/// `DateTime.tryParse` has two behaviours under one name: it refuses text it
/// cannot recognise, and it ROLLS OVER anything it can. `2026-06-32` is the 2nd
/// of July, `2027-02-29` is the 1st of March, and `DateTime.parse` rolls over
/// identically. So an impossible column does not read as absent — it reads as a
/// confident wrong instant that passes every downstream non-null check
/// (decisions § 1344). `core_models`' `parseIsoStrict` family refuses instead.
///
/// This exists because the guard that states the same rule for the app
/// (`apps/mobile_android/test/store_timestamp_reader_guard_test.dart`) derives
/// its covered set from files under that app's own `lib/`, so no package is in
/// it — and `api_client` held 21 raw parses the whole time that guard was green
/// (§ 1430). A rule with no instrument over a tree is a rule that tree does not
/// have.
///
/// The set is every file under `lib/`, not a list: a reader added tomorrow is
/// covered the day it lands rather than the day someone remembers to register
/// it. There is deliberately no per-site escape hatch — nothing in this package
/// needs one, and an unused exemption is a hole waiting for the first caller
/// who does not want to explain itself. A site that genuinely must keep a
/// parsed value's own zone edits this guard and says so.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final parseCall = RegExp(r'DateTime\.(try)?[Pp]arse\(');

  test('the scan sees this package at all', () {
    // A guard that inspects nothing enforces nothing: `lib` moving or the
    // suite running from another directory would otherwise read as a pass.
    expect(files, isNotEmpty, reason: 'no Dart file found under lib/');
    expect(
      files.any((f) => f.readAsStringSync().contains('parseIsoStrict')),
      isTrue,
      reason: 'no file in this package reads a stored date-time through the '
          'strict reader, so this guard is checking a rule nothing follows',
    );
  });

  test('no file under lib/ parses a stored date-time itself', () {
    final offenders = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in parseCall.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${f.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these sites take the rollover: an out-of-range component yields '
          'a wrong instant rather than no instant. Read through '
          'parseIsoStrictValue (a nullable column), parseIsoStrictRequired (a '
          'column the row cannot be shaped without) or parseIsoStrict (a '
          'String already in hand) from core_models',
    );
  });
}
