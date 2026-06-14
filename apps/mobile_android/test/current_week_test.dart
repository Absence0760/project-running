import 'package:flutter_test/flutter_test.dart';
import '../lib/current_week.dart';

// A Wednesday, local time. 2026-06-10 is a Wednesday.
final wed = DateTime(2026, 6, 10, 12, 0, 0);

List<String> isos(CurrentWeek week) => week.days.map((d) => d.iso).toList();

void main() {
  group('currentWeek', () {
    test('monday-start window spans Mon..Sun containing now', () {
      final w = currentWeek(const [], WeekStart.monday, wed);
      expect(isos(w), [
        '2026-06-08', // Mon
        '2026-06-09',
        '2026-06-10', // Wed (now)
        '2026-06-11',
        '2026-06-12',
        '2026-06-13',
        '2026-06-14', // Sun
      ]);
      expect(w.days.length, 7);
    });

    test('sunday-start window spans Sun..Sat containing now', () {
      final w = currentWeek(const [], WeekStart.sunday, wed);
      expect(isos(w), [
        '2026-06-07', // Sun
        '2026-06-08',
        '2026-06-09',
        '2026-06-10', // Wed (now)
        '2026-06-11',
        '2026-06-12',
        '2026-06-13', // Sat
      ]);
    });

    test('dow is the JS day-of-week for each cell', () {
      final w = currentWeek(const [], WeekStart.monday, wed);
      expect(w.days.map((d) => d.dow).toList(), [1, 2, 3, 4, 5, 6, 0]); // Mon..Sun
    });

    test('flags today and future days', () {
      final w = currentWeek(const [], WeekStart.monday, wed);
      final today = w.days.firstWhere((d) => d.iso == '2026-06-10');
      expect(today.isToday, isTrue);
      expect(today.isFuture, isFalse);
      expect(w.days.firstWhere((d) => d.iso == '2026-06-09').isFuture, isFalse); // past
      expect(w.days.firstWhere((d) => d.iso == '2026-06-11').isFuture, isTrue); // tomorrow
    });

    test('buckets activities onto their local day and sums distance + count', () {
      final acts = [
        const WeekActivity(startedAt: '2026-06-08T07:00:00', distanceM: 5000),
        const WeekActivity(startedAt: '2026-06-08T18:00:00', distanceM: 3000),
        const WeekActivity(startedAt: '2026-06-10T06:30:00', distanceM: 10000),
      ];
      final w = currentWeek(acts, WeekStart.monday, wed);
      final mon = w.days.firstWhere((d) => d.iso == '2026-06-08');
      expect(mon.distanceM, 8000);
      expect(mon.count, 2);
      final wedDay = w.days.firstWhere((d) => d.iso == '2026-06-10');
      expect(wedDay.distanceM, 10000);
      expect(wedDay.count, 1);
      expect(w.totalDistanceM, 18000);
      expect(w.totalCount, 3);
    });

    test('ignores activities outside the current week', () {
      final acts = [
        const WeekActivity(startedAt: '2026-06-01T07:00:00', distanceM: 5000), // last week
        const WeekActivity(startedAt: '2026-06-20T07:00:00', distanceM: 5000), // next week
        const WeekActivity(startedAt: '2026-06-09T07:00:00', distanceM: 4000), // in week
      ];
      final w = currentWeek(acts, WeekStart.monday, wed);
      expect(w.totalDistanceM, 4000);
      expect(w.totalCount, 1);
    });

    test('ignores zero / negative distance activities', () {
      final acts = [
        const WeekActivity(startedAt: '2026-06-09T07:00:00', distanceM: 0),
        const WeekActivity(startedAt: '2026-06-09T08:00:00', distanceM: -100),
        const WeekActivity(startedAt: '2026-06-09T09:00:00', distanceM: 2000),
      ];
      final w = currentWeek(acts, WeekStart.monday, wed);
      expect(w.totalDistanceM, 2000);
      expect(w.totalCount, 1);
    });

    test('ignores activities with an unparseable timestamp', () {
      final acts = [
        const WeekActivity(startedAt: 'not-a-date', distanceM: 5000),
        const WeekActivity(startedAt: '2026-06-09T07:00:00', distanceM: 3000),
      ];
      final w = currentWeek(acts, WeekStart.monday, wed);
      expect(w.totalDistanceM, 3000);
      expect(w.totalCount, 1);
    });

    test('a late-evening run buckets onto its local day, not UTC', () {
      final acts = [
        const WeekActivity(startedAt: '2026-06-09T23:30:00', distanceM: 6000),
      ];
      final w = currentWeek(acts, WeekStart.monday, wed);
      expect(w.days.firstWhere((d) => d.iso == '2026-06-09').distanceM, 6000);
      expect(w.days.firstWhere((d) => d.iso == '2026-06-10').distanceM, 0);
    });

    test('empty input yields a zeroed seven-day week', () {
      final w = currentWeek(const [], WeekStart.monday, wed);
      expect(w.totalDistanceM, 0);
      expect(w.totalCount, 0);
      expect(w.days.every((d) => d.distanceM == 0 && d.count == 0), isTrue);
    });
  });
}
