import 'package:flutter_test/flutter_test.dart';

import '../lib/social_service.dart';

/// Parity tests for `SocialService.createEvent` — the insert-body
/// shape must match `apps/web/src/lib/data.ts:createEvent` so events
/// created on either platform store identically.
///
/// History: mobile + web diverged in four ways before this round
///   1. Mobile didn't trim `title` — web does `input.title.trim()`.
///   2. Mobile didn't normalise `description` or `meet_label` to
///      trim-then-null. Whitespace-only inputs survived to the DB.
///   3. Mobile took `recurrenceByDay` as `String?` and sent a bare
///      string into a `text[]` column. Postgrest doesn't auto-coerce,
///      so the recurrence rule was either rejected or silently
///      dropped — every mobile-created recurring event before this
///      fix landed has a NULL `recurrence_byday`.
///   4. Mobile had no `recurrenceCount` parameter, even though the
///      column exists and web supports the "end after N occurrences"
///      form of the recurrence rule.
void main() {
  const userId = 'user-abc-123';
  const clubId = 'club-xyz';
  final startsAt = DateTime.utc(2026, 6, 1, 9, 30);

  group('buildCreateEventBody — text-field normalisation (parity with web)',
      () {
    test('title is trimmed', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: '  Saturday parkrun  ',
        startsAt: startsAt,
      );
      expect(body['title'], 'Saturday parkrun');
    });

    test('null description stays null', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
      );
      expect(body['description'], isNull);
    });

    test('whitespace-only description collapses to null', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        description: '  \n\t  ',
      );
      expect(body['description'], isNull);
    });

    test('non-empty description is trimmed but preserved', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        description: '  Bring water  ',
      );
      expect(body['description'], 'Bring water');
    });

    test('meet_label follows the same trim/null contract', () {
      final blank = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        meetLabel: '   ',
      );
      expect(blank['meet_label'], isNull);

      final populated = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        meetLabel: '  Hackney Marshes car park  ',
      );
      expect(populated['meet_label'], 'Hackney Marshes car park');
    });
  });

  group(
      'buildCreateEventBody — recurrence_byday type (the silent-failure bug)',
      () {
    // The pre-fix mobile signature took `String?` and shoved a bare
    // weekday code like `"MO"` into a `text[]` column. Postgrest
    // doesn't auto-coerce string → array, so the recurrence rule was
    // either rejected or dropped. Both forms of the bug have the same
    // observable symptom: the event saves but no instances expand.
    test('null recurrenceByDay → null in body', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
      );
      expect(body['recurrence_byday'], isNull);
    });

    test('single-weekday byday is written as a one-element List<String>', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        recurrenceByDay: ['MO'],
      );
      expect(body['recurrence_byday'], isA<List<String>>());
      expect(body['recurrence_byday'], equals(<String>['MO']));
    });

    test('multi-weekday byday round-trips intact', () {
      // Web supports an array of weekday codes for "twice a week"
      // rules. Pin that the helper preserves order and content.
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        recurrenceByDay: ['MO', 'WE', 'FR'],
      );
      expect(body['recurrence_byday'], equals(<String>['MO', 'WE', 'FR']));
    });
  });

  group('buildCreateEventBody — recurrence_count parity', () {
    test('null recurrenceCount → null in body', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
      );
      expect(body['recurrence_count'], isNull);
    });

    test('non-null recurrenceCount is written through', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        recurrenceFreq: 'weekly',
        recurrenceByDay: ['SA'],
        recurrenceCount: 12,
      );
      expect(body['recurrence_count'], 12);
    });
  });

  group('buildCreateEventBody — canonical column set + timestamps', () {
    test('starts_at is serialised as an ISO-8601 string', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: DateTime.utc(2026, 6, 1, 9, 30, 15),
      );
      expect(body['starts_at'], '2026-06-01T09:30:15.000Z');
    });

    test('recurrence_until is serialised as an ISO-8601 string when set', () {
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
        recurrenceUntil: DateTime.utc(2026, 12, 31),
      );
      expect(body['recurrence_until'], '2026-12-31T00:00:00.000Z');
    });

    test('every optional column appears in the body (even when null) — '
        'matches web\'s `?? null` defaults', () {
      // Web sets every column on insert via `?? null` so the row's
      // shape is fixed. Mobile's previous body used `if (x != null)`
      // gates which meant some optional fields just weren't present
      // and relied on DB-side defaults. Aligning on "always emit the
      // key" makes the two clients write identical rows.
      final body = SocialService.buildCreateEventBody(
        authorId: userId,
        clubId: clubId,
        title: 'T',
        startsAt: startsAt,
      );
      for (final key in const [
        'club_id',
        'title',
        'description',
        'starts_at',
        'duration_min',
        'meet_label',
        'meet_lat',
        'meet_lng',
        'route_id',
        'distance_m',
        'pace_target_sec',
        'capacity',
        'author_id',
        'recurrence_freq',
        'recurrence_byday',
        'recurrence_until',
        'recurrence_count',
      ]) {
        expect(body.containsKey(key), isTrue,
            reason: 'Column "$key" must always appear in the insert '
                'body so web and mobile write identical row shapes.');
      }
    });
  });
}
