// Mirror of web's `import_failures.test.ts` — test-for-test, same order.
// Web object literals become Dart `Map`s; where web throws a DOM/`Error`
// instance the Dart side throws the closest real thrown value.

import 'package:flutter_test/flutter_test.dart';

import '../lib/import_failures.dart';

void main() {
  test('a dropped connection classifies as network, not unknown', () {
    expect(classifyImportFailure(const FormatException('Failed to fetch')).reason,
        ImportFailureReason.network);
    expect(
        classifyImportFailure(
                Exception('NetworkError when attempting to fetch'))
            .reason,
        ImportFailureReason.network);
    expect(classifyImportFailure(Exception('Load failed')).reason,
        ImportFailureReason.network);
  });

  test('an expired session classifies as auth', () {
    expect(classifyImportFailure(StateError('Not signed in')).reason,
        ImportFailureReason.auth);
    expect(classifyImportFailure(Exception('JWT expired')).reason,
        ImportFailureReason.auth);
    expect(
        classifyImportFailure({'status': 401, 'message': 'nope'}).reason,
        ImportFailureReason.auth);
  });

  test('an invalid token reads as auth, not as unparseable', () {
    expect(classifyImportFailure(Exception('invalid token')).reason,
        ImportFailureReason.auth);
  });

  test('rate limiting is recognised from status, trigger code, and prose', () {
    expect(classifyImportFailure({'status': 429, 'message': 'slow down'}).reason,
        ImportFailureReason.rateLimited);
    expect(
        classifyImportFailure({
          'code': 'P0001',
          'message': 'rate limit exceeded for create_route, retry in 30s',
        }).reason,
        ImportFailureReason.rateLimited);
    expect(classifyImportFailure(Exception('Too Many Requests')).reason,
        ImportFailureReason.rateLimited);
  });

  test('an oversized upload reads as too_large, not rejected', () {
    expect(classifyImportFailure({'status': 413, 'message': 'nope'}).reason,
        ImportFailureReason.tooLarge);
    expect(
        classifyImportFailure(
                Exception('The object exceeded the maximum allowed size'))
            .reason,
        ImportFailureReason.tooLarge);
  });

  test('a storage quota rejection is a size problem, not a rate limit', () {
    // The word "quota" also appears in third-party rate-limit prose, but the
    // only errors reaching this classifier come from the run save, the photo
    // upload and the parsers — where a quota IS a size cap.
    expect(classifyImportFailure(Exception('The quota has been exceeded.')).reason,
        ImportFailureReason.tooLarge);
    // A genuine rate limit still wins: it is matched before the size patterns.
    expect(
        classifyImportFailure(Exception('API quota exceeded — too many requests'))
            .reason,
        ImportFailureReason.rateLimited);
  });

  test('a database refusal classifies as rejected', () {
    expect(classifyImportFailure({'code': '42501', 'message': 'denied'}).reason,
        ImportFailureReason.rejected);
    expect(
        classifyImportFailure({'code': '23505', 'message': 'duplicate key'})
            .reason,
        ImportFailureReason.rejected);
    expect(
        classifyImportFailure(
                Exception('new row violates row-level security policy'))
            .reason,
        ImportFailureReason.rejected);
  });

  test('a data-exception SQLSTATE reads as rejected, not as an unreadable file',
      () {
    // 22P02 carries "invalid input syntax", which the unparseable message
    // pattern would otherwise claim — the server answered and refused.
    expect(
        classifyImportFailure({
          'code': '22P02',
          'message': 'invalid input syntax for type uuid',
        }).reason,
        ImportFailureReason.rejected);
    expect(
        classifyImportFailure({
          'code': 'PGRST204',
          'message': 'Could not find the column',
        }).reason,
        ImportFailureReason.rejected);
  });

  test('a code never overrides the network / auth / size signals', () {
    expect(
        classifyImportFailure({
          'code': 'PGRST000',
          'message': 'TypeError: Failed to fetch',
        }).reason,
        ImportFailureReason.network);
    expect(
        classifyImportFailure({'code': '42501', 'message': 'JWT expired'}).reason,
        ImportFailureReason.auth);
  });

  test('a bad archive member classifies as unparseable', () {
    expect(
        classifyImportFailure(const FormatException(
                'Unsupported file format: .bin. Use GPX, KML, KMZ, GeoJSON, or TCX.'))
            .reason,
        ImportFailureReason.unparseable);
    expect(
        classifyImportFailure(
                const FormatException('TCX file contains no track points'))
            .reason,
        ImportFailureReason.unparseable);
    // A bundle .zip that wraps no activity — the runner's answer is "that
    // file wasn't a run", not "unknown error".
    expect(
        classifyImportFailure(
                const FormatException('Archive member contains no FIT file'))
            .reason,
        ImportFailureReason.unparseable);
  });

  test('an unrecognised failure stays unknown rather than guessing', () {
    expect(classifyImportFailure(Exception('something went sideways')).reason,
        ImportFailureReason.unknown);
    expect(classifyImportFailure(null).reason, ImportFailureReason.unknown);
    expect(classifyImportFailure(<String, Object?>{}).reason,
        ImportFailureReason.unknown);
  });

  test('detail carries code and message but never details or hint', () {
    final detail = classifyImportFailure({
      'code': '42501',
      'message': 'new row violates row-level security policy for table "runs"',
      'details': 'Failing row contains (uuid, 51.5074, -0.1278)',
      'hint': 'check the policy on runs',
    }).detail;
    expect(detail, startsWith('42501: new row violates'));
    expect(detail.contains('51.5074'), isFalse);
    expect(detail.contains('check the policy'), isFalse);
  });

  test('detail collapses whitespace and is bounded', () {
    expect(classifyImportFailure(const FormatException('a\n\tb   c')).detail,
        'a b c');
    final long =
        classifyImportFailure(FormatException('x' * 500)).detail;
    expect(long.length, 200);
    expect(long.endsWith('…'), isTrue);
  });

  test('a non-Error thrown value does not produce junk', () {
    expect(classifyImportFailure({'foo': 'bar'}).detail, '');
    expect(classifyImportFailure('plain string boom').detail,
        'plain string boom');
  });

  test('recording a failure keeps the activity name and start', () {
    final log = newImportFailureLog();
    recordImportFailure(log,
        name: 'Morning Run',
        startedAt: '2026-03-01T07:00:00Z',
        error: const FormatException('Failed to fetch'));
    expect(log.items.length, 1);
    expect(log.items.first.name, 'Morning Run');
    expect(log.items.first.startedAt, '2026-03-01T07:00:00Z');
    expect(log.items.first.reason, ImportFailureReason.network);
    expect(log.items.first.detail, 'Failed to fetch');
    expect(log.truncated, 0);
  });

  test('a blank name falls back rather than rendering an empty row', () {
    final log = newImportFailureLog();
    recordImportFailure(log, name: '   ', error: Exception('boom'));
    expect(log.items.first.name, 'Unnamed activity');
    expect(log.items.first.startedAt, isNull);
  });

  test('the log caps retained failures and counts the overflow', () {
    final log = newImportFailureLog();
    for (var i = 0; i < kMaxRecordedImportFailures + 17; i++) {
      recordImportFailure(log, name: 'Run $i', error: Exception('boom'));
    }
    expect(log.items.length, kMaxRecordedImportFailures);
    expect(log.truncated, 17);
  });

  test('grouping orders by count then reason', () {
    final log = newImportFailureLog();
    recordImportFailure(log,
        name: 'a', error: const FormatException('Failed to fetch'));
    recordImportFailure(log,
        name: 'b', error: const FormatException('Failed to fetch'));
    recordImportFailure(log, name: 'c', error: Exception('JWT expired'));
    recordImportFailure(log,
        name: 'd',
        error: const FormatException('TCX file contains no track points'));
    final groups = groupImportFailures(log);
    expect(groups.map((g) => g.reason).toList(), [
      ImportFailureReason.network,
      ImportFailureReason.auth,
      ImportFailureReason.unparseable,
    ]);
    expect(groups.map((g) => g.count).toList(), [2, 1, 1]);
  });

  test('grouping an empty log yields no rows', () {
    expect(groupImportFailures(newImportFailureLog()), isEmpty);
  });

  test('the CSV report escapes embedded quotes and commas', () {
    final log = newImportFailureLog();
    recordImportFailure(log,
        name: 'Hill "repeats", 8x400',
        startedAt: '2026-03-01T07:00:00Z',
        error: const FormatException('Failed to fetch'));
    final lines = importFailureReportCsv(log).split('\n');
    expect(lines[0], 'Activity,Started,Reason,Detail');
    expect(lines[1],
        '"Hill ""repeats"", 8x400","2026-03-01T07:00:00Z","network","Failed to fetch"');
    expect(lines.length, 2);
  });

  test('the CSV report states truncation rather than silently omitting', () {
    final log = newImportFailureLog();
    for (var i = 0; i < kMaxRecordedImportFailures + 3; i++) {
      recordImportFailure(log, name: 'Run $i', error: Exception('boom'));
    }
    final lines = importFailureReportCsv(log).split('\n');
    expect(lines.length, kMaxRecordedImportFailures + 2);
    expect(lines.last,
        startsWith('"(3 further failures not recorded)","","truncated"'));
  });

  test('an empty log still produces a header-only report', () {
    expect(importFailureReportCsv(newImportFailureLog()),
        'Activity,Started,Reason,Detail');
  });
}
