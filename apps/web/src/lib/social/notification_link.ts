// Single source of truth for the notification → deep-link routing. The bell
// popover and the full inbox list both turn a NotificationView into the href a
// click should navigate to; the two switch statements used to be byte-identical
// copies, so a new NotificationKind meant editing the same routing table twice
// (the drift the notification_kind_coverage guard was pinning). Extracted here
// so the routing lives — and is unit-tested — once. verbFor stays per-component
// because its message keys are namespaced (notificationBell.* vs
// notificationsList.*); only the pure href mapping is shared.
//
// Typed against a structural subset of NotificationView so this module stays
// free of a runtime import from core/data.ts and remains tsx-testable.
export interface NotificationLinkInput {
	row: {
		kind: string;
		run_id: string | null;
		actor_id: string | null;
		event_id: string | null;
		plan_id: string | null;
		achievement_id: string | null;
		challenge_id: string | null;
	};
	event_club_slug: string | null;
	club_slug: string | null;
}

export function notificationLinkFor(item: NotificationLinkInput): string | null {
	const r = item.row;
	switch (r.kind) {
		case 'kudos':
		case 'comment':
		case 'comment_reply':
			return r.run_id ? `/runs/${r.run_id}` : null;
		case 'follow':
			return r.actor_id ? `/u/${r.actor_id}` : null;
		case 'event_rsvp':
		case 'event_cancel':
		case 'event_reminder':
			return r.event_id && item.event_club_slug
				? `/clubs/${item.event_club_slug}/events/${r.event_id}`
				: null;
		case 'plan_update':
		case 'plan_assigned':
			return r.plan_id ? `/plans/${r.plan_id}` : null;
		case 'message':
			return r.actor_id ? `/messages/${r.actor_id}` : null;
		case 'club_post':
			return item.club_slug ? `/clubs/${item.club_slug}` : null;
		case 'run_completed':
			return r.run_id ? `/share/run/${r.run_id}` : null;
		case 'achievement':
			return r.achievement_id ? `/share/badge/${r.achievement_id}` : null;
		case 'challenge_complete':
			return r.challenge_id ? `/challenges/${r.challenge_id}` : null;
		case 'content_hidden':
			return null;
		default:
			return null;
	}
}
