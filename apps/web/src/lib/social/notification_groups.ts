// Collapse same-kind + same-target notifications that arrived close
// together into a single "Alice and N others" row. TS↔Dart parity pair
// with apps/mobile_android/lib/notification_groups.dart — keep the
// algorithm, edge cases, and test counts in lockstep.
//
// The helper is intentionally decoupled from the DB view types: it reads
// only the small set of `notifications` columns below, so a `NotificationRow`
// satisfies the input structurally and it stays unit-testable without the
// join view.

/** The subset of a `notifications` row the grouping logic reads. */
export interface GroupableNotification {
	id: string;
	kind: string;
	actor_id: string | null;
	run_id: string | null;
	event_id: string | null;
	club_id: string | null;
	plan_id: string | null;
	achievement_id: string | null;
	challenge_id: string | null;
	read_at: string | null;
	created_at: string;
}

export interface NotificationGroup {
	/** `${kind}|${targetKey}` — stable within a render, not across bursts. */
	key: string;
	kind: string;
	/** The newest member — the row the collapsed line renders from. */
	lead: GroupableNotification;
	/** The remaining members, newest-first (empty for a singleton group). */
	others: GroupableNotification[];
	/** `others.length` — the "and N others" count. */
	otherCount: number;
	/** How many members (lead included) are unread. */
	unreadCount: number;
}

/**
 * Two notifications sharing a (kind, target) only collapse when their
 * timestamps fall within this window of each other — so a fresh kudos and
 * one from three days ago on the same run stay separate rows.
 */
export const NOTIFICATION_GROUP_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * The entity a notification points at, so same-kind notifications on the
 * SAME entity collapse together. Kinds with no shared target (or a null
 * target id) get a per-row key so they can never merge into each other.
 */
function targetKeyFor(n: GroupableNotification): string {
	const solo = `solo:${n.id}`;
	switch (n.kind) {
		case 'kudos':
		case 'comment':
		case 'comment_reply':
		case 'run_completed':
			return n.run_id ? `run:${n.run_id}` : solo;
		case 'follow':
			// Followers all target the recipient — collapse them together.
			return 'follow';
		case 'event_rsvp':
		case 'event_cancel':
		case 'event_reminder':
			return n.event_id ? `event:${n.event_id}` : solo;
		case 'club_post':
			return n.club_id ? `club:${n.club_id}` : solo;
		case 'plan_update':
		case 'plan_assigned':
			return n.plan_id ? `plan:${n.plan_id}` : solo;
		case 'achievement':
			return n.achievement_id ? `achievement:${n.achievement_id}` : solo;
		case 'challenge_complete':
			return n.challenge_id ? `challenge:${n.challenge_id}` : solo;
		case 'message':
			return n.actor_id ? `message:${n.actor_id}` : solo;
		default:
			return solo;
	}
}

/**
 * Effective epoch-ms for a row, clamped to `nowMs` so a clock-skewed
 * future timestamp can't sort ahead of genuinely newer rows or escape the
 * collapse window. Unparseable timestamps fall back to `nowMs`.
 */
function effectiveMs(n: GroupableNotification, nowMs: number): number {
	const t = Date.parse(n.created_at);
	return Number.isFinite(t) ? Math.min(t, nowMs) : nowMs;
}

/**
 * Collapse a flat notification list (any order) into groups. Each group's
 * `lead` is its newest member; members further back than
 * `NOTIFICATION_GROUP_WINDOW_MS` from that lead open a fresh group. Groups
 * are returned newest-lead first.
 */
export function groupNotifications(
	rows: GroupableNotification[],
	nowMs: number = Date.now(),
): NotificationGroup[] {
	const sorted = [...rows].sort((a, b) => {
		const d = effectiveMs(b, nowMs) - effectiveMs(a, nowMs);
		return d !== 0 ? d : a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
	});

	const groups: NotificationGroup[] = [];
	const openByKey = new Map<string, NotificationGroup>();

	for (const row of sorted) {
		const groupKey = `${row.kind}|${targetKeyFor(row)}`;
		const open = openByKey.get(groupKey);
		const rowMs = effectiveMs(row, nowMs);
		if (open && effectiveMs(open.lead, nowMs) - rowMs <= NOTIFICATION_GROUP_WINDOW_MS) {
			open.others.push(row);
			open.otherCount = open.others.length;
			if (row.read_at == null) open.unreadCount += 1;
		} else {
			const group: NotificationGroup = {
				key: groupKey,
				kind: row.kind,
				lead: row,
				others: [],
				otherCount: 0,
				unreadCount: row.read_at == null ? 1 : 0,
			};
			groups.push(group);
			openByKey.set(groupKey, group);
		}
	}

	return groups;
}
