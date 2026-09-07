import 'dart:io';

import 'package:test/test.dart';

/// The raw date-time parse lives in exactly one file of this package, and every
/// other reader goes through it.
///
/// `DateTime.tryParse` ROLLS OVER an out-of-range component rather than
/// refusing it — `2026-06-32` is the 2nd of July, `2027-02-29` is the 1st of
/// March — so an impossible stored value reads as a confident wrong instant
/// that passes every downstream non-null check (decisions § 1344).
/// [parseIsoStrict] range-checks each component and refuses instead, and since
/// § 1377 it lives here because its readers sit in three trees.
///
/// The app's own guard
/// (`apps/mobile_android/test/store_timestamp_reader_guard_test.dart`) derives
/// its covered set from files under that app's `lib/`, so this package has
/// never been in it: the 167 generated row readers and the seven in `social.dart`
/// were converted in § 1430 with nothing pinning the result. This is that
/// instrument, and its sibling covers `api_client`.
///
/// Two exemptions, both derived rather than listed. [_owner] is where the raw
/// parse is SUPPOSED to be, and the suite fails if it stops holding one — an
/// owner that no longer parses anything means the rule moved and this guard is
/// aimed at nothing. The generated `part` files are recognised by the marker
/// their generator writes, never by name: they read this package's OWN
/// `toJson` output rather than a server column, and they are rewritten by
/// `build_runner` on every regeneration, so a hand edit to one is erased.
void main() {
  const owner = 'lib/src/iso_parse.dart';
  const generatedMarker = 'GENERATED CODE - DO NOT MODIFY BY HAND';

  final parseCall = RegExp(r'DateTime\.(try)?[Pp]arse\(');

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the scan sees this package at all', () {
    expect(files, isNotEmpty, reason: 'no Dart file found under lib/');
    expect(files.map((f) => f.path), contains(owner));
  });

  test('the owner still holds the raw parse it is exempted for', () {
    // Anti-vacuity: if the parse leaves this file the exemption is covering
    // nothing, and the rule below is enforcing a property no code has.
    expect(
      parseCall.hasMatch(File(owner).readAsStringSync()),
      isTrue,
      reason: '$owner no longer parses anything — the strict reader moved and '
          'this guard is exempting the wrong file',
    );
  });

  test('every generated part file says so in its own text', () {
    final generated =
        files.where((f) => f.readAsStringSync().contains(generatedMarker));
    expect(generated, isNotEmpty,
        reason: 'no file carries the generator marker, so the exemption below '
            'is derived from a string nothing writes any more');
    expect(
      generated.every((f) => f.path.endsWith('.g.dart')),
      isTrue,
      reason: 'a hand-written file claims to be generated, which would exempt '
          'it from the rule below',
    );
  });

  test('no other file under lib/ parses a stored date-time itself', () {
    final offenders = <String>[];
    for (final f in files) {
      if (f.path == owner) continue;
      final src = f.readAsStringSync();
      if (src.contains(generatedMarker)) continue;
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
          'parseIsoStrictValue, parseIsoStrictRequired or parseIsoStrict',
    );
  });
}
