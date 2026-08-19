import 'package:flutter_test/flutter_test.dart';

import '../lib/event_occurrence.dart';
import '../lib/recurrence.dart';

// A weekly Wednesday 08:00 series. Instances: Apr 1, 8, 15, 22, 29.
final _weekly = EventRecurrence(
  startsAt: DateTime.utc(2026, 4, 1, 8),
  freq: RecurrenceFreq.weekly,
  timezone: 'UTC',
);
final _beforeSeries = DateTime.utc(2026, 3, 30);

void main() {
  group('isOccurrenceCancelled', () {
    test('matches the same instant expressed in another zone', () {
      // Web compares two ISO renderings of one instant; the Dart equivalent is
      // that a local-zone DateTime naming the same moment still matches.
      final utc = DateTime.utc(2026, 4, 8, 8);
      expect(isOccurrenceCancelled([utc], utc.toLocal()), isTrue);
      expect(isOccurrenceCancelled([utc.toLocal()], utc), isTrue);
    });

    test('a different instant, an empty list, and a null are all not cancelled',
        () {
      expect(
        isOccurrenceCancelled(
            [DateTime.utc(2026, 4, 8, 8)], DateTime.utc(2026, 4, 15, 8)),
        isFalse,
      );
      expect(isOccurrenceCancelled(const [], DateTime.utc(2026, 4, 8, 8)),
          isFalse);
      expect(isOccurrenceCancelled([DateTime.utc(2026, 4, 8, 8)], null), isFalse);
    });
  });

  group('nextLiveInstance', () {
    test('nothing cancelled gives the next occurrence', () {
      expect(nextLiveInstance(_weekly, const [], _beforeSeries),
          DateTime.utc(2026, 4, 1, 8));
    });

    test('skips the cancelled next occurrence', () {
      expect(
        nextLiveInstance(_weekly, [DateTime.utc(2026, 4, 1, 8)], _beforeSeries),
        DateTime.utc(2026, 4, 8, 8),
      );
    });

    test('skips a run of consecutive cancellations', () {
      expect(
        nextLiveInstance(_weekly, [
          DateTime.utc(2026, 4, 1, 8),
          DateTime.utc(2026, 4, 8, 8),
          DateTime.utc(2026, 4, 15, 8),
        ], _beforeSeries),
        DateTime.utc(2026, 4, 22, 8),
      );
    });

    test('a cancellation further out does not disturb the next occurrence', () {
      expect(
        nextLiveInstance(_weekly, [DateTime.utc(2026, 4, 22, 8)], _beforeSeries),
        DateTime.utc(2026, 4, 1, 8),
      );
    });

    test('already-past cancellations do not eat the search budget', () {
      // Three cancellations, all behind `after`. The budget is derived from the
      // cancelled COUNT, so the live Apr 22 occurrence must still be found.
      expect(
        nextLiveInstance(_weekly, [
          DateTime.utc(2026, 4, 1, 8),
          DateTime.utc(2026, 4, 8, 8),
          DateTime.utc(2026, 4, 15, 8),
        ], DateTime.utc(2026, 4, 20)),
        DateTime.utc(2026, 4, 22, 8),
      );
    });

    test('every remaining occurrence cancelled returns null', () {
      final bounded = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 1, 8),
        freq: RecurrenceFreq.weekly,
        count: 2,
        timezone: 'UTC',
      );
      expect(
        nextLiveInstance(bounded, [
          DateTime.utc(2026, 4, 1, 8),
          DateTime.utc(2026, 4, 8, 8),
        ], _beforeSeries),
        isNull,
      );
    });

    test('an exhausted series returns null whether or not anything was cancelled',
        () {
      final bounded = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 1, 8),
        freq: RecurrenceFreq.weekly,
        count: 1,
        timezone: 'UTC',
      );
      final after = DateTime.utc(2026, 5, 1);
      expect(nextLiveInstance(bounded, const [], after), isNull);
      expect(nextLiveInstance(bounded, [DateTime.utc(2026, 4, 1, 8)], after),
          isNull);
    });

    test('a one-off event cancelled has no live instance', () {
      final oneOff = EventRecurrence(startsAt: DateTime.utc(2026, 4, 1, 8));
      expect(
        nextLiveInstance(oneOff, [DateTime.utc(2026, 4, 1, 8)], _beforeSeries),
        isNull,
      );
      expect(nextLiveInstance(oneOff, const [], _beforeSeries),
          DateTime.utc(2026, 4, 1, 8));
    });
  });
}
