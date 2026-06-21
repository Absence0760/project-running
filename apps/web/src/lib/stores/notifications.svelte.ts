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
 *   - a Supabase Realtime subscription on the user's notification rows,
 *     so a kudos / comment / follow arriving while the tab is open bumps
 *     the badge live without waiting for a focus event
 *   - explicit `refresh()` after the bell popover or /notifications
 *     page modifies state
 */
import type { RealtimeChannel } from '@supabase/supabase-js';
import { fetchUnreadNotificationCount } from '$lib/core/data';
import { supabase } from '$lib/core/supabase';
import { auth } from './auth.svelte';

class NotificationStore {
	unreadCount = $state(0);
	loading = $state(false);
	#channel: RealtimeChannel | null = null;

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

	/// Optimistic "all read" — zeroes the badge but keeps the Realtime
	/// channel live so a notification arriving after a mark-all still
	/// bumps the badge. Distinct from `clear()`, which is the logout-only
	/// teardown that also drops the subscription.
	markAllRead() {
		this.unreadCount = 0;
	}

	/// Subscribe to live changes on this user's notification rows. INSERT
	/// (always unread on creation) bumps the badge immediately; UPDATE /
	/// DELETE (read or dismissed, possibly from another tab) re-read the
	/// authoritative count. Idempotent — a second call tears the prior
	/// channel down first.
	subscribe(userId: string) {
		this.unsubscribe();
		this.#channel = supabase
			.channel(`notifications:${userId}`)
			.on(
				'postgres_changes',
				{ event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
				() => {
					this.unreadCount += 1;
				},
			)
			.on(
				'postgres_changes',
				{ event: 'UPDATE', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
				() => {
					void this.refresh();
				},
			)
			.on(
				'postgres_changes',
				{ event: 'DELETE', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
				() => {
					void this.refresh();
				},
			)
			.subscribe();
	}

	unsubscribe() {
		if (this.#channel) {
			void supabase.removeChannel(this.#channel);
			this.#channel = null;
		}
	}

	clear() {
		this.unsubscribe();
		this.unreadCount = 0;
	}
}

export const notificationStore = new NotificationStore();
