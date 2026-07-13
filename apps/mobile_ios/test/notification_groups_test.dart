import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/notification_groups.dart';

final now = DateTime.parse('2026-07-12T12:00:00.000Z').millisecondsSinceEpoch;

DateTime ago(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(now - ms, isUtc: true);

int _seq = 0;
NotificationRow n({
  String? id,
  String kind = 'kudos',
  String? actorId,
  String? runId,
  String? eventId,
  String? clubId,
  String? planId,
  String? achievementId,
  String? challengeId,
  DateTime? readAt,
  DateTime? createdAt,
}) {
  _seq += 1;
  return NotificationRow(
    id: id ?? 'id-$_seq',
    userId: 'me',
    kind: kind,
    actorId: actorId,
    runId: runId,
    eventId: eventId,
    clubId: clubId,
    planId: planId,
    achievementId: achievementId,
    challengeId: challengeId,
    readAt: readAt,
    createdAt: createdAt ?? ago(0),
  );
}

void main() {
  group('groupNotifications', () {
    test('empty input yields no groups', () {
      expect(groupNotifications(const [], nowMs: now), isEmpty);
    });

    test('a single notification is a group of one', () {
      final groups =
          groupNotifications([n(id: 'a', kind: 'follow')], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].lead.id, 'a');
      expect(groups[0].otherCount, 0);
      expect(groups[0].others, isEmpty);
      expect(groups[0].unreadCount, 1);
    });

    test('same kind + same run within window collapses, lead is newest', () {
      final groups = groupNotifications([
        n(id: 'old', kind: 'kudos', runId: 'r1', actorId: 'u1', createdAt: ago(2000)),
        n(id: 'new', kind: 'kudos', runId: 'r1', actorId: 'u2', createdAt: ago(1000)),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].lead.id, 'new');
      expect(groups[0].otherCount, 1);
      expect(groups[0].others.map((o) => o.id).toList(), ['old']);
    });

    test('same kind on different runs stays separate', () {
      final groups = groupNotifications([
        n(id: 'a', kind: 'kudos', runId: 'r1'),
        n(id: 'b', kind: 'kudos', runId: 'r2'),
      ], nowMs: now);
      expect(groups.length, 2);
      expect(groups.map((g) => g.otherCount).toList(), [0, 0]);
    });

    test('different kinds on the same run do not merge', () {
      final groups = groupNotifications([
        n(id: 'k', kind: 'kudos', runId: 'r1'),
        n(id: 'c', kind: 'comment', runId: 'r1'),
      ], nowMs: now);
      expect(groups.length, 2);
    });

    test('same run beyond the window opens a fresh group', () {
      final groups = groupNotifications([
        n(id: 'new', kind: 'kudos', runId: 'r1', createdAt: ago(1000)),
        n(
          id: 'old',
          kind: 'kudos',
          runId: 'r1',
          createdAt: ago(kNotificationGroupWindowMs + 5000),
        ),
      ], nowMs: now);
      expect(groups.length, 2);
      expect(groups[0].lead.id, 'new');
      expect(groups[1].lead.id, 'old');
    });

    test('window boundary is inclusive', () {
      final groups = groupNotifications([
        n(id: 'new', kind: 'kudos', runId: 'r1', createdAt: ago(0)),
        n(
          id: 'edge',
          kind: 'kudos',
          runId: 'r1',
          createdAt: ago(kNotificationGroupWindowMs),
        ),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].otherCount, 1);
    });

    test('unreadCount counts only unread members', () {
      final groups = groupNotifications([
        n(id: 'a', kind: 'kudos', runId: 'r1', createdAt: ago(1000), readAt: null),
        n(id: 'b', kind: 'kudos', runId: 'r1', createdAt: ago(2000), readAt: ago(500)),
        n(id: 'c', kind: 'kudos', runId: 'r1', createdAt: ago(3000), readAt: null),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].otherCount, 2);
      expect(groups[0].unreadCount, 2);
    });

    test('follows collapse regardless of actor', () {
      final groups = groupNotifications([
        n(id: 'f1', kind: 'follow', actorId: 'u1', createdAt: ago(1000)),
        n(id: 'f2', kind: 'follow', actorId: 'u2', createdAt: ago(2000)),
        n(id: 'f3', kind: 'follow', actorId: 'u3', createdAt: ago(3000)),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].otherCount, 2);
    });

    test('event RSVPs collapse per event, distinct events split', () {
      final groups = groupNotifications([
        n(id: 'e1a', kind: 'event_rsvp', eventId: 'ev1', createdAt: ago(1000)),
        n(id: 'e1b', kind: 'event_rsvp', eventId: 'ev1', createdAt: ago(2000)),
        n(id: 'e2a', kind: 'event_rsvp', eventId: 'ev2', createdAt: ago(1500)),
      ], nowMs: now);
      expect(groups.length, 2);
      final ev1 = groups.firstWhere((g) => g.lead.eventId == 'ev1');
      expect(ev1.otherCount, 1);
    });

    test('club posts collapse per club', () {
      final groups = groupNotifications([
        n(id: 'p1', kind: 'club_post', clubId: 'c1', createdAt: ago(1000)),
        n(id: 'p2', kind: 'club_post', clubId: 'c1', createdAt: ago(2000)),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].otherCount, 1);
    });

    test('messages collapse per actor, distinct actors split', () {
      final groups = groupNotifications([
        n(id: 'm1', kind: 'message', actorId: 'u1', createdAt: ago(1000)),
        n(id: 'm2', kind: 'message', actorId: 'u1', createdAt: ago(2000)),
        n(id: 'm3', kind: 'message', actorId: 'u2', createdAt: ago(1500)),
      ], nowMs: now);
      expect(groups.length, 2);
      final u1 = groups.firstWhere((g) => g.lead.actorId == 'u1');
      expect(u1.otherCount, 1);
    });

    test('a null target never merges two rows', () {
      final groups = groupNotifications([
        n(id: 'a', kind: 'kudos', runId: null, createdAt: ago(1000)),
        n(id: 'b', kind: 'kudos', runId: null, createdAt: ago(2000)),
      ], nowMs: now);
      expect(groups.length, 2);
      expect(groups.map((g) => g.otherCount).toList(), [0, 0]);
    });

    test('groups are ordered newest-lead first', () {
      final groups = groupNotifications([
        n(id: 'older', kind: 'kudos', runId: 'r1', createdAt: ago(5000)),
        n(id: 'newer', kind: 'comment', runId: 'r2', createdAt: ago(1000)),
      ], nowMs: now);
      expect(groups.map((g) => g.lead.id).toList(), ['newer', 'older']);
    });

    test('a clock-skewed future row clamps to now and leads the burst', () {
      final groups = groupNotifications([
        n(id: 'past', kind: 'kudos', runId: 'r1', createdAt: ago(2000)),
        n(
          id: 'future',
          kind: 'kudos',
          runId: 'r1',
          createdAt: DateTime.fromMillisecondsSinceEpoch(now + 60000, isUtc: true),
        ),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].lead.id, 'future');
      expect(groups[0].otherCount, 1);
    });

    test('unsorted input still finds the true newest lead', () {
      final groups = groupNotifications([
        n(id: 'mid', kind: 'kudos', runId: 'r1', createdAt: ago(2000)),
        n(id: 'newest', kind: 'kudos', runId: 'r1', createdAt: ago(500)),
        n(id: 'oldest', kind: 'kudos', runId: 'r1', createdAt: ago(4000)),
      ], nowMs: now);
      expect(groups.length, 1);
      expect(groups[0].lead.id, 'newest');
      expect(groups[0].others.map((o) => o.id).toList(), ['mid', 'oldest']);
    });

    test('achievements group by id, a null id stays solo', () {
      final groups = groupNotifications([
        n(id: 'a1', kind: 'achievement', achievementId: 'ach1', createdAt: ago(1000)),
        n(id: 'a2', kind: 'achievement', achievementId: 'ach1', createdAt: ago(2000)),
        n(id: 'a3', kind: 'achievement', achievementId: null, createdAt: ago(1500)),
        n(id: 'a4', kind: 'achievement', achievementId: null, createdAt: ago(2500)),
      ], nowMs: now);
      expect(groups.length, 3);
      final ach1 = groups.firstWhere((g) => g.lead.achievementId == 'ach1');
      expect(ach1.otherCount, 1);
    });
  });
}
