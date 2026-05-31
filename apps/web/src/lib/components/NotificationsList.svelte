<script lang="ts">
	import { onMount } from 'svelte';
	import { initial } from '$lib/avatar';
	import { goto } from '$app/navigation';
	import {
		fetchNotifications,
		markNotificationRead,
		markAllNotificationsRead,
		deleteNotification,
		type NotificationView,
	} from '$lib/data';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { fmtKm } from '$lib/units.svelte';

	let items = $state<NotificationView[]>([]);
	let loading = $state(true);
	let filter = $state<'all' | 'unread'>('all');

	async function load() {
		loading = true;
		try {
			items = await fetchNotifications(100);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	let visible = $derived(
		filter === 'unread' ? items.filter((x) => x.row.read_at == null) : items,
	);

	async function open(item: NotificationView) {
		const wasUnread = item.row.read_at == null;
		if (wasUnread) {
			notificationStore.decrement();
			items = items.map((x) =>
				x.row.id === item.row.id
					? { ...x, row: { ...x.row, read_at: new Date().toISOString() } }
					: x,
			);
			markNotificationRead(item.row.id).catch((e) => console.warn('mark read failed', e));
		}
		const href = linkFor(item);
		if (href) goto(href);
	}

	async function handleMarkAll() {
		try {
			await markAllNotificationsRead();
			notificationStore.clear();
			items = items.map((x) => ({
				...x,
				row: { ...x.row, read_at: x.row.read_at ?? new Date().toISOString() },
			}));
		} catch (e) {
			showToast(`Failed to mark all read: ${e}`, 'error');
		}
	}

	async function remove(id: string, event: Event) {
		event.stopPropagation();
		const target = items.find((x) => x.row.id === id);
		const wasUnread = target?.row.read_at == null;
		items = items.filter((x) => x.row.id !== id);
		if (wasUnread) notificationStore.decrement();
		try {
			await deleteNotification(id);
		} catch (e) {
			showToast(`Failed to delete: ${e}`, 'error');
			await load();
		}
	}

	function linkFor(item: NotificationView): string | null {
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
				return r.event_id && item.event_club_slug
					? `/clubs/${item.event_club_slug}/events/${r.event_id}`
					: null;
			case 'plan_update':
				return r.plan_id ? `/plans/${r.plan_id}` : null;
			case 'message':
				return r.actor_id ? `/messages/${r.actor_id}` : null;
			case 'club_post':
				return item.club_slug ? `/clubs/${item.club_slug}` : null;
			case 'run_completed':
				return r.run_id ? `/share/run/${r.run_id}` : null;
		}
	}

	function verbFor(item: NotificationView): string {
		const name = item.actor?.display_name ?? 'Someone';
		const dist = item.run_distance_m
			? fmtKm(item.run_distance_m)
			: 'your run';
		switch (item.row.kind) {
			case 'kudos':
				return `${name} gave kudos to your ${dist}`;
			case 'comment':
				return `${name} commented on your ${dist}`;
			case 'comment_reply':
				return `${name} replied to your comment`;
			case 'follow':
				return `${name} started following you`;
			case 'event_rsvp':
				return item.event_title
					? `${name} RSVP'd Going to your event "${item.event_title}"`
					: `${name} RSVP'd Going to your event`;
			case 'event_cancel':
				return item.event_title
					? `An occurrence of "${item.event_title}" was cancelled`
					: 'An event occurrence you RSVP\'d to was cancelled';
			case 'plan_update':
				return `${name} updated your training plan`;
			case 'message':
				return `${name} sent you a message`;
			case 'club_post':
				return item.club_name
					? `${name} posted in ${item.club_name}`
					: `${name} posted in a club you're in`;
			case 'run_completed':
				return item.run_distance_m
					? `${name} completed a ${fmtKm(item.run_distance_m)} run`
					: `${name} completed a run`;
		}
	}

	function fmtAbsolute(iso: string): string {
		return new Date(iso).toLocaleString(undefined, {
			weekday: 'short',
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit',
		});
	}

</script>

<div class="wrap">
	<header class="head">
		<div class="filter-tabs">
			<button class="filter" class:active={filter === 'all'} onclick={() => (filter = 'all')}>
				All
			</button>
			<button class="filter" class:active={filter === 'unread'} onclick={() => (filter = 'unread')}>
				Unread
				{#if notificationStore.unreadCount > 0}
					<span class="filter-count">{notificationStore.unreadCount}</span>
				{/if}
			</button>
		</div>
		{#if items.some((x) => x.row.read_at == null)}
			<button class="btn btn-outline btn-sm" type="button" onclick={handleMarkAll}>
				Mark all read
			</button>
		{/if}
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else if visible.length === 0}
		<div class="empty">
			{#if filter === 'unread'}
				<p>You're all caught up.</p>
			{:else}
				<p>No notifications yet — kudos, comments, and new followers show up here.</p>
				<a href="/social?tab=people" class="btn btn-primary">Find people</a>
			{/if}
		</div>
	{:else}
		<ul class="list">
			{#each visible as item (item.row.id)}
				<li class="item-wrap" class:unread={item.row.read_at == null}>
					<button class="item-main" type="button" onclick={() => open(item)}>
						<span class="avatar-md">
							{#if item.actor?.avatar_url}
								<img src={item.actor.avatar_url} alt="" />
							{:else}
								{initial(item.actor?.display_name)}
							{/if}
						</span>
						<span class="body">
							<span class="verb">{verbFor(item)}</span>
							{#if item.comment_excerpt}
								<span class="excerpt">"{item.comment_excerpt}"</span>
							{/if}
							<span class="when">{fmtAbsolute(item.row.created_at)}</span>
						</span>
					</button>
					<button
						type="button"
						class="dismiss"
						aria-label="Dismiss"
						onclick={(e) => remove(item.row.id, e)}
					>
						<span class="material-symbols">close</span>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.wrap {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		max-width: 50rem;
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.filter-tabs {
		display: inline-flex;
		gap: 0.25rem;
	}
	.filter {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: none;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		padding: 0.3rem 0.85rem;
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		font-family: inherit;
	}
	.filter:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.filter.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}
	.filter-count {
		min-width: 1.2rem;
		padding: 0 0.4rem;
		background: rgba(255, 255, 255, 0.25);
		color: inherit;
		border-radius: 9999px;
		font-size: 0.7rem;
		font-weight: 700;
	}

	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.95rem;
		margin: 0;
	}
	.empty {
		text-align: center;
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
	}

	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.item-wrap {
		display: flex;
		align-items: stretch;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		transition: border-color var(--transition-fast);
		overflow: hidden;
	}
	.item-wrap:hover {
		border-color: var(--color-primary);
	}
	.item-wrap.unread {
		background: color-mix(in srgb, var(--color-primary) 7%, var(--color-surface));
	}
	.item-main {
		display: flex;
		align-items: flex-start;
		gap: 0.85rem;
		flex: 1;
		min-width: 0;
		padding: 0.85rem 1rem;
		background: transparent;
		border: none;
		cursor: pointer;
		text-align: left;
		font: inherit;
		color: inherit;
	}
	.avatar-md {
		flex-shrink: 0;
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: grid;
		place-items: center;
		font-size: 0.95rem;
		font-weight: 700;
		overflow: hidden;
	}
	.avatar-md img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
	}
	.verb {
		font-size: 0.95rem;
		color: var(--color-text);
		line-height: 1.4;
	}
	.excerpt {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
		display: -webkit-box;
		-webkit-line-clamp: 3;
		line-clamp: 3;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.when {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.dismiss {
		flex-shrink: 0;
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.5rem 0.75rem;
		align-self: stretch;
		display: inline-flex;
		align-items: center;
	}
	.dismiss:hover {
		color: var(--color-danger, #ef4444);
		background: var(--color-bg-secondary);
	}
	.dismiss .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.05rem;
	}
</style>
