import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityRow.fromRow', () {
    test('parses a full row', () {
      final r = ActivityRow.fromRow({
        'id': 'a1',
        'kind': 'lift',
        'started_at': '2026-06-04T08:00:00Z',
        'summary': {'title': 'Push day', 'set_count': 5},
      });
      expect(r, isNotNull);
      expect(r!.id, 'a1');
      expect(r.kind, 'lift');
      expect(r.startedAt, DateTime.parse('2026-06-04T08:00:00Z'));
      expect(r.summary['title'], 'Push day');
    });

    test('drops a row with a null or empty id', () {
      expect(
          ActivityRow.fromRow(
              {'id': null, 'kind': 'run', 'started_at': '2026-06-04T08:00:00Z'}),
          isNull);
      expect(
          ActivityRow.fromRow(
              {'id': '', 'kind': 'run', 'started_at': '2026-06-04T08:00:00Z'}),
          isNull);
    });

    test('drops a row whose started_at is missing or unparseable', () {
      expect(ActivityRow.fromRow({'id': 'a', 'kind': 'run'}), isNull);
      expect(
          ActivityRow.fromRow(
              {'id': 'a', 'kind': 'run', 'started_at': 'not-a-date'}),
          isNull);
    });

    test('defaults kind to run when the column is null', () {
      final r = ActivityRow.fromRow(
          {'id': 'a', 'started_at': '2026-06-04T08:00:00Z'});
      expect(r!.kind, 'run');
    });

    test('defaults summary to an empty map when null or non-Map', () {
      final nullSummary = ActivityRow.fromRow(
          {'id': 'a', 'kind': 'meal', 'started_at': '2026-06-04T08:00:00Z'});
      expect(nullSummary!.summary, isEmpty);
      final badSummary = ActivityRow.fromRow({
        'id': 'b',
        'kind': 'meal',
        'started_at': '2026-06-04T08:00:00Z',
        'summary': 'oops',
      });
      expect(badSummary!.summary, isEmpty);
    });
  });
}
