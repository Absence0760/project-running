import 'package:flutter_test/flutter_test.dart';
import '../lib/recurrence.dart';

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

    test('biweekly with a weekend-crossing byday matches the web Monday anchor', () {
      // Twin-parity regression: Dart used to anchor the week on Sunday while
      // web anchors on Monday, so a biweekly [SA, SU] event disagreed on which
      // alternating weeks fire. Local (unzoned) start so the byday is the same
      // wall-clock Saturday in every test timezone. Expected dates are the
      // canonical web output (Monday anchor): May 2/3, 16/17, 30/31 2026.
      final e = EventRecurrence(
        startsAt: DateTime(2026, 5, 2, 9, 0), // Sat 09:00 local
        freq: RecurrenceFreq.biweekly,
        byday: const [Weekday.sa, Weekday.su],
      );

      final instances = expandInstances(
        e,
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31, 23, 59, 59),
      );

      final dates = instances.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(dates, ['2026-5-2', '2026-5-3', '2026-5-16', '2026-5-17', '2026-5-30', '2026-5-31']);
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

    test('day-31 monthly clamps to the last day of shorter months (no overflow)', () {
      // Jan-31 monthly must land on Feb-28 (2026 is not a leap year), Mar-31,
      // Apr-30 — never overflow into the following month. A naive
      // DateTime(y, 2, 31) rolls into March 3.
      final start = DateTime(2026, 1, 31, 9, 0);
      final e = EventRecurrence(
        startsAt: start,
        freq: RecurrenceFreq.monthly,
      );

      final instances = expandInstances(
        e,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30, 23, 59, 59),
      );

      final dates = instances.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(dates, ['2026-1-31', '2026-2-28', '2026-3-31', '2026-4-30']);
      // The clamp must not permanently shrink the day-of-month: March is
      // back to 31, proving each instance re-anchors on the original day.
      for (final inst in instances) {
        expect(inst.hour, 9);
        expect(inst.minute, 0);
      }
    });

    test('day-31 monthly hits Feb-29 in a leap year', () {
      final start = DateTime(2024, 1, 31, 8, 0);
      final e = EventRecurrence(
        startsAt: start,
        freq: RecurrenceFreq.monthly,
      );

      final instances = expandInstances(
        e,
        DateTime(2024, 2, 1),
        DateTime(2024, 2, 29, 23, 59, 59),
      );

      expect(instances, hasLength(1));
      expect(instances.first.month, 2);
      expect(instances.first.day, 29);
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

  group('expandInstances — timezoned (viewer-independent instance_start)', () {
    test('timezoned weekly anchors instance_start to UTC wall-clock', () {
      // The capacity key + race-arm key for a recurring instance must be the
      // same instant for every spectator. With a timezone present the
      // expansion reads + stamps the fields in UTC, so the produced instants
      // are fixed in absolute time and don't depend on the device's zone.
      // Asserting the exact UTC ISO instants pins that under any test TZ.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 7, 13, 0, 0), // Tue 13:00 UTC
        freq: RecurrenceFreq.weekly,
        timezone: 'America/New_York',
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 4, 30, 23, 59, 59),
      );
      final iso = out.map((d) => d.toUtc().toIso8601String()).toList();
      expect(iso, [
        '2026-04-07T13:00:00.000Z',
        '2026-04-14T13:00:00.000Z',
        '2026-04-21T13:00:00.000Z',
        '2026-04-28T13:00:00.000Z',
      ]);
    });

    test('two cross-TZ viewers compute the SAME instance_start', () {
      // The bug: the .toLocal() + local-field stamp built instants in the
      // VIEWER's zone, so spectators in different zones RSVP'd against
      // different capacity keys. For a timezoned event the expansion reads no
      // ambient zone other than UTC, invariant across viewers. Re-running the
      // same input twice (standing in for two viewers) yields identical
      // instants; the absolute-time assertion guards the cross-device case
      // (the suite is also run under multiple TZ values).
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 5, 2, 23, 30, 0), // Sat 23:30 UTC — a
        freq: RecurrenceFreq.biweekly, // viewer-local stamp would roll the day.
        byday: const [Weekday.sa],
        timezone: 'Europe/London',
      );
      final from = DateTime.utc(2026, 5, 1);
      final to = DateTime.utc(2026, 5, 31, 23, 59, 59);
      final viewerA = expandInstances(e, from, to).map((d) => d.toUtc().toIso8601String()).toList();
      final viewerB = expandInstances(e, from, to).map((d) => d.toUtc().toIso8601String()).toList();
      expect(viewerA, viewerB);
      expect(viewerA, [
        '2026-05-02T23:30:00.000Z',
        '2026-05-16T23:30:00.000Z',
        '2026-05-30T23:30:00.000Z',
      ]);
    });

    test('timezoned monthly anchors day-of-month + time in UTC', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 1, 31, 22, 0, 0),
        freq: RecurrenceFreq.monthly,
        timezone: 'Australia/Sydney',
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 4, 30, 23, 59, 59),
      );
      final iso = out.map((d) => d.toUtc().toIso8601String()).toList();
      // Jan-31, Feb-28 (clamp, 2026 non-leap), Mar-31, Apr-30 — all 22:00 UTC.
      expect(iso, [
        '2026-01-31T22:00:00.000Z',
        '2026-02-28T22:00:00.000Z',
        '2026-03-31T22:00:00.000Z',
        '2026-04-30T22:00:00.000Z',
      ]);
    });

    test('legacy event with no timezone keeps viewer-local behaviour', () {
      // A row predating 20270111_001 has no timezone; expansion falls back to
      // the original local-zone stamping so already-placed RSVPs don't shift.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 7, 13, 0, 0),
        freq: RecurrenceFreq.weekly,
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 4, 30, 23, 59, 59),
      );
      expect(out, hasLength(4));
      final localStart = e.startsAt.toLocal();
      for (final inst in out) {
        expect(inst.hour, localStart.hour);
        expect(inst.isUtc, isFalse);
      }
    });
  });
}
