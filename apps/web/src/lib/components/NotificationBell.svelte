<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { goto } from '$app/navigation';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		fetchNotifications,
		markNotificationRead,
		markAllNotificationsRead,
		type NotificationView,
	} from '$lib/core/data';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { fmtKm } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { notificationLinkFor } from '$lib/social/notification_link';

	let open = $state(false);
	let loading = $state(false);
	let items = $state<NotificationView[]>([]);

	// Focus-trap state mirrors the account popover in +layout.svelte —
	// audit/accessibility (2026-05-25) High: pre-fix, Tab escaped the
	// dialog into the page behind it and the user had no keyboard
	// path through the notifications list (WCAG 2.1.2 + 2.4.3).
	let popoverEl = $state<HTMLDivElement | null>(null);
	let bellBtnEl = $state<HTMLButtonElement | null>(null);

	$effect(() => {
		if (!open) return;
		const trigger = bellBtnEl;
		queueMicrotask(() => {
			const first = popoverEl?.querySelector<HTMLElement>(
				'a, button, [tabindex]:not([tabindex="-1"])',
			);
			first?.focus();
		});

		const onKey = (e: KeyboardEvent) => {
			if (e.key === 'Escape') {
				e.stopPropagation();
				open = false;
				return;
			}
			if (e.key !== 'Tab' || !popoverEl) return;
			const focusables = Array.from(
				popoverEl.querySelectorAll<HTMLElement>(
					'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])',
				),
			);
			if (focusables.length === 0) return;
			const first = focusables[0];
			const last = focusables[focusables.length - 1];
			const active = document.activeElement as HTMLElement | null;
			if (e.shiftKey && active === first) {
				e.preventDefault();
				last.focus();
			} else if (!e.shiftKey && active === last) {
				e.preventDefault();
				first.focus();
			}
		};
		window.addEventListener('keydown', onKey);
		return () => {
			window.removeEventListener('keydown', onKey);
			if (trigger && document.body.contains(trigger)) trigger.focus();
		};
	});

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
		const href = notificationLinkFor(item);
		if (href) goto(href);
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
			showToast(m('notificationBell.markAllFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	function verbFor(item: NotificationView): string {
		const name = item.actor?.display_name ?? m('notificationBell.someone');
		const dist = item.run_distance_m
			? fmtKm(item.run_distance_m)
			: m('notificationBell.yourRun');
		switch (item.row.kind) {
			case 'kudos':
				return m('notificationBell.kudos', { name, dist });
			case 'comment':
				return m('notificationBell.comment', { name, dist });
			case 'comment_reply':
				return m('notificationBell.commentReply', { name });
			case 'follow':
				return m('notificationBell.follow', { name });
			case 'event_rsvp':
				return item.event_title
					? m('notificationBell.eventRsvpTitled', { name, title: item.event_title })
					: m('notificationBell.eventRsvp', { name });
			case 'event_cancel':
				return item.event_title
					? m('notificationBell.eventCancelTitled', { title: item.event_title })
					: m('notificationBell.eventCancel');
			case 'event_reminder':
				return item.event_title
					? m('notificationBell.eventReminderTitled', { title: item.event_title })
					: m('notificationBell.eventReminder');
			case 'plan_update':
				return m('notificationBell.planUpdate', { name });
			case 'plan_assigned':
				return m('notificationBell.planAssigned', { name });
			case 'message':
				return m('notificationBell.message', { name });
			case 'club_post':
				return item.club_name
					? m('notificationBell.clubPostNamed', { name, club: item.club_name })
					: m('notificationBell.clubPost', { name });
			case 'run_completed':
				return item.run_distance_m
					? m('notificationBell.runCompletedDist', { name, dist: fmtKm(item.run_distance_m) })
					: m('notificationBell.runCompleted', { name });
			case 'achievement':
				return m('notificationBell.achievement');
			case 'challenge_complete':
				return m('notificationBell.challengeComplete');
			case 'content_hidden':
				return m('notificationBell.contentHidden');
			default:
				return m('notificationBell.generic');
		}
	}

	function fmtRelative(iso: string): string {
		const ms = Date.now() - new Date(iso).getTime();
		const mins = Math.floor(ms / 60_000);
		if (mins < 1) return m('notificationBell.justNow');
		if (mins < 60) return m('notificationBell.minutesAgo', { n: mins });
		const hrs = Math.floor(mins / 60);
		if (hrs < 24) return m('notificationBell.hoursAgo', { n: hrs });
		const days = Math.floor(hrs / 24);
		if (days < 30) return m('notificationBell.daysAgo', { n: days });
		return new Date(iso).toLocaleDateString(activeFormatLocale(), {
			month: 'short',
			day: 'numeric',
		});
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
		bind:this={bellBtnEl}
		class="bell-btn"
		class:active={open}
		type="button"
		aria-label={notificationStore.unreadCount > 0
			? m('notificationBell.bellUnread', { n: notificationStore.unreadCount })
			: m('notificationBell.title')}
		aria-expanded={open}
		onclick={togglePanel}
		title={m('notificationBell.title')}
	>
		<span class="bell-icon material-symbols">
			{notificationStore.unreadCount > 0 ? 'notifications_active' : 'notifications'}
		</span>
		{#if notificationStore.unreadCount > 0}
			<span class="badge">
				{notificationStore.unreadCount > 9 ? '9+' : notificationStore.unreadCount}
			</span>
		{/if}
	</button>

	{#if open}
		<button
			class="popover-backdrop"
			type="button"
			aria-label={m('notificationBell.close')}
			onclick={() => (open = false)}
		></button>
		<div
			bind:this={popoverEl}
			class="popover"
			role="dialog"
			tabindex="-1"
			aria-labelledby="notif-popover-heading"
		>
			<header class="popover-head">
				<h3 id="notif-popover-heading">{m('notificationBell.title')}</h3>
				{#if notificationStore.unreadCount > 0}
					<button class="link-btn" type="button" onclick={handleMarkAll}>
						{m('notificationBell.markAllRead')}
					</button>
				{/if}
			</header>

			{#if loading}
				<p class="muted">{m('shell.loading')}</p>
			{:else if items.length === 0}
				<p class="muted">{m('notificationBell.empty')}</p>
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
								<Avatar
									url={item.actor?.avatar_url}
									name={item.actor?.display_name}
									size="2.1rem"
									font="0.85rem"
								/>
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
				{#if auth.user}
					<a
						class="see-all"
						href="/u/{auth.user.id}?tab=notifications"
						onclick={() => (open = false)}
					>
						{m('notificationBell.seeAll')}
						<span class="material-symbols">chevron_right</span>
					</a>
				{/if}
			{/if}
		</div>
	{/if}
</div>

<style>
	.bell-wrap {
		position: relative;
		flex-shrink: 0;
	}
	/* Compact icon-button that visually pairs with the profile button
	   in the sidebar footer. Same height as the collapse-toggle so the
	   row reads as one unit. */
	.bell-btn {
		display: grid;
		place-items: center;
		width: 2rem;
		height: 2rem;
		border: none;
		border-radius: var(--radius-md);
		background: transparent;
		color: var(--sidebar-text-muted);
		cursor: pointer;
		flex-shrink: 0;
		position: relative;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}
	.bell-btn:focus { outline: none; }
	.bell-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.bell-btn:hover {
		background: var(--sidebar-hover-bg);
		color: var(--sidebar-text);
	}
	.bell-btn.active {
		background: var(--sidebar-hover-bg);
		color: var(--sidebar-text);
	}
	.bell-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 1.25rem;
		line-height: 1;
	}
	.badge {
		position: absolute;
		top: -2px;
		inset-inline-end: -2px;
		min-width: 1rem;
		height: 1rem;
		padding: 0 var(--space-xs);
		display: inline-grid;
		place-items: center;
		/* WCAG AA: 0.62rem bold white on --color-danger was 3.06:1 in dark
		   (normal-text threshold applies at this size); -strong is 6.06:1. */
		background: var(--color-danger-strong);
		color: white;
		font-size: 0.62rem;
		font-weight: 700;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
		box-shadow: 0 0 0 2px var(--color-bg-secondary);
		line-height: 1;
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
		inset-inline-start: calc(100% + 0.5rem);
		/* Anchor the popover's TOP edge to the bell so it hangs downward.
		   Earlier the bell lived in the sidebar footer and the popover
		   anchored bottom: 0 — fine when the bell sat near the bottom of
		   the viewport, but it clipped off the top of the screen when
		   the bell moved into the sidebar head. */
		top: 0;
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
			inset-inline-start: 0;
			inset-inline-end: 0;
			/* Mobile: bell still at the top of the sidebar / rail; drop
			   the popover below it so the body content stays visible. */
			top: calc(100% + 0.5rem);
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
		text-align: start;
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
		inset-inline-end: 0.7rem;
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
