import 'package:api_client/api_client.dart' show ActivityRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/activity_timeline.dart';

ActivityRow _a(String id, String kind, DateTime startedAt) => ActivityRow(
      id: id,
      kind: kind,
      startedAt: startedAt,
      summary: const {},
    );

void main() {
  group('groupActivitiesByDay', () {
    test('returns empty for no rows', () {
      expect(groupActivitiesByDay(const []), isEmpty);
    });

    test('buckets rows by local calendar day, preserving order', () {
      final rows = [
        _a('a', 'run', DateTime(2026, 6, 4, 18)),
        _a('b', 'lift', DateTime(2026, 6, 4, 8)),
        _a('c', 'meal', DateTime(2026, 6, 3, 12)),
      ];
      final groups = groupActivitiesByDay(rows);
      expect(groups.length, 2);
      expect(groups[0].day, DateTime(2026, 6, 4));
      expect(groups[0].rows.map((r) => r.id), ['a', 'b']);
      expect(groups[1].day, DateTime(2026, 6, 3));
      expect(groups[1].rows.single.id, 'c');
    });

    test('same instant different time-of-day stays one day bucket', () {
      final rows = [
        _a('a', 'run', DateTime(2026, 6, 4, 23, 59)),
        _a('b', 'meal', DateTime(2026, 6, 4, 0, 1)),
      ];
      final groups = groupActivitiesByDay(rows);
      expect(groups.length, 1);
      expect(groups.single.rows.length, 2);
    });

    test('re-opens a day bucket only on a day change (no merge across gaps)', () {
      // Rows arrive newest-first; a back-to-back A/B/A day pattern produces
      // three buckets, not two — grouping is sequential, not a global sort.
      final rows = [
        _a('a', 'run', DateTime(2026, 6, 5, 9)),
        _a('b', 'run', DateTime(2026, 6, 4, 9)),
        _a('c', 'run', DateTime(2026, 6, 5, 7)),
      ];
      final groups = groupActivitiesByDay(rows);
      expect(groups.length, 3);
      expect(groups.map((g) => g.rows.single.id), ['a', 'b', 'c']);
    });
  });
}
