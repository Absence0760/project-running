<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { goto } from '$app/navigation';
	import {
		fetchNotificationsWithError,
		markNotificationRead,
		markAllNotificationsRead,
		deleteNotification,
		type NotificationView,
	} from '$lib/core/data';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { fmtKm } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { notificationLinkFor } from '$lib/social/notification_link';
	import { groupNotifications, type NotificationGroup } from '$lib/social/notification_groups';

	let items = $state<NotificationView[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let filter = $state<'all' | 'unread'>('all');

	async function load() {
		loading = true;
		loadError = null;
		try {
			const res = await fetchNotificationsWithError(100);
			if (res.error) {
				loadError = res.error;
				return;
			}
			items = res.notifications;
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	let visible = $derived(
		filter === 'unread' ? items.filter((x) => x.row.read_at == null) : items,
	);

	let viewById = $derived(new Map(visible.map((v) => [v.row.id, v])));
	let groups = $derived(groupNotifications(visible.map((v) => v.row)));
	let expanded = $state<Set<string>>(new Set());

	function toggleExpanded(key: string) {
		const next = new Set(expanded);
		if (next.has(key)) next.delete(key);
		else next.add(key);
		expanded = next;
	}

	function markReadLocal(ids: string[]) {
		const idSet = new Set(ids);
		let unread = 0;
		items = items.map((x) => {
			if (idSet.has(x.row.id) && x.row.read_at == null) {
				unread += 1;
				return { ...x, row: { ...x.row, read_at: new Date().toISOString() } };
			}
			return x;
		});
		for (let i = 0; i < unread; i++) notificationStore.decrement();
		for (const id of ids) {
			markNotificationRead(id).catch((e) => console.warn('mark read failed', e));
		}
	}

	async function open(item: NotificationView) {
		if (item.row.read_at == null) markReadLocal([item.row.id]);
		const href = notificationLinkFor(item);
		if (href) goto(href);
	}

	function openGroup(group: NotificationGroup) {
		const lead = viewById.get(group.lead.id);
		if (!lead) return;
		const unreadIds = [group.lead, ...group.others]
			.filter((r) => r.read_at == null)
			.map((r) => r.id);
		if (unreadIds.length > 0) markReadLocal(unreadIds);
		const href = notificationLinkFor(lead);
		if (href) goto(href);
	}

	async function removeGroup(group: NotificationGroup, event: Event) {
		event.stopPropagation();
		for (const row of [group.lead, ...group.others]) {
			await remove(row.id, event);
		}
	}

	function nameFor(item: NotificationView): string {
		return item.actor?.display_name ?? m('notificationsList.someone');
	}

	async function handleMarkAll() {
		try {
			await markAllNotificationsRead();
			notificationStore.markAllRead();
			items = items.map((x) => ({
				...x,
				row: { ...x.row, read_at: x.row.read_at ?? new Date().toISOString() },
			}));
		} catch (e) {
			showToast(m('notificationsList.markAllFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
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
			showToast(m('notificationsList.deleteFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
			await load();
		}
	}

	function verbFor(item: NotificationView, nameOverride?: string): string {
		const name = nameOverride ?? nameFor(item);
		const dist = item.run_distance_m
			? fmtKm(item.run_distance_m)
			: m('notificationsList.yourRun');
		switch (item.row.kind) {
			case 'kudos':
				return m('notificationsList.verbKudos', { name, dist });
			case 'comment':
				return m('notificationsList.verbComment', { name, dist });
			case 'comment_reply':
				return m('notificationsList.verbCommentReply', { name });
			case 'follow':
				return m('notificationsList.verbFollow', { name });
			case 'event_rsvp':
				return item.event_title
					? m('notificationsList.verbEventRsvpTitled', { name, title: item.event_title })
					: m('notificationsList.verbEventRsvp', { name });
			case 'event_cancel':
				return item.event_title
					? m('notificationsList.verbEventCancelTitled', { title: item.event_title })
					: m('notificationsList.verbEventCancel');
			case 'event_reminder':
				return item.event_title
					? m('notificationsList.verbEventReminderTitled', { title: item.event_title })
					: m('notificationsList.verbEventReminder');
			case 'plan_update':
				return m('notificationsList.verbPlanUpdate', { name });
			case 'plan_assigned':
				return m('notificationsList.verbPlanAssigned', { name });
			case 'message':
				return m('notificationsList.verbMessage', { name });
			case 'club_post':
				return item.club_name
					? m('notificationsList.verbClubPostNamed', { name, club: item.club_name })
					: m('notificationsList.verbClubPost', { name });
			case 'run_completed':
				return item.run_distance_m
					? m('notificationsList.verbRunCompletedDist', { name, dist: fmtKm(item.run_distance_m) })
					: m('notificationsList.verbRunCompleted', { name });
			case 'achievement':
				return m('notificationsList.verbAchievement');
			case 'challenge_complete':
				return m('notificationsList.verbChallengeComplete');
			case 'content_hidden':
				return m('notificationsList.verbContentHidden');
			default:
				return m('notificationsList.verbGeneric');
		}
	}

	function fmtAbsolute(iso: string): string {
		return new Date(iso).toLocaleString(activeFormatLocale(), {
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
				{m('notificationsList.tabAll')}
			</button>
			<button class="filter" class:active={filter === 'unread'} onclick={() => (filter = 'unread')}>
				{m('notificationsList.tabUnread')}
				{#if notificationStore.unreadCount > 0}
					<span class="filter-count">{notificationStore.unreadCount}</span>
				{/if}
			</button>
		</div>
		{#if items.some((x) => x.row.read_at == null)}
			<button class="btn btn-outline btn-sm" type="button" onclick={handleMarkAll}>
				{m('notificationsList.markAllRead')}
			</button>
		{/if}
	</header>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('profile.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{m('profile.retry')}</button>
		</div>
	{:else if visible.length === 0}
		<div class="empty">
			{#if filter === 'unread'}
				<p>{m('notificationsList.allCaughtUp')}</p>
			{:else}
				<p>{m('notificationsList.emptyAll')}</p>
				<a href="/social?tab=people" class="btn btn-primary">{m('notificationsList.findPeople')}</a>
			{/if}
		</div>
	{:else}
		<ul class="list">
			{#each groups as group (group.key + group.lead.id)}
				{@const lead = viewById.get(group.lead.id)}
				{#if lead}
					<li class="item-wrap" class:unread={group.unreadCount > 0}>
						<button class="item-main" type="button" onclick={() => openGroup(group)}>
							<Avatar
								url={lead.actor?.avatar_url}
								name={lead.actor?.display_name}
								size="2.5rem"
								font="0.95rem"
							/>
							<span class="body">
								<span class="verb">
									{verbFor(
										lead,
										group.otherCount > 0
											? m('notificationsList.nameAndOthers', {
													name: nameFor(lead),
													count: group.otherCount,
												})
											: undefined,
									)}
								</span>
								{#if lead.comment_excerpt}
									<span class="excerpt">"{lead.comment_excerpt}"</span>
								{/if}
								<span class="when">{fmtAbsolute(group.lead.created_at)}</span>
							</span>
							{#if group.unreadCount > 0}
								<span class="group-unread" aria-hidden="true">{group.unreadCount}</span>
							{/if}
						</button>
						{#if group.otherCount > 0}
							<button
								type="button"
								class="expander"
								aria-expanded={expanded.has(group.key)}
								aria-label={expanded.has(group.key)
									? m('notificationsList.showLess')
									: m('notificationsList.andOthers', { count: group.otherCount })}
								onclick={() => toggleExpanded(group.key)}
							>
								<span class="material-symbols">
									{expanded.has(group.key) ? 'expand_less' : 'expand_more'}
								</span>
							</button>
						{/if}
						<button
							type="button"
							class="dismiss"
							aria-label={m('notificationsList.dismiss')}
							onclick={(e) => removeGroup(group, e)}
						>
							<span class="material-symbols">close</span>
						</button>
					</li>
					{#if group.otherCount > 0 && expanded.has(group.key)}
						{#each group.others as other (other.id)}
							{@const otherView = viewById.get(other.id)}
							{#if otherView}
								<li class="item-wrap sub" class:unread={other.read_at == null}>
									<button class="item-main" type="button" onclick={() => open(otherView)}>
										<Avatar
											url={otherView.actor?.avatar_url}
											name={otherView.actor?.display_name}
											size="2rem"
											font="0.8rem"
										/>
										<span class="body">
											<span class="verb">{verbFor(otherView)}</span>
											{#if otherView.comment_excerpt}
												<span class="excerpt">"{otherView.comment_excerpt}"</span>
											{/if}
											<span class="when">{fmtAbsolute(other.created_at)}</span>
										</span>
									</button>
									<button
										type="button"
										class="dismiss"
										aria-label={m('notificationsList.dismiss')}
										onclick={(e) => remove(other.id, e)}
									>
										<span class="material-symbols">close</span>
									</button>
								</li>
							{/if}
						{/each}
					{/if}
				{/if}
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
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
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
		text-align: start;
		font: inherit;
		color: inherit;
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
	.item-wrap.sub {
		margin-left: 1.75rem;
		background: var(--color-bg-secondary, var(--color-surface));
	}
	.group-unread {
		flex-shrink: 0;
		align-self: center;
		min-width: 1.3rem;
		padding: 0 0.4rem;
		background: var(--color-primary);
		color: white;
		border-radius: 9999px;
		font-size: 0.72rem;
		font-weight: 700;
		text-align: center;
	}
	.expander {
		flex-shrink: 0;
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.5rem 0.5rem;
		align-self: stretch;
		display: inline-flex;
		align-items: center;
	}
	.expander:hover {
		color: var(--color-primary);
		background: var(--color-bg-secondary);
	}
	.expander .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.2rem;
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
