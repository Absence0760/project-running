import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/recurrence.dart';

void main() {
  group('expandInstances — weekly recurrence', () {
    test('each weekly instance hour/minute matches the local interpretation of startsAt', () {
      // An event stored in the DB as UTC (e.g. 10:30 UTC).
      // After the fix, each instance carries the *local* hour/minute of that UTC
      // timestamp. Before the fix, it carried the raw UTC hour, which is wrong
      // for any user whose offset != 0.
      final utcStart = DateTime.utc(2026, 4, 1, 10, 30, 0);
      final localStart = utcStart.toLocal();
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty,
          reason: 'at least one weekly instance should fall in April');
      for (final inst in instances) {
        // inst is a local (unzoned) DateTime — its .hour/.minute are local fields.
        expect(inst.hour, localStart.hour,
            reason: 'instance hour should be localStart.hour, not the raw UTC hour');
        expect(inst.minute, localStart.minute);
        expect(inst.second, localStart.second);
      }
    });

    test('instances do not precede the original startsAt', () {
      final utcStart = DateTime.utc(2026, 4, 8, 9, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty);
      for (final inst in instances) {
        expect(inst.isBefore(e.startsAt), isFalse,
            reason: 'no instance should precede the event start');
      }
    });

    test('biweekly event produces fewer instances than weekly in the same window', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final weekly = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );
      final biweekly = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.biweekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final wInstances = expandInstances(weekly, from, to);
      final bInstances = expandInstances(biweekly, from, to);
      // Biweekly should produce at most half as many instances.
      expect(bInstances.length, lessThan(wInstances.length));
    });

    test('recurrence_count cap limits the number of instances', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
        count: 2,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(2));
    });

    test('until date stops expansion — no instance falls after until', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final until = DateTime.utc(2026, 4, 22);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
        until: until,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty);
      for (final inst in instances) {
        expect(inst.isAfter(until), isFalse,
            reason: 'no instance should fall after the until date');
      }
    });

    test('non-recurring event returns the single instance if in window', () {
      final utcStart = DateTime.utc(2026, 4, 10, 8, 0, 0);
      final e = EventRecurrence(startsAt: utcStart);

      expect(
        expandInstances(e, DateTime.utc(2026, 4, 1), DateTime.utc(2026, 4, 30)),
        hasLength(1),
      );
      expect(
        expandInstances(e, DateTime.utc(2026, 5, 1), DateTime.utc(2026, 5, 31)),
        isEmpty,
      );
    });
  });

  group('expandInstances — monthly recurrence', () {
    test('monthly event produces one instance per month in window', () {
      final utcStart = DateTime.utc(2026, 4, 5, 10, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.monthly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 6, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(3)); // Apr 5, May 5, Jun 5
    });

    test('monthly recurrence_count cap limits instances', () {
      final utcStart = DateTime.utc(2026, 1, 1, 9, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.monthly,
        count: 3,
      );

      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(3));
    });
  });
}
