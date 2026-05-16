<script lang="ts">
	import { page } from '$app/stores';
	import {
		fetchPublicProfile,
		fetchPublicRunsByUser,
		fetchFollowers,
		fetchFollowing,
		fetchFollowingFeed,
		fetchEngagementSummaries,
		followUser,
		unfollowUser,
		giveKudos,
		rescindKudos,
		FEED_WINDOW_DAYS,
		type FeedEntry,
		type ProfileSummary,
		type PublicProfile,
	} from '$lib/data';
	import { formatDuration } from '$lib/mock-data';
	import { formatDistance, formatPace } from '$lib/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import RunShareView from '$lib/components/RunShareView.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';
	import NotificationsList from '$lib/components/NotificationsList.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import type { Run } from '$lib/types';

	let userId = $derived($page.params.id as string);
	let profile = $state<ProfileSummary | null>(null);
	let runs = $state<Run[]>([]);
	let followers = $state<PublicProfile[]>([]);
	let following = $state<PublicProfile[]>([]);
	let loading = $state(true);
	let busy = $state(false);
	let tab = $state<'runs' | 'followers' | 'following' | 'notifications' | 'feed'>('runs');

	let isSelf = $derived(auth.user?.id === userId);
	let openRunId = $state<string | null>(null);

	// ── Feed state (self-only tab) ─────────────────────────────────
	// Mirrors the shape /feed used to render: 14-day window over runs
	// from people you follow, cursor-paginated on (started_at, id), with
	// kudos + comment counts surfaced as pills under each card. State
	// hydrates lazily when the user first lands on the Feed tab so non-
	// owners never pay for the feed query.
	let feedEntries = $state<FeedEntry[]>([]);
	let feedEngagement = $state<
		Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>
	>(new Map());
	let feedLoading = $state(false);
	let feedLoaded = $state(false);
	let feedExhausted = $state(false);
	let feedLoadingMore = $state(false);
	let kudosBusy = $state<Set<string>>(new Set());
	let activityFilter = $state<string>('all');
	const FEED_ACTIVITIES: { value: string; label: string; icon: string }[] = [
		{ value: 'all', label: 'All', icon: 'apps' },
		{ value: 'run', label: 'Run', icon: 'directions_run' },
		{ value: 'walk', label: 'Walk', icon: 'directions_walk' },
		{ value: 'cycle', label: 'Cycle', icon: 'directions_bike' },
		{ value: 'hike', label: 'Hike', icon: 'terrain' },
	];
	let followsAnyone = $derived(following.length > 0);

	async function load() {
		loading = true;
		const [p, r, fr, fg] = await Promise.all([
			fetchPublicProfile(userId),
			fetchPublicRunsByUser(userId, 20),
			fetchFollowers(userId, 50),
			fetchFollowing(userId, 50),
		]);
		profile = p;
		runs = r;
		followers = fr;
		following = fg;
		loading = false;
	}

	$effect(() => {
		if (userId) load();
	});

	// Deep-link the followers / following / notifications / feed tab
	// via `?tab=…` so the feed-header chips, the bell popover, and the
	// /feed redirect can link straight into the right panel. The
	// notifications + feed tabs are self-only — even if a deep link asks
	// for them on someone else's profile, RLS hides the rows anyway, so
	// collapse the invalid case to the runs tab.
	$effect(() => {
		const t = $page.url.searchParams.get('tab');
		if (t === 'followers' || t === 'following' || t === 'runs') tab = t;
		else if (t === 'notifications' && isSelf) tab = 'notifications';
		else if (t === 'feed' && isSelf) tab = 'feed';
	});

	// Lazy-load the feed when the self-viewer first switches to the tab.
	// Re-fetches when the activity filter changes (drops back to page 1).
	$effect(() => {
		if (tab !== 'feed' || !isSelf) return;
		const _ = activityFilter;
		loadFeed();
	});

	async function loadFeed() {
		feedLoading = true;
		try {
			feedEntries = await fetchFollowingFeed({
				limit: 20,
				activityType: activityFilter,
			});
			feedExhausted = feedEntries.length < 20;
			feedEngagement = await fetchEngagementSummaries(feedEntries.map((e) => e.id));
		} catch (e) {
			showToast(`Could not load feed: ${e}`, 'error');
		} finally {
			feedLoading = false;
			feedLoaded = true;
		}
	}

	async function loadMoreFeed() {
		if (feedLoadingMore || feedExhausted || feedEntries.length === 0) return;
		feedLoadingMore = true;
		try {
			const last = feedEntries[feedEntries.length - 1];
			const more = await fetchFollowingFeed({
				limit: 20,
				cursor: { started_at: last.started_at, id: last.id },
				activityType: activityFilter,
			});
			feedEntries = [...feedEntries, ...more];
			feedExhausted = more.length < 20;
			const moreEng = await fetchEngagementSummaries(more.map((e) => e.id));
			const merged = new Map(feedEngagement);
			for (const [k, v] of moreEng) merged.set(k, v);
			feedEngagement = merged;
		} finally {
			feedLoadingMore = false;
		}
	}

	async function toggleKudos(runId: string) {
		if (kudosBusy.has(runId)) return;
		const current = feedEngagement.get(runId) ?? {
			kudos_count: 0,
			viewer_has_kudos: false,
			comment_count: 0,
		};
		kudosBusy = new Set([...kudosBusy, runId]);
		try {
			if (current.viewer_has_kudos) {
				await rescindKudos(runId);
				feedEngagement = new Map(feedEngagement).set(runId, {
					...current,
					kudos_count: Math.max(current.kudos_count - 1, 0),
					viewer_has_kudos: false,
				});
			} else {
				await giveKudos(runId);
				feedEngagement = new Map(feedEngagement).set(runId, {
					...current,
					kudos_count: current.kudos_count + 1,
					viewer_has_kudos: true,
				});
			}
		} catch (e) {
			showToast(`Could not update kudos: ${e}`, 'error');
		} finally {
			const next = new Set(kudosBusy);
			next.delete(runId);
			kudosBusy = next;
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
			year: 'numeric',
		});
	}

	async function toggleFollow() {
		if (!profile || !auth.loggedIn || isSelf) return;
		busy = true;
		try {
			if (profile.viewer_follows) {
				await unfollowUser(profile.id);
				profile = {
					...profile,
					viewer_follows: false,
					follower_count: Math.max(profile.follower_count - 1, 0),
				};
			} else {
				await followUser(profile.id);
				profile = {
					...profile,
					viewer_follows: true,
					follower_count: profile.follower_count + 1,
				};
			}
		} catch (e) {
			showToast(`Could not update follow: ${e}`, 'error');
		} finally {
			busy = false;
		}
	}

	function fmtDate(iso: string): string {
		return new Date(iso).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric',
		});
	}

	function pace(distance_m: number, duration_s: number): string {
		if (distance_m <= 0 || duration_s <= 0) return '—';
		return formatPace(duration_s, distance_m);
	}

	function goBack() {
		// Profile pages can be reached from many entry points (feed,
		// kudos givers, club members, follower lists). history.back()
		// preserves the user's mental flow; the /dashboard fallback
		// covers direct navigation / fresh tabs where there's nothing
		// to go back to. (The previous /feed fallback now redirects
		// back to this profile, so use /dashboard instead.)
		if (typeof history !== 'undefined' && history.length > 1) {
			history.back();
		} else {
			location.href = '/dashboard';
		}
	}
</script>

<svelte:head>
	<title>{profile?.display_name ?? 'Runner'} — Run Onward</title>
</svelte:head>

<div class="page">
	<button type="button" class="back-link" onclick={goBack}>
		<span class="material-symbols">arrow_back</span>
		Back
	</button>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else if !profile}
		<div class="empty">
			<p>This runner doesn't exist or their profile isn't visible.</p>
		</div>
	{:else}
		<header class="profile-head">
			<div class="avatar-xl">
				{#if profile.avatar_url}
					<img src={profile.avatar_url} alt="" />
				{:else}
					{(profile.display_name?.[0] ?? '?').toUpperCase()}
				{/if}
			</div>
			<div class="profile-info">
				<h1>{profile.display_name ?? 'Runner'}</h1>
				<div class="counts">
					<button class="count" type="button" onclick={() => (tab = 'runs')}>
						<span class="count-num">{runs.length}</span>
						<span class="count-label">Runs</span>
					</button>
					<button class="count" type="button" onclick={() => (tab = 'followers')}>
						<span class="count-num">{profile.follower_count}</span>
						<span class="count-label">Followers</span>
					</button>
					<button class="count" type="button" onclick={() => (tab = 'following')}>
						<span class="count-num">{profile.following_count}</span>
						<span class="count-label">Following</span>
					</button>
				</div>
			</div>
			{#if !isSelf && auth.loggedIn}
				<button
					class="btn {profile.viewer_follows ? 'btn-outline' : 'btn-primary'} btn-follow"
					type="button"
					disabled={busy}
					onclick={toggleFollow}
				>
					<span class="material-symbols">
						{profile.viewer_follows ? 'check' : 'person_add'}
					</span>
					{profile.viewer_follows ? 'Following' : 'Follow'}
				</button>
			{/if}
		</header>

		<div class="tabs">
			<button class="tab" class:active={tab === 'runs'} onclick={() => (tab = 'runs')}>
				Runs
			</button>
			{#if isSelf}
				<button class="tab" class:active={tab === 'feed'} onclick={() => (tab = 'feed')}>
					Feed
				</button>
			{/if}
			<button class="tab" class:active={tab === 'followers'} onclick={() => (tab = 'followers')}>
				Followers
			</button>
			<button class="tab" class:active={tab === 'following'} onclick={() => (tab = 'following')}>
				Following
			</button>
			{#if isSelf}
				<button
					class="tab"
					class:active={tab === 'notifications'}
					onclick={() => (tab = 'notifications')}
				>
					Notifications
					{#if notificationStore.unreadCount > 0}
						<span class="tab-badge">{notificationStore.unreadCount}</span>
					{/if}
				</button>
			{/if}
		</div>

		{#if tab === 'runs'}
			{#if runs.length === 0}
				<div class="empty">
					<p>{isSelf ? "You haven't shared any runs yet." : 'No public runs yet.'}</p>
				</div>
			{:else}
				<div class="run-list">
					{#each runs as r (r.id)}
						<button type="button" class="run-row" onclick={() => (openRunId = r.id)}>
							<div class="run-date">{fmtDate(r.started_at)}</div>
							<div class="run-main">
								<h3>Run</h3>
								<div class="run-meta">
									<span>
										<span class="material-symbols">straighten</span>
										{formatDistance(r.distance_m)}
									</span>
									<span>
										<span class="material-symbols">timer</span>
										{formatDuration(r.duration_s)}
									</span>
									<span>
										<span class="material-symbols">speed</span>
										{pace(r.distance_m, r.duration_s)}
									</span>
								</div>
							</div>
						</button>
					{/each}
				</div>
			{/if}
		{:else if tab === 'followers'}
			{#if followers.length === 0}
				<div class="empty"><p>No followers yet.</p></div>
			{:else}
				<div class="people-list">
					{#each followers as p (p.id)}
						<a href="/u/{p.id}" class="person-row">
							<div class="avatar-sm">
								{#if p.avatar_url}
									<img src={p.avatar_url} alt="" />
								{:else}
									{(p.display_name?.[0] ?? '?').toUpperCase()}
								{/if}
							</div>
							<span>{p.display_name ?? 'Runner'}</span>
						</a>
					{/each}
				</div>
			{/if}
		{:else if tab === 'following'}
			{#if following.length === 0}
				<div class="empty"><p>Not following anyone yet.</p></div>
			{:else}
				<div class="people-list">
					{#each following as p (p.id)}
						<a href="/u/{p.id}" class="person-row">
							<div class="avatar-sm">
								{#if p.avatar_url}
									<img src={p.avatar_url} alt="" />
								{:else}
									{(p.display_name?.[0] ?? '?').toUpperCase()}
								{/if}
							</div>
							<span>{p.display_name ?? 'Runner'}</span>
						</a>
					{/each}
				</div>
			{/if}
		{:else if tab === 'feed' && isSelf}
			<div class="feed-toolbar">
				<div class="activity-group" role="group" aria-label="Activity type">
					{#each FEED_ACTIVITIES as act}
						<button
							class="activity-btn"
							class:active={activityFilter === act.value}
							onclick={() => (activityFilter = act.value)}
							title={act.label}
							aria-label={act.label}
							aria-pressed={activityFilter === act.value}
							type="button"
						>
							<span class="material-symbols">{act.icon}</span>
							<span class="activity-label">{act.label}</span>
						</button>
					{/each}
				</div>
				<span class="window-hint">Last {FEED_WINDOW_DAYS} days</span>
			</div>

			{#if feedLoading && !feedLoaded}
				<p class="muted">Loading…</p>
			{:else if feedEntries.length === 0}
				<div class="empty feed-empty">
					<span class="material-symbols empty-icon">groups</span>
					{#if !followsAnyone}
						<h2>Your feed is empty</h2>
						<p>
							Follow other runners to see their public runs here. Visit a club's Members tab or
							open a public run to find a profile to follow.
						</p>
						<a href="/clubs" class="btn btn-primary">Browse clubs</a>
					{:else if activityFilter !== 'all'}
						<h2>No matches</h2>
						<p>Nothing matches the current filter in the last {FEED_WINDOW_DAYS} days.</p>
						<button
							class="btn btn-outline"
							type="button"
							onclick={() => (activityFilter = 'all')}
						>
							Clear filters
						</button>
					{:else}
						<h2>No recent activity</h2>
						<p>
							Nobody you follow has logged a public run in the last {FEED_WINDOW_DAYS} days. Older
							runs are still on each runner's profile.
						</p>
					{/if}
				</div>
			{:else}
				<div class="feed">
					{#each feedEntries as entry (entry.id)}
						{@const eng = feedEngagement.get(entry.id) ?? { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 }}
						<article class="entry">
							<header class="entry-head">
								<a href="/u/{entry.author.id}" class="author">
									<div class="avatar-sm">
										{#if entry.author.avatar_url}
											<img src={entry.author.avatar_url} alt="" />
										{:else}
											{(entry.author.display_name?.[0] ?? '?').toUpperCase()}
										{/if}
									</div>
									<span class="author-name">{entry.author.display_name ?? 'Runner'}</span>
								</a>
								<span class="when">{fmtRelative(entry.started_at)}</span>
							</header>
							<button type="button" class="entry-body" onclick={() => (openRunId = entry.id)}>
								{#if entry.track_url}
									<div class="entry-map">
										<RunTrackPreview
											runId={entry.id}
											trackUrl={entry.track_url}
											ownerUserId={entry.author.id}
										/>
									</div>
								{/if}
								<div class="entry-stats-wrap">
									<div class="stats">
										<div class="stat">
											<span class="stat-num">{formatDistance(entry.distance_m)}</span>
											<span class="stat-label">Distance</span>
										</div>
										<div class="stat">
											<span class="stat-num">{formatDuration(entry.duration_s)}</span>
											<span class="stat-label">Time</span>
										</div>
										<div class="stat">
											<span class="stat-num">{pace(entry.distance_m, entry.duration_s)}</span>
											<span class="stat-label">Pace</span>
										</div>
									</div>
								</div>
							</button>
							<footer class="entry-foot">
								<button
									class="kudos-pill"
									class:given={eng.viewer_has_kudos}
									type="button"
									disabled={kudosBusy.has(entry.id)}
									onclick={() => toggleKudos(entry.id)}
								>
									<span class="material-symbols">
										{eng.viewer_has_kudos ? 'favorite' : 'favorite_border'}
									</span>
									<span>{eng.kudos_count}</span>
								</button>
								<button
									class="comment-pill"
									type="button"
									onclick={() => (openRunId = entry.id)}
								>
									<span class="material-symbols">chat_bubble_outline</span>
									<span>{eng.comment_count}</span>
								</button>
							</footer>
						</article>
					{/each}
				</div>

				{#if !feedExhausted}
					<div class="load-more">
						<button class="btn btn-outline" onclick={loadMoreFeed} disabled={feedLoadingMore}>
							{feedLoadingMore ? 'Loading…' : 'Load more'}
						</button>
					</div>
				{/if}
			{/if}
		{:else if tab === 'notifications' && isSelf}
			<NotificationsList />
		{/if}
	{/if}
</div>

<Modal open={openRunId !== null} onclose={() => (openRunId = null)} title="Run" wide>
	{#if openRunId}
		{#key openRunId}
			<RunShareView runId={openRunId} compact />
		{/key}
	{/if}
</Modal>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		margin-bottom: var(--space-md);
		padding: 0.4rem 0.55rem 0.4rem 0.35rem;
		background: none;
		border: none;
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		border-radius: var(--radius-md);
		transition: color var(--transition-fast), background var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
	}

	.back-link .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	.profile-head {
		display: flex;
		align-items: center;
		gap: var(--space-xl);
		margin-bottom: var(--space-xl);
		flex-wrap: wrap;
	}

	.avatar-xl {
		width: 6rem;
		height: 6rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: grid;
		place-items: center;
		font-size: 2rem;
		font-weight: 700;
		overflow: hidden;
		flex-shrink: 0;
	}

	.avatar-xl img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.profile-info {
		flex: 1;
		min-width: 0;
	}

	h1 {
		font-size: 1.75rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm) 0;
	}

	.counts {
		display: flex;
		gap: var(--space-lg);
	}

	.count {
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
	}

	.count-num {
		font-size: 1.25rem;
		font-weight: 700;
		color: var(--color-text);
	}

	.count-label {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.btn-follow {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		margin-bottom: var(--space-md);
		border-bottom: 1px solid var(--color-border);
	}

	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		margin-right: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	.tab-badge {
		display: inline-grid;
		place-items: center;
		min-width: 1.2rem;
		height: 1.2rem;
		margin-left: 0.4rem;
		padding: 0 0.4rem;
		background: var(--color-primary);
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
	}

	.run-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.run-row {
		display: grid;
		grid-template-columns: 6rem 1fr;
		gap: var(--space-md);
		align-items: center;
		width: 100%;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: left;
		text-decoration: none;
		color: inherit;
		font: inherit;
		cursor: pointer;
		transition: border-color var(--transition-fast);
	}

	.run-row:hover {
		border-color: var(--color-primary);
	}

	.run-date {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}

	.run-main h3 {
		margin: 0 0 0.2rem 0;
		font-size: 1rem;
		font-weight: 600;
	}

	.run-meta {
		display: flex;
		gap: var(--space-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		flex-wrap: wrap;
	}

	.run-meta .material-symbols {
		font-size: 0.95rem;
		vertical-align: -3px;
		margin-right: 0.2rem;
	}

	.people-list {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: var(--space-sm);
	}

	.person-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		transition: border-color var(--transition-fast);
	}

	.person-row:hover {
		border-color: var(--color-primary);
	}

	.avatar-sm {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: grid;
		place-items: center;
		font-size: 0.85rem;
		font-weight: 700;
		overflow: hidden;
		flex-shrink: 0;
	}

	.avatar-sm img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.empty {
		text-align: center;
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}

	.muted {
		color: var(--color-text-tertiary);
	}

	/* ── Feed tab (self-only) ─────────────────────────────────────
	   Mirrors the card grid the standalone /feed used to render so the
	   feed reads the same as before — same minmax(22rem, 1fr) shape,
	   same track preview + stats + kudos pills layout. /feed is now a
	   thin redirect into this tab. */
	.feed-toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-md);
	}

	.activity-group {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		padding: 2px;
		gap: 2px;
	}

	.activity-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.35rem 0.7rem;
		border: none;
		border-radius: calc(var(--radius-md) - 2px);
		background: transparent;
		font: inherit;
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.activity-btn .material-symbols {
		font-size: 1.05rem;
	}

	.activity-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}

	.activity-btn.active {
		background: var(--color-primary);
		color: white;
	}

	.activity-btn.active:hover {
		background: var(--color-primary-hover);
	}

	.window-hint {
		margin-left: auto;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		font-weight: 500;
	}

	@media (max-width: 50rem) {
		.activity-label {
			display: none;
		}
		.window-hint {
			margin-left: 0;
		}
	}

	.feed {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.entry {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	.entry:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.entry-map {
		width: 100%;
		height: 9rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.entry-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-md) var(--space-lg);
		border-bottom: 1px solid var(--color-border);
	}

	.author {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		text-decoration: none;
		color: inherit;
	}

	.author-name {
		font-weight: 600;
	}

	.when {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}

	.entry-body {
		display: block;
		width: 100%;
		padding: 0;
		text-decoration: none;
		color: inherit;
		background: transparent;
		border: 0;
		text-align: left;
		cursor: pointer;
		flex: 1;
	}

	.entry-stats-wrap {
		padding: var(--space-lg);
		transition: background var(--transition-fast);
	}

	.entry-body:hover .entry-stats-wrap {
		background: var(--color-bg-tertiary);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
	}

	.stat {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
	}

	.stat-num {
		font-size: 1.25rem;
		font-weight: 700;
		color: var(--color-text);
	}

	.stat-label {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.entry-foot {
		display: flex;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		border-top: 1px solid var(--color-border);
	}

	.kudos-pill,
	.comment-pill {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.3rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		cursor: pointer;
		text-decoration: none;
		transition:
			color var(--transition-fast),
			border-color var(--transition-fast),
			background var(--transition-fast);
	}

	.kudos-pill .material-symbols,
	.comment-pill .material-symbols {
		font-size: 1rem;
	}

	.kudos-pill:disabled {
		cursor: not-allowed;
	}

	.kudos-pill:not(:disabled):hover,
	.comment-pill:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.kudos-pill.given {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.feed-empty {
		max-width: 28rem;
		margin: var(--space-2xl) 0;
		padding: var(--space-2xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		text-align: center;
		align-items: center;
	}

	.empty-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 3rem;
		color: var(--color-text-tertiary);
	}

	.feed-empty h2 {
		font-size: 1.25rem;
		font-weight: 700;
		margin: 0;
	}

	.feed-empty p {
		color: var(--color-text-secondary);
		margin: 0;
	}

	.load-more {
		text-align: center;
		padding: var(--space-xl);
	}
</style>
