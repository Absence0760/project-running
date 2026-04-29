/**
 * Reactive store for the notifications bell badge (decisions §38).
 *
 * Holds the unread count + an optimistic decrement when the user
 * marks something read. Single source of truth for the layout-level
 * bell + the standalone /notifications page so they stay in sync
 * without prop drilling.
 *
 * Refresh triggers:
 *   - on auth-ready (initial paint)
 *   - on window focus (covers the "left tab open, came back later"
 *     case without a polling timer)
 *   - explicit `refresh()` after the bell popover or /notifications
 *     page modifies state
 */
import { fetchUnreadNotificationCount } from '$lib/data';
import { auth } from './auth.svelte';

class NotificationStore {
	unreadCount = $state(0);
	loading = $state(false);

	async refresh() {
		if (!auth.user?.id) {
			this.unreadCount = 0;
			return;
		}
		this.loading = true;
		try {
			this.unreadCount = await fetchUnreadNotificationCount();
		} catch (e) {
			console.warn('notification refresh failed', e);
		} finally {
			this.loading = false;
		}
	}

	/// Optimistic decrement when the UI marks one read. Bounded at 0
	/// to handle the edge case where two tabs race against the same
	/// row (the second decrement would otherwise underflow).
	decrement(by = 1) {
		this.unreadCount = Math.max(0, this.unreadCount - by);
	}

	clear() {
		this.unreadCount = 0;
	}
}

export const notificationStore = new NotificationStore();
