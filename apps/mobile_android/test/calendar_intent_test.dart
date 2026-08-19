import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/calendar_intent.dart';
import '../lib/recurrence.dart';

EventRecurrence _weekly({
  DateTime? startsAt,
  List<Weekday>? byday,
  DateTime? until,
  int? count,
  RecurrenceFreq freq = RecurrenceFreq.weekly,
}) => EventRecurrence(
  startsAt: startsAt ?? DateTime.utc(2026, 6, 16, 18),
  freq: freq,
  byday: byday ?? [Weekday.sa],
  until: until,
  count: count,
  timezone: 'UTC',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildRrule', () {
    test('a weekly series names its weekdays in RFC order', () {
      expect(
        buildRrule(
          freq: RecurrenceFreq.weekly,
          byday: [Weekday.sa, Weekday.tu],
        ),
        'FREQ=WEEKLY;BYDAY=TU,SA',
      );
    });

    test('a fortnightly series is weekly with an interval', () {
      expect(
        buildRrule(freq: RecurrenceFreq.biweekly, byday: [Weekday.we]),
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE',
      );
    });

    test('an empty weekday set leaves BYDAY off rather than emitting nothing',
        () {
      expect(buildRrule(freq: RecurrenceFreq.weekly), 'FREQ=WEEKLY');
    });

    test('a monthly series carries its day of the month', () {
      expect(
        buildRrule(freq: RecurrenceFreq.monthly, monthDay: 12),
        'FREQ=MONTHLY;BYMONTHDAY=12',
      );
    });

    test('a monthly series past the 28th is withheld, not approximated', () {
      // The app clamps a missing day-of-month to the month's last day;
      // BYMONTHDAY skips the short month instead.
      expect(buildRrule(freq: RecurrenceFreq.monthly, monthDay: 31), isNull);
      expect(buildRrule(freq: RecurrenceFreq.monthly, monthDay: 29), isNull);
    });

    test('a monthly series with no day of the month is withheld', () {
      expect(buildRrule(freq: RecurrenceFreq.monthly), isNull);
    });

    test('a count is emitted as COUNT', () {
      expect(
        buildRrule(freq: RecurrenceFreq.weekly, byday: [Weekday.sa], count: 6),
        'FREQ=WEEKLY;COUNT=6;BYDAY=SA',
      );
    });

    test('a count below one is withheld', () {
      expect(
        buildRrule(freq: RecurrenceFreq.weekly, byday: [Weekday.sa], count: 0),
        isNull,
      );
    });

    test('an until is emitted as a UTC stamp', () {
      expect(
        buildRrule(
          freq: RecurrenceFreq.weekly,
          byday: [Weekday.sa],
          until: DateTime.utc(2026, 9, 5, 7, 30, 4),
        ),
        'FREQ=WEEKLY;UNTIL=20260905T073004Z;BYDAY=SA',
      );
    });

    test('an until in a local zone is converted, not stamped as written', () {
      final rule = buildRrule(
        freq: RecurrenceFreq.weekly,
        byday: [Weekday.sa],
        until: DateTime.utc(2026, 9, 5, 7).toLocal(),
      );
      expect(rule, 'FREQ=WEEKLY;UNTIL=20260905T070000Z;BYDAY=SA');
    });

    test('a count wins over an until — RFC 5545 forbids both in one rule', () {
      final rule = buildRrule(
        freq: RecurrenceFreq.weekly,
        byday: [Weekday.sa],
        count: 3,
        until: DateTime.utc(2026, 9, 5),
      );
      expect(rule, contains('COUNT=3'));
      expect(rule, isNot(contains('UNTIL')));
    });
  });

  group('calendarSeriesFor', () {
    test('a one-off event has no series', () {
      expect(
        calendarSeriesFor(
          EventRecurrence(startsAt: DateTime.utc(2026, 6, 20, 8)),
        ),
        isNull,
      );
    });

    test('the anchor is the first occurrence, not the creation day', () {
      // Created on a Tuesday, recurring on Saturdays: anchoring on startsAt
      // would add a Tuesday the club page never shows.
      final series = calendarSeriesFor(
        _weekly(startsAt: DateTime.utc(2026, 6, 16, 18)),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.anchor, DateTime.utc(2026, 6, 20, 18));
      expect(series.rrule, 'FREQ=WEEKLY;BYDAY=SA');
    });

    test('a sub-second start still anchors on its own first occurrence', () {
      // The expansion stamps whole seconds, so searching from the raw instant
      // drops the first occurrence and lands the anchor a week late.
      final series = calendarSeriesFor(
        _weekly(startsAt: DateTime.utc(2026, 6, 20, 18, 0, 0, 123, 456)),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.anchor, DateTime.utc(2026, 6, 20, 18));
    });

    test('a sub-second start does not cost the series an occurrence', () {
      final series = calendarSeriesFor(
        _weekly(
          startsAt: DateTime.utc(2026, 6, 20, 18, 0, 0, 123, 456),
          count: 9,
          until: DateTime.utc(2026, 7, 4, 18),
        ),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.rrule, 'FREQ=WEEKLY;COUNT=3;BYDAY=SA');
    });

    test('the weekday set is read off the expansion', () {
      final series = calendarSeriesFor(
        _weekly(byday: [Weekday.tu, Weekday.th]),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.rrule, 'FREQ=WEEKLY;BYDAY=TU,TH');
    });

    test('a fortnightly series keeps its interval', () {
      final series = calendarSeriesFor(
        _weekly(freq: RecurrenceFreq.biweekly),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.rrule, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SA');
    });

    test('an until-bounded series carries UNTIL', () {
      final series = calendarSeriesFor(
        _weekly(until: DateTime.utc(2026, 8, 1, 18)),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.rrule, 'FREQ=WEEKLY;UNTIL=20260801T180000Z;BYDAY=SA');
    });

    test('an until + count pair resolves to whichever binds first', () {
      // 20 Jun / 27 Jun / 4 Jul are inside the until-bound, so the count of 9
      // never binds and the rule states the three real occurrences.
      final series = calendarSeriesFor(
        _weekly(count: 9, until: DateTime.utc(2026, 7, 4, 18)),
        now: DateTime.utc(2026, 6, 16),
      );
      expect(series!.rrule, 'FREQ=WEEKLY;COUNT=3;BYDAY=SA');
    });

    test('a monthly series inside the clamp-free range states its day', () {
      final series = calendarSeriesFor(
        EventRecurrence(
          startsAt: DateTime.utc(2026, 6, 12, 19),
          freq: RecurrenceFreq.monthly,
          timezone: 'UTC',
        ),
        now: DateTime.utc(2026, 6, 1),
      );
      expect(series!.rrule, 'FREQ=MONTHLY;BYMONTHDAY=12');
    });

    test('a monthly series anchored past the 28th has no expressible rule', () {
      expect(
        calendarSeriesFor(
          EventRecurrence(
            startsAt: DateTime.utc(2026, 1, 31, 19),
            freq: RecurrenceFreq.monthly,
            timezone: 'UTC',
          ),
          now: DateTime.utc(2026, 6, 1),
        ),
        isNull,
      );
    });

    test('called-off occurrences ahead are reported, never silently dropped',
        () {
      final series = calendarSeriesFor(
        _weekly(),
        cancelled: [DateTime.utc(2026, 6, 27, 18), DateTime.utc(2026, 7, 4, 18)],
        now: DateTime.utc(2026, 6, 20),
      );
      expect(series!.unsubtractedCancellations, [
        DateTime.utc(2026, 6, 27, 18),
        DateTime.utc(2026, 7, 4, 18),
      ]);
    });

    test('a cancellation already behind the viewer is not reported', () {
      final series = calendarSeriesFor(
        _weekly(),
        cancelled: [DateTime.utc(2026, 6, 20, 18)],
        now: DateTime.utc(2026, 6, 25),
      );
      expect(series!.unsubtractedCancellations, isEmpty);
    });

    test('nothing called off reports nothing', () {
      final series = calendarSeriesFor(_weekly(), now: DateTime.utc(2026, 6, 16));
      expect(series!.unsubtractedCancellations, isEmpty);
    });
  });

  group('addToDeviceCalendar', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(calendarChannel, null);
    });

    test('hands the occurrence over as UTC epoch milliseconds', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(calendarChannel, (call) async {
        seen = call;
        return true;
      });

      final ok = await addToDeviceCalendar(
        title: 'Saturday Long Run',
        start: DateTime.utc(2026, 6, 20, 8),
        durationMin: 90,
        description: 'Meet by the bridge',
        location: 'Riverside Park',
        url: 'https://threkir.com/share/event/e1',
        rrule: 'FREQ=WEEKLY;BYDAY=SA',
      );

      expect(ok, isTrue);
      expect(seen!.method, 'addEvent');
      final args = seen!.arguments as Map;
      expect(args['title'], 'Saturday Long Run');
      expect(args['startMs'], DateTime.utc(2026, 6, 20, 8).millisecondsSinceEpoch);
      expect(args['endMs'], DateTime.utc(2026, 6, 20, 9, 30).millisecondsSinceEpoch);
      expect(args['location'], 'Riverside Park');
      expect(args['rrule'], 'FREQ=WEEKLY;BYDAY=SA');
    });

    test('no duration means no end instant to hand over', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(calendarChannel, (call) async {
        seen = call;
        return true;
      });

      await addToDeviceCalendar(
        title: 'Track night',
        start: DateTime.utc(2026, 6, 20, 8),
        durationMin: 0,
      );

      expect((seen!.arguments as Map).containsKey('endMs'), isFalse);
    });

    test('a local start crosses the channel as its absolute instant', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(calendarChannel, (call) async {
        seen = call;
        return true;
      });

      final start = DateTime.utc(2026, 6, 20, 8).toLocal();
      await addToDeviceCalendar(title: 'Track night', start: start);

      expect(
        (seen!.arguments as Map)['startMs'],
        DateTime.utc(2026, 6, 20, 8).millisecondsSinceEpoch,
      );
    });

    test('a refused hand-off is reported, not swallowed as success', () async {
      messenger.setMockMethodCallHandler(
        calendarChannel,
        (call) async => false,
      );
      expect(
        await addToDeviceCalendar(
          title: 'Track night',
          start: DateTime.utc(2026, 6, 20, 8),
        ),
        isFalse,
      );
    });

    test('a throwing platform channel returns false rather than propagating',
        () async {
      messenger.setMockMethodCallHandler(calendarChannel, (call) async {
        throw PlatformException(code: 'no-calendar');
      });
      expect(
        await addToDeviceCalendar(
          title: 'Track night',
          start: DateTime.utc(2026, 6, 20, 8),
        ),
        isFalse,
      );
    });

    test('a missing native handler returns false', () async {
      expect(
        await addToDeviceCalendar(
          title: 'Track night',
          start: DateTime.utc(2026, 6, 20, 8),
        ),
        isFalse,
      );
    });
  });
}
