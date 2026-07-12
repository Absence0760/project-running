import 'package:core_models/core_models.dart';

/// Collapse same-kind + same-target notifications that arrived close
/// together into a single "Alice and N others" row. TS↔Dart parity pair
/// with apps/web/src/lib/social/notification_groups.ts — keep the
/// algorithm, edge cases, and test counts in lockstep.

/// Two notifications sharing a (kind, target) only collapse when their
/// timestamps fall within this window of each other — so a fresh kudos and
/// one from three days ago on the same run stay separate rows.
const int kNotificationGroupWindowMs = 24 * 60 * 60 * 1000;

class NotificationGroup {
  /// `${kind}|${targetKey}` — stable within a render, not across bursts.
  final String key;
  final String kind;

  /// The newest member — the row the collapsed line renders from.
  final NotificationRow lead;

  /// The remaining members, newest-first (empty for a singleton group).
  final List<NotificationRow> others;

  /// `others.length` — the "and N others" count.
  int get otherCount => others.length;

  /// How many members (lead included) are unread.
  final List<NotificationRow> _all;
  int get unreadCount => _all.where((n) => n.readAt == null).length;

  NotificationGroup._(this.key, this.kind, this.lead, this.others)
      : _all = [lead, ...others];
}

/// The entity a notification points at, so same-kind notifications on the
/// SAME entity collapse together. Kinds with no shared target (or a null
/// target id) get a per-row key so they can never merge into each other.
String _targetKeyFor(NotificationRow n) {
  final solo = 'solo:${n.id}';
  switch (n.kind) {
    case 'kudos':
    case 'comment':
    case 'comment_reply':
    case 'run_completed':
      return n.runId != null ? 'run:${n.runId}' : solo;
    case 'follow':
      // Followers all target the recipient — collapse them together.
      return 'follow';
    case 'event_rsvp':
    case 'event_cancel':
    case 'event_reminder':
      return n.eventId != null ? 'event:${n.eventId}' : solo;
    case 'club_post':
      return n.clubId != null ? 'club:${n.clubId}' : solo;
    case 'plan_update':
    case 'plan_assigned':
      return n.planId != null ? 'plan:${n.planId}' : solo;
    case 'achievement':
      return n.achievementId != null ? 'achievement:${n.achievementId}' : solo;
    case 'challenge_complete':
      return n.challengeId != null ? 'challenge:${n.challengeId}' : solo;
    case 'message':
      return n.actorId != null ? 'message:${n.actorId}' : solo;
    default:
      return solo;
  }
}

/// Effective epoch-ms for a row, clamped to [nowMs] so a clock-skewed
/// future timestamp can't sort ahead of genuinely newer rows or escape the
/// collapse window.
int _effectiveMs(NotificationRow n, int nowMs) {
  final t = n.createdAt.millisecondsSinceEpoch;
  return t < nowMs ? t : nowMs;
}

class _MutableGroup {
  final String key;
  final String kind;
  final NotificationRow lead;
  final List<NotificationRow> others = [];
  _MutableGroup(this.key, this.kind, this.lead);
}

/// Collapse a flat notification list (any order) into groups. Each group's
/// `lead` is its newest member; members further back than
/// [kNotificationGroupWindowMs] from that lead open a fresh group. Groups
/// are returned newest-lead first.
List<NotificationGroup> groupNotifications(
  List<NotificationRow> rows, {
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  final sorted = [...rows]..sort((a, b) {
      final d = _effectiveMs(b, now) - _effectiveMs(a, now);
      if (d != 0) return d;
      return a.id.compareTo(b.id) > 0 ? -1 : (a.id.compareTo(b.id) < 0 ? 1 : 0);
    });

  final groups = <_MutableGroup>[];
  final openByKey = <String, _MutableGroup>{};

  for (final row in sorted) {
    final groupKey = '${row.kind}|${_targetKeyFor(row)}';
    final open = openByKey[groupKey];
    final rowMs = _effectiveMs(row, now);
    if (open != null &&
        _effectiveMs(open.lead, now) - rowMs <= kNotificationGroupWindowMs) {
      open.others.add(row);
    } else {
      final g = _MutableGroup(groupKey, row.kind, row);
      groups.add(g);
      openByKey[groupKey] = g;
    }
  }

  return groups
      .map((g) => NotificationGroup._(g.key, g.kind, g.lead, g.others))
      .toList();
}
