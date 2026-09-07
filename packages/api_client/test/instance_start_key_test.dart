import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// decisions § 1343. `instance_start` is the recurring-occurrence KEY the
/// server matches with `=`, and six methods on [ApiClient] write or filter on
/// it. Every one of them serialised the caller's `DateTime` with a bare
/// `toIso8601String()`, which writes NO zone designator for a local
/// `DateTime` — and `expandInstances` mints exactly that for an event
/// declaring no timezone. Postgres resolves a zone-less literal in the
/// session's own TimeZone, so two phones in different zones filed one
/// occurrence under two different keys, and neither matched the true instant
/// web has always written (a JS `Date` is an instant; `toISOString()` always
/// emits `Z`).
void main() {
  group('instanceStartKey', () {
    test('a UTC occurrence is unchanged', () {
      expect(instanceStartKey(DateTime.utc(2026, 6, 14, 7)),
          '2026-06-14T07:00:00.000Z');
    });

    test('a LOCAL occurrence becomes the instant it names, not its wall clock',
        () {
      // The defect, stated directly. On a non-UTC runner the two strings
      // differ; on a UTC runner they coincide, so the designator assertion
      // below is the half that is never vacuous.
      final local = DateTime.utc(2026, 6, 14, 7).toLocal();
      expect(instanceStartKey(local), '2026-06-14T07:00:00.000Z');
      expect(instanceStartKey(local), endsWith('Z'));
      expect(local.toIso8601String(), isNot(endsWith('Z')));
    });

    test('every answer states a zone', () {
      for (final at in [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 6, 14, 7).toLocal(),
        DateTime.parse('2026-06-14T09:00:00+02:00'),
        DateTime.parse('2026-06-14T07:00:00'),
      ]) {
        expect(instanceStartKey(at), endsWith('Z'), reason: '$at');
      }
    });

    test('two readers in different zones agree on one occurrence', () {
      // The same absolute instant reached through three spellings a client
      // could plausibly hold it in.
      final keys = {
        instanceStartKey(DateTime.utc(2026, 6, 14, 7)),
        instanceStartKey(DateTime.parse('2026-06-14T09:00:00+02:00')),
        instanceStartKey(
            DateTime.fromMillisecondsSinceEpoch(1781420400000, isUtc: false)),
      };
      expect(keys, hasLength(1));
    });

    test('a null occurrence stays null rather than becoming an epoch', () {
      expect(instanceStartKeyOrNull(null), isNull);
      expect(instanceStartKeyOrNull(DateTime.utc(2026, 6, 14, 7)),
          '2026-06-14T07:00:00.000Z');
    });
  });

  group('every instance_start wire site goes through the key helper', () {
    final src = File('lib/src/api_client.dart').readAsStringSync();

    test('the count of key sites has not collapsed', () {
      // Anchored on the number of SITES, not on the number of helper calls, so
      // deleting the normalisation cannot delete this test's own expectation.
      // Six when this landed: the run-photo insert and its gallery filter, the
      // RSVP upsert and the attendee filter, the crossings filter, and the
      // upsert-crossing RPC.
      final sites = RegExp(r'[iI]nstance[sS]tart\w*[,)\n]')
          .allMatches(src)
          .length;
      expect(sites, greaterThanOrEqualTo(6),
          reason: 'the instance_start writers have moved or been renamed');
    });

    test('no site serialises an instance_start with a bare toIso8601String',
        () {
      final offenders = <String>[];
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('toIso8601String()')) continue;
        // The declaration of the helper itself is the one place allowed to.
        if (line.contains('String instanceStartKey(')) continue;
        final window = '${i > 0 ? lines[i - 1] : ''}\n$line';
        if (!RegExp(r'[iI]nstance[sS]tart').hasMatch(window)) continue;
        offenders.add('lib/src/api_client.dart:${i + 1}: ${line.trim()}');
      }
      expect(offenders, isEmpty,
          reason: 'send instance_start through instanceStartKey — a bare '
              'toIso8601String writes no zone designator for a local '
              'DateTime, and Postgres re-anchors it (decisions § 1343):\n'
              '${offenders.join('\n')}');
    });

    test('the helper normalises before serialising', () {
      expect(src.contains('String instanceStartKey(DateTime at) => '
          'at.toUtc().toIso8601String();'), isTrue,
          reason: 'the .toUtc() IS the fix; a helper without it is a rename');
    });
  });
}
