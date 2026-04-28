<script lang="ts">
	import { goto } from '$app/navigation';
	import {
		fetchNotifications,
		markNotificationRead,
		markAllNotificationsRead,
		type NotificationView,
	} from '$lib/data';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	interface Props {
		collapsed?: boolean;
	}
	let { collapsed = false }: Props = $props();

	let open = $state(false);
	let loading = $state(false);
	let items = $state<NotificationView[]>([]);

	async function togglePanel() {
		open = !open;
		if (open) await refreshList();
	}

	async function refreshList() {
		loading = true;
		try {
			items = await fetchNotifications(15);
		} finally {
			loading = false;
		}
	}

	async function handleClick(item: NotificationView) {
		// Optimistic mark-as-read so the bell badge updates without
		// waiting for the round trip. The actual write is best-effort —
		// failures are logged but don't block navigation.
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
		open = false;
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

	function linkFor(item: NotificationView): string | null {
		const r = item.row;
		switch (r.kind) {
			case 'kudos':
			case 'comment':
			case 'comment_reply':
				return r.run_id ? `/runs/${r.run_id}` : null;
			case 'follow':
				return r.actor_id ? `/u/${r.actor_id}` : null;
		}
	}

	function verbFor(item: NotificationView): string {
		const name = item.actor?.display_name ?? 'Someone';
		const dist = item.run_distance_m
			? `${(item.run_distance_m / 1000).toFixed(1)} km`
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
		}
	}

	function fmtRelative(iso: string): string {
		const ms = Date.now() - new Date(iso).getTime();
		const mins = Math.floor(ms / 60_000);
		if (mins < 1) return 'just now';
		if (mins < 60) return `${mins}m ago`;
		const hrs = Math.floor(mins / 60);
		if (hrs < 24) return `${hrs}h ago`;
		const days = Math.floor(hrs / 24);
		if (days < 30) return `${days}d ago`;
		return new Date(iso).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
		});
	}

	function initial(name: string | null | undefined): string {
		return (name?.[0] ?? '?').toUpperCase();
	}

	function handleEsc(e: KeyboardEvent) {
		if (e.key === 'Escape' && open) {
			open = false;
		}
	}
</script>

<svelte:window onkeydown={handleEsc} />

<div class="bell-wrap">
	<button
		class="bell-btn"
		class:has-unread={notificationStore.unreadCount > 0}
		type="button"
		aria-label={notificationStore.unreadCount > 0
			? `Notifications, ${notificationStore.unreadCount} unread`
			: 'Notifications'}
		aria-expanded={open}
		onclick={togglePanel}
		title={collapsed ? 'Notifications' : undefined}
	>
		<span class="material-symbols">{notificationStore.unreadCount > 0 ? 'notifications' : 'notifications_none'}</span>
		<span class="bell-label">Notifications</span>
		{#if notificationStore.unreadCount > 0}
			<span class="badge">
				{notificationStore.unreadCount > 99 ? '99+' : notificationStore.unreadCount}
			</span>
		{/if}
	</button>

	{#if open}
		<button
			class="popover-backdrop"
			type="button"
			aria-label="Close"
			onclick={() => (open = false)}
		></button>
		<div class="popover" role="dialog" aria-label="Notifications">
			<header class="popover-head">
				<h3>Notifications</h3>
				{#if notificationStore.unreadCount > 0}
					<button class="link-btn" type="button" onclick={handleMarkAll}>
						Mark all read
					</button>
				{/if}
			</header>

			{#if loading}
				<p class="muted">Loading…</p>
			{:else if items.length === 0}
				<p class="muted">Nothing yet — kudos, comments, and new followers show up here.</p>
			{:else}
				<ul class="list">
					{#each items as item (item.row.id)}
						<li>
							<button
								class="item"
								type="button"
								class:unread={item.row.read_at == null}
								onclick={() => handleClick(item)}
							>
								<span class="avatar-sm">
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
									<span class="when">{fmtRelative(item.row.created_at)}</span>
								</span>
								{#if item.row.read_at == null}
									<span class="unread-dot" aria-hidden="true"></span>
								{/if}
							</button>
						</li>
					{/each}
				</ul>
				<a class="see-all" href="/notifications" onclick={() => (open = false)}>
					See all
					<span class="material-symbols">chevron_right</span>
				</a>
			{/if}
		</div>
	{/if}
</div>

<style>
	.bell-wrap {
		position: relative;
	}
	.bell-btn {
		display: flex;
		align-items: center;
		gap: 0.85rem;
		width: 100%;
		padding: 0.55rem 0.85rem;
		background: transparent;
		border: none;
		border-radius: var(--radius-md);
		color: rgba(255, 255, 255, 0.85);
		cursor: pointer;
		font: inherit;
		text-align: left;
		position: relative;
		transition: background var(--transition-fast);
	}
	.bell-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: white;
	}
	.bell-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.35rem;
		flex-shrink: 0;
	}
	.bell-label {
		flex: 1;
		min-width: 0;
		font-size: 0.95rem;
	}
	:global(.sidebar.collapsed) .bell-btn .bell-label {
		display: none;
	}
	.badge {
		min-width: 1.25rem;
		height: 1.25rem;
		padding: 0 0.35rem;
		display: inline-grid;
		place-items: center;
		background: #ef4444;
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
	}
	:global(.sidebar.collapsed) .bell-btn .badge {
		position: absolute;
		top: 0.25rem;
		right: 0.25rem;
	}

	.popover-backdrop {
		position: fixed;
		inset: 0;
		background: transparent;
		border: none;
		cursor: default;
		z-index: 100;
	}
	.popover {
		position: absolute;
		left: calc(100% + 0.5rem);
		bottom: 0;
		width: 22rem;
		max-height: 80vh;
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-lg, 0 10px 35px rgba(0, 0, 0, 0.25));
		z-index: 101;
		overflow: hidden;
	}
	@media (max-width: 50rem) {
		.popover {
			left: 0;
			right: 0;
			bottom: calc(100% + 0.5rem);
			width: auto;
			margin: 0 0.5rem;
		}
	}
	.popover-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.65rem 0.85rem;
		border-bottom: 1px solid var(--color-border);
	}
	.popover-head h3 {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 700;
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.82rem;
		font-weight: 600;
		cursor: pointer;
		padding: 0.2rem 0.4rem;
	}

	.list {
		list-style: none;
		margin: 0;
		padding: 0.25rem 0;
		overflow-y: auto;
	}
	.item {
		display: flex;
		align-items: flex-start;
		gap: 0.65rem;
		width: 100%;
		padding: 0.55rem 0.85rem;
		background: transparent;
		border: none;
		cursor: pointer;
		text-align: left;
		font: inherit;
		color: inherit;
		position: relative;
	}
	.item:hover {
		background: var(--color-bg-secondary);
	}
	.item.unread {
		background: color-mix(in srgb, var(--color-primary) 6%, transparent);
	}
	.avatar-sm {
		flex-shrink: 0;
		width: 2.1rem;
		height: 2.1rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: grid;
		place-items: center;
		font-size: 0.85rem;
		font-weight: 700;
		overflow: hidden;
	}
	.avatar-sm img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.verb {
		font-size: 0.88rem;
		color: var(--color-text);
		line-height: 1.3;
	}
	.excerpt {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		line-height: 1.3;
		overflow: hidden;
		text-overflow: ellipsis;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
	}
	.when {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		margin-top: 0.05rem;
	}
	.unread-dot {
		position: absolute;
		top: 0.85rem;
		right: 0.7rem;
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: var(--color-primary);
	}

	.see-all {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 0.2rem;
		padding: 0.55rem 0.85rem;
		border-top: 1px solid var(--color-border);
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		text-decoration: none;
	}
	.see-all:hover {
		background: var(--color-bg-secondary);
	}
	.see-all .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}

	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		padding: 1rem;
		margin: 0;
		text-align: center;
	}
</style>
