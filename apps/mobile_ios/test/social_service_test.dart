import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

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
/// by the iceberg note in `docs/testing.md § What's not covered`.

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
}
