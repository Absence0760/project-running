import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// The coach-athlete roster value types are part of the public api_client
/// surface (mirroring web's CoachAthleteLink / PendingCoachInvite /
/// AthleteRunSummary / ActivePlanOverview). They're built inline by the
/// fetch methods rather than via a `fromJson`, so this pins their exported
/// shape — a rename or a dropped field breaks the consuming mobile screens.
void main() {
  group('CoachAthleteLink', () {
    test('carries the link + joined-profile fields', () {
      final link = CoachAthleteLink(
        id: 'l1',
        status: 'active',
        note: 'strong climber',
        createdAt: DateTime.utc(2026, 1, 1),
        acceptedAt: DateTime.utc(2026, 1, 2),
        userId: 'athlete-1',
        displayName: 'Alice',
        avatarUrl: 'https://x/a.png',
      );
      expect(link.id, 'l1');
      expect(link.status, 'active');
      expect(link.userId, 'athlete-1');
      expect(link.displayName, 'Alice');
      expect(link.acceptedAt, DateTime.utc(2026, 1, 2));
    });

    test('tolerates null display name / avatar / note', () {
      final link = CoachAthleteLink(
        id: 'l2',
        status: 'active',
        note: null,
        createdAt: DateTime.utc(2026, 1, 1),
        acceptedAt: null,
        userId: 'coach-1',
        displayName: null,
        avatarUrl: null,
      );
      expect(link.displayName, isNull);
      expect(link.avatarUrl, isNull);
      expect(link.acceptedAt, isNull);
    });
  });

  group('PendingCoachInvite', () {
    test('carries the token + created-at', () {
      final inv = PendingCoachInvite(
        id: 'inv1',
        inviteToken: 'abc123',
        note: null,
        createdAt: DateTime.utc(2026, 1, 5),
      );
      expect(inv.inviteToken, 'abc123');
      expect(inv.createdAt, DateTime.utc(2026, 1, 5));
    });
  });

  group('AthleteRunSummary', () {
    test('carries the column-narrowed run fields (no track)', () {
      final r = AthleteRunSummary(
        id: 'r1',
        startedAt: DateTime.utc(2026, 1, 10),
        distanceM: 10000,
        durationS: 3000,
        isPublic: false,
        source: 'app',
        routeId: null,
        activityType: 'run',
        metadata: const {'activity_type': 'run'},
      );
      expect(r.distanceM, 10000);
      expect(r.durationS, 3000);
      expect(r.isPublic, isFalse);
      expect(r.activityType, 'run');
      expect(r.metadata?['activity_type'], 'run');
    });
  });
}
