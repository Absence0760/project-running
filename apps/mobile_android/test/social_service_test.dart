import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/event_gym_template.dart';
import '../lib/recurrence.dart';
import '../lib/social_service.dart';

/// Pure-unit coverage for the value classes and helpers that
/// `SocialService` exposes. These are the surfaces that drive
/// authorization affordances on the social screens (admin-only buttons,
/// event-organiser controls, race-director Arm/Fire). A regression in
/// `ClubView.isAdmin` would either lock admins out of their club or —
/// worse — expose admin controls to a non-admin viewer; either way
/// the screen test wouldn't catch it because the screen reads the bool.
///
/// Anything that hits Supabase directly (browseClubs, fetchMyClubs, the
/// _enrichClubs / _enrichEvents pipelines, RSVP writes) is NOT covered
/// here — `SocialService` resolves `Supabase.instance.client` inline,
/// so testing those branches needs a DI seam refactor first. Tracked
/// by the iceberg note in `docs/testing/testing.md § What's not covered`.

ClubRow _row(String id, {int memberCount = 1}) => ClubRow(
      id: id,
      slug: 'club-$id',
      name: 'Club $id',
      description: null,
      locationLabel: null,
      isPublic: true,
      joinPolicy: 'open',
      ownerId: 'owner-1',
      createdAt: DateTime(2026, 1, 1),
      memberCount: memberCount,
      isVerified: false,
      requiresActivityWaiver: false,
    );

ClubView _view({
  required String? viewerRole,
  String? viewerStatus,
  int memberCount = 1,
  String joinPolicy = 'open',
}) {
  return ClubView(
    row: _row('a'),
    memberCount: memberCount,
    viewerRole: viewerRole,
    viewerStatus: viewerStatus,
    joinPolicy: joinPolicy,
  );
}

void main() {
  group('ClubView role helpers', () {
    test('viewerRole == "owner" → isAdmin / isMember / isEventOrganiser / isRaceDirector', () {
      final v = _view(viewerRole: 'owner');
      expect(v.isAdmin, isTrue);
      expect(v.isMember, isTrue);
      expect(v.isEventOrganiser, isTrue,
          reason: 'admins inherit event-organiser affordances');
      expect(v.isRaceDirector, isTrue,
          reason: 'admins inherit race-director affordances');
    });

    test('viewerRole == "admin" → same as owner', () {
      final v = _view(viewerRole: 'admin');
      expect(v.isAdmin, isTrue);
      expect(v.isEventOrganiser, isTrue);
      expect(v.isRaceDirector, isTrue);
      expect(v.isMember, isTrue);
    });

    test('viewerRole == "event_organiser" → only event affordances', () {
      final v = _view(viewerRole: 'event_organiser');
      expect(v.isAdmin, isFalse);
      expect(v.isEventOrganiser, isTrue);
      expect(v.isRaceDirector, isFalse);
      expect(v.isMember, isTrue);
    });

    test('viewerRole == "race_director" → only race-director affordances', () {
      final v = _view(viewerRole: 'race_director');
      expect(v.isAdmin, isFalse);
      expect(v.isEventOrganiser, isFalse);
      expect(v.isRaceDirector, isTrue);
      expect(v.isMember, isTrue);
    });

    test('viewerRole == "member" → member only, no affordances', () {
      final v = _view(viewerRole: 'member');
      expect(v.isAdmin, isFalse);
      expect(v.isEventOrganiser, isFalse);
      expect(v.isRaceDirector, isFalse);
      expect(v.isMember, isTrue);
    });

    test('viewerRole == null → not a member, no affordances', () {
      final v = _view(viewerRole: null);
      expect(v.isAdmin, isFalse);
      expect(v.isEventOrganiser, isFalse);
      expect(v.isRaceDirector, isFalse);
      expect(v.isMember, isFalse);
    });

    test('unknown viewerRole string → treated as not-admin but is-member', () {
      // viewerRole is a String? from the DB; an unrecognised value
      // (a future role we haven't taught the client about yet) is
      // safer to treat as "member with no special affordances" than
      // "admin". This pin prevents a careless `||` from sliding in.
      final v = _view(viewerRole: 'mystery_role');
      expect(v.isAdmin, isFalse);
      expect(v.isEventOrganiser, isFalse);
      expect(v.isRaceDirector, isFalse);
      expect(v.isMember, isTrue,
          reason: 'any non-null viewerRole still implies membership');
    });
  });

  group('parseBydayCodes', () {
    test('jsonb-array of weekday codes returns parsed Weekday list', () {
      final r = parseBydayCodes(['MO', 'WE', 'FR']);
      expect(r, [Weekday.mo, Weekday.we, Weekday.fr]);
    });

    test('preserves order and duplicates (caller can dedupe if needed)', () {
      final r = parseBydayCodes(['TU', 'TU', 'MO']);
      expect(r, [Weekday.tu, Weekday.tu, Weekday.mo]);
    });

    test('non-array input returns null', () {
      expect(parseBydayCodes(null), isNull);
      expect(parseBydayCodes('MO'), isNull);
      expect(parseBydayCodes({'days': 'MO'}), isNull);
      expect(parseBydayCodes(42), isNull);
    });

    test('empty array returns null (caller treats as "no override")', () {
      expect(parseBydayCodes(<dynamic>[]), isNull);
    });

    test('array of all-unknown codes returns null', () {
      // Same shape as empty: a recurrence with zero-recognised days
      // shouldn't constrain instance generation any differently from
      // having no byday clause at all.
      expect(parseBydayCodes(['XX', 'YY']), isNull);
    });

    test('mixed known + unknown codes filters to known only', () {
      final r = parseBydayCodes(['MO', 'XX', 'FR']);
      expect(r, [Weekday.mo, Weekday.fr]);
    });
  });

  group('ClubView convenience getters', () {
    test('memberCount / joinPolicy / viewerStatus surface as constructed', () {
      final v = _view(
        viewerRole: 'member',
        viewerStatus: 'pending',
        memberCount: 42,
        joinPolicy: 'request',
      );
      expect(v.memberCount, 42);
      expect(v.joinPolicy, 'request');
      expect(v.viewerStatus, 'pending');
    });
  });

  group('SocialService.buildCreateClubBody', () {
    test('trims name and collapses blank description/location to null', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: 'owner-1',
        name: '  Hackney Half  ',
        slug: 'hackney-half',
        description: '   ',
        locationLabel: '',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(body['owner_id'], 'owner-1');
      expect(body['name'], 'Hackney Half');
      expect(body['slug'], 'hackney-half');
      expect(body['description'], isNull);
      expect(body['location_label'], isNull);
      expect(body['is_public'], isTrue);
      expect(body['join_policy'], 'open');
    });

    test('keeps non-blank description/location trimmed', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: 'o',
        name: 'C',
        slug: 'c',
        description: '  We run.  ',
        locationLabel: '  London  ',
        isPublic: false,
        joinPolicy: 'invite',
      );
      expect(body['description'], 'We run.');
      expect(body['location_label'], 'London');
      expect(body['is_public'], isFalse);
    });

    test('invite-only club carries the supplied token; open club has null', () {
      final invite = SocialService.buildCreateClubBody(
        ownerId: 'o',
        name: 'C',
        slug: 'c',
        isPublic: false,
        joinPolicy: 'invite',
        inviteToken: 'deadbeef',
      );
      expect(invite['invite_token'], 'deadbeef');
      final open = SocialService.buildCreateClubBody(
        ownerId: 'o',
        name: 'C',
        slug: 'c',
        isPublic: true,
        joinPolicy: 'open',
      );
      expect(open['invite_token'], isNull);
    });

    test('normalises http(s) links and drops non-http(s) ones (XSS guard)', () {
      final body = SocialService.buildCreateClubBody(
        ownerId: 'o',
        name: 'C',
        slug: 'c',
        isPublic: true,
        joinPolicy: 'open',
        websiteUrl: 'https://example.com',
        instagramUrl: ' javascript:alert(1) ',
        stravaUrl: 'data:text/html,evil',
        facebookUrl: '   ',
      );
      expect(body['website_url'], 'https://example.com');
      // A javascript:/data: URL must not survive to the DB.
      expect(body['instagram_url'], isNull);
      expect(body['strava_url'], isNull);
      expect(body['facebook_url'], isNull);
    });
  });

  group('SocialService.normaliseClubLink', () {
    test('returns null for empty / whitespace input', () {
      expect(SocialService.normaliseClubLink(null), isNull);
      expect(SocialService.normaliseClubLink(''), isNull);
      expect(SocialService.normaliseClubLink('   '), isNull);
    });

    test('accepts http and https case-insensitively, trimming surrounds', () {
      expect(SocialService.normaliseClubLink('  https://a.com '), 'https://a.com');
      expect(SocialService.normaliseClubLink('HTTP://a.com'), 'HTTP://a.com');
    });

    test('rejects javascript: / data: / scheme-less input', () {
      expect(SocialService.normaliseClubLink('javascript:alert(1)'), isNull);
      expect(SocialService.normaliseClubLink('data:text/html,x'), isNull);
      expect(SocialService.normaliseClubLink('example.com'), isNull);
      expect(SocialService.normaliseClubLink('ftp://a.com'), isNull);
    });
  });

  group('SocialService.genInviteToken', () {
    test('produces 32 lowercase hex chars', () {
      final t = SocialService.genInviteToken(rng: Random(1));
      expect(t.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(t), isTrue);
    });

    test('is deterministic under a seeded RNG (testability seam)', () {
      final a = SocialService.genInviteToken(rng: Random(7));
      final b = SocialService.genInviteToken(rng: Random(7));
      expect(a, b);
    });

    test('differs across distinct seeds', () {
      final a = SocialService.genInviteToken(rng: Random(1));
      final b = SocialService.genInviteToken(rng: Random(2));
      expect(a, isNot(b));
    });
  });

  group('SocialService.buildCreateEventBody', () {
    test('a run (athletic) event keeps route/distance/pace and nulls class fields',
        () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: '  Saturday 5k  ',
        startsAt: DateTime.utc(2026, 6, 20, 9),
        category: 'run',
        discipline: 'should-be-dropped',
        routeId: 'route-9',
        distanceM: 5000,
        paceTargetSec: 300,
      );
      expect(body['title'], 'Saturday 5k');
      expect(body['category'], 'run');
      expect(body['route_id'], 'route-9');
      expect(body['distance_m'], 5000);
      expect(body['pace_target_sec'], 300);
      // discipline / gym_template are class-only.
      expect(body['discipline'], isNull);
      expect(body['gym_template'], isNull);
    });

    test('a social (non-athletic) event nulls route/distance/pace', () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'Pub night',
        startsAt: DateTime.utc(2026, 6, 20, 19),
        category: 'social',
        routeId: 'route-9',
        distanceM: 5000,
        paceTargetSec: 300,
      );
      expect(body['route_id'], isNull);
      expect(body['distance_m'], isNull);
      expect(body['pace_target_sec'], isNull);
    });

    test('a class event keeps discipline + builds the gym_template jsonb', () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'Reformer Pilates',
        startsAt: DateTime.utc(2026, 6, 20, 18),
        category: 'class',
        discipline: '  Pilates  ',
        gymTemplate:
            const EventGymTemplate(discipline: 'Pilates', durationMin: 45),
        // athletic fields are dropped for a class
        distanceM: 5000,
      );
      expect(body['category'], 'class');
      expect(body['discipline'], 'Pilates');
      expect(body['distance_m'], isNull);
      final tmpl = body['gym_template'] as Map<String, dynamic>;
      expect(tmpl['discipline'], 'Pilates');
      expect(tmpl['duration_min'], 45);
    });

    test('a class with a null gymTemplate writes a null gym_template', () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'Yoga',
        startsAt: DateTime.utc(2026, 6, 20, 18),
        category: 'class',
        discipline: 'Vinyasa',
      );
      expect(body['discipline'], 'Vinyasa');
      expect(body['gym_template'], isNull);
    });

    test('recurrence fields round-trip (byday list, until ISO, count, freq)',
        () {
      final until = DateTime.utc(2026, 12, 31);
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'Weekly tempo',
        startsAt: DateTime.utc(2026, 6, 16, 18),
        recurrenceFreq: 'weekly',
        recurrenceByDay: ['TU'],
        recurrenceUntil: until,
        recurrenceCount: 12,
      );
      expect(body['recurrence_freq'], 'weekly');
      expect(body['recurrence_byday'], ['TU']);
      expect(body['recurrence_until'], until.toIso8601String());
      expect(body['recurrence_count'], 12);
    });

    test('collapses blank description / meetLabel to null', () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'X',
        startsAt: DateTime.utc(2026, 6, 16, 18),
        description: '   ',
        meetLabel: '',
      );
      expect(body['description'], isNull);
      expect(body['meet_label'], isNull);
    });

    test('honours isPublic=false for a members-only event', () {
      final body = SocialService.buildCreateEventBody(
        authorId: 'a',
        clubId: 'club-1',
        title: 'X',
        startsAt: DateTime.utc(2026, 6, 16, 18),
        isPublic: false,
      );
      expect(body['is_public'], isFalse);
    });
  });

  group('EventView.toRecurrence / freq', () {
    EventRow eventRow({String? freq}) => EventRow(
          id: 'e1',
          clubId: 'c1',
          title: 'T',
          startsAt: DateTime.utc(2026, 6, 16, 18),
          authorId: 'a',
          category: 'run',
          isPublic: true,
          recurrenceFreq: freq,
        );

    test('non-recurring event → null freq, recurrence carries no freq', () {
      final v = EventView(
        row: eventRow(),
        byday: null,
        attendeeCount: 0,
        viewerRsvp: null,
        nextInstanceStart: DateTime.utc(2026, 6, 16, 18),
      );
      expect(v.freq, isNull);
      expect(v.toRecurrence().freq, isNull);
    });

    test('weekly event → freq parsed + threaded into the recurrence', () {
      final v = EventView(
        row: eventRow(freq: 'weekly'),
        byday: const [Weekday.tu],
        attendeeCount: 0,
        viewerRsvp: 'going',
        nextInstanceStart: DateTime.utc(2026, 6, 16, 18),
      );
      expect(v.freq, RecurrenceFreq.weekly);
      final rec = v.toRecurrence();
      expect(rec.freq, RecurrenceFreq.weekly);
      expect(rec.byday, const [Weekday.tu]);
      expect(rec.startsAt, v.row.startsAt);
    });
  });

  group('hashHue', () {
    test('stays in [0, 360) and is deterministic per id', () {
      for (final id in ['a', 'user-123', 'ZZZ', '😀']) {
        final h = hashHue(id);
        expect(h, inInclusiveRange(0, 359));
        expect(hashHue(id), h, reason: 'same id hashes to the same hue');
      }
    });

    test('different ids generally differ (avatar colour-diffing)', () {
      expect(hashHue('alice') == hashHue('bob'), isFalse);
    });
  });

  group('initialFor', () {
    test('uppercases the first letter', () {
      expect(initialFor('alice'), 'A');
      expect(initialFor('Bob'), 'B');
    });

    test('null / empty / whitespace falls back to "?"', () {
      expect(initialFor(null), '?');
      expect(initialFor(''), '?');
      expect(initialFor('   '), '?');
    });

    test('trims leading whitespace before taking the initial', () {
      expect(initialFor('  zed'), 'Z');
    });
  });

  group('fmtPace', () {
    test('null → empty string', () {
      expect(fmtPace(null), '');
    });

    test('formats sec/km as m:ss /km with zero-padded seconds', () {
      expect(fmtPace(300), '5:00 /km');
      expect(fmtPace(305), '5:05 /km');
      expect(fmtPace(65), '1:05 /km');
    });
  });
}
