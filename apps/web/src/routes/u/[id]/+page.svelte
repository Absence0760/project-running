<script lang="ts">
	import { page } from '$app/stores';
	import Avatar from '$lib/components/Avatar.svelte';
	import { formatDuration, formatRelativeTime } from '$lib/time';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import {
		fetchPublicProfile,
		fetchPublicRunsByUser,
		fetchFollowers,
		fetchFollowing,
		FOLLOW_PAGE_SIZE,
		fetchFollowingFeed,
		fetchEngagementSummaries,
		followUser,
		unfollowUser,
		blockUser,
		unblockUser,
		isBlockedByViewer,
		giveKudos,
		rescindKudos,
		FEED_WINDOW_DAYS,
		type FeedEntry,
		type ProfileSummary,
		type PublicProfile,
	} from '$lib/data';
	
	import { formatDistance, formatPace } from '$lib/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import RunShareView from '$lib/components/RunShareView.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';
	import NotificationsList from '$lib/components/NotificationsList.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import { notificationStore } from '$lib/stores/notifications.svelte';
	import type { Run } from '$lib/types';

	let userId = $derived($page.params.id as string);
	let profile = $state<ProfileSummary | null>(null);
	let runs = $state<Run[]>([]);
	let followers = $state<PublicProfile[]>([]);
	let following = $state<PublicProfile[]>([]);
	let followersHasMore = $state(false);
	let followingHasMore = $state(false);
	let followersLoadingMore = $state(false);
	let followingLoadingMore = $state(false);
	let loading = $state(true);
	let busy = $state(false);
	let tab = $state<'runs' | 'followers' | 'following' | 'notifications' | 'feed'>('runs');

	let isSelf = $derived(auth.user?.id === userId);
	let openRunId = $state<string | null>(null);

	// Per-row follow state for the Followers / Following lists. Keys are
	// target user IDs the viewer currently follows. Hydrated from one
	// `user_follows` query that intersects the loaded list with the
	// viewer's outbound edges — no per-row round-trip.
	let viewerFollows = $state<Set<string>>(new Set());
	let rowBusy = $state<Set<string>>(new Set());
	let showReportDialog = $state(false);
	// Block state — see migration 20261012_001_user_blocks.sql. We
	// track whether the viewer has blocked the target so the same
	// button toggles between Block and Unblock; a confirm dialog
	// gates the destructive direction (block drains follows on both
	// sides, so it's not a no-cost click).
	let viewerHasBlocked = $state(false);
	let blockBusy = $state(false);
	let showBlockConfirm = $state(false);

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
		const [p, r, fr, fg, blocked] = await Promise.all([
			fetchPublicProfile(userId),
			fetchPublicRunsByUser(userId, 20),
			fetchFollowers(userId, { limit: FOLLOW_PAGE_SIZE }),
			fetchFollowing(userId, { limit: FOLLOW_PAGE_SIZE }),
			auth.loggedIn && auth.user?.id !== userId
				? isBlockedByViewer(userId)
				: Promise.resolve(false),
		]);
		profile = p;
		runs = r;
		followers = fr;
		following = fg;
		followersHasMore = fr.length === FOLLOW_PAGE_SIZE;
		followingHasMore = fg.length === FOLLOW_PAGE_SIZE;
		viewerHasBlocked = blocked;
		loading = false;
		hydrateViewerFollows();
	}

	async function loadMoreFollowers() {
		if (followersLoadingMore || !followersHasMore) return;
		followersLoadingMore = true;
		try {
			const more = await fetchFollowers(userId, {
				limit: FOLLOW_PAGE_SIZE,
				offset: followers.length,
			});
			followers = [...followers, ...more];
			followersHasMore = more.length === FOLLOW_PAGE_SIZE;
			hydrateViewerFollows();
		} catch (e) {
			showToast(`Could not load more followers: ${e}`, 'error');
		} finally {
			followersLoadingMore = false;
		}
	}

	async function loadMoreFollowing() {
		if (followingLoadingMore || !followingHasMore) return;
		followingLoadingMore = true;
		try {
			const more = await fetchFollowing(userId, {
				limit: FOLLOW_PAGE_SIZE,
				offset: following.length,
			});
			following = [...following, ...more];
			followingHasMore = more.length === FOLLOW_PAGE_SIZE;
			hydrateViewerFollows();
		} catch (e) {
			showToast(`Could not load more: ${e}`, 'error');
		} finally {
			followingLoadingMore = false;
		}
	}

	// Single-query batch lookup of viewer→target edges over the union of
	// Followers + Following row IDs (minus self, which is never followed
	// anyway). Loaded after `load()` so it never blocks first paint.
	async function hydrateViewerFollows() {
		const viewerId = auth.user?.id;
		if (!viewerId) return;
		const ids = new Set<string>();
		for (const p of followers) if (p.id !== viewerId) ids.add(p.id);
		for (const p of following) if (p.id !== viewerId) ids.add(p.id);
		if (ids.size === 0) return;
		const { data, error } = await supabase
			.from('user_follows')
			.select('followee_id')
			.eq('follower_id', viewerId)
			.in('followee_id', [...ids]);
		if (error || !data) return;
		viewerFollows = new Set(data.map((r) => r.followee_id as string));
	}

	$effect(() => {
		if (userId) load();
	});

	// Deep-link the followers / following / notifications tab via
	// `?tab=…`. The activity feed used to live here too as a self-only
	// tab — it's now hosted at /social?tab=feed, so any legacy ?tab=feed
	// link bounces over there.
	$effect(() => {
		const t = $page.url.searchParams.get('tab');
		if (t === 'feed') {
			// Out-of-band navigation — defer so we don't fire during the
			// initial $effect chain.
			queueMicrotask(() => goto('/social?tab=feed', { replaceState: true }));
			return;
		}
		if (t === 'followers' || t === 'following' || t === 'runs') tab = t;
		else if (t === 'notifications' && isSelf) tab = 'notifications';
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
		} catch (e) {
			// Without this catch the explicit "load more" scroll
			// trigger silently swallowed network errors and the user
			// scrolled forever waiting for entries that never arrived.
			showToast(`Could not load more: ${e}`, 'error');
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

	async function confirmBlock() {
		showBlockConfirm = false;
		if (!profile || !auth.loggedIn || isSelf || blockBusy) return;
		blockBusy = true;
		try {
			await blockUser(profile.id);
			viewerHasBlocked = true;
			// Block subsumes unfollow on both sides — the RPC also
			// drains existing follow rows, so the local follow state
			// must reflect that or the Follow button would lie until
			// reload.
			profile = {
				...profile,
				viewer_follows: false,
				follower_count: Math.max(profile.follower_count - (profile.viewer_follows ? 1 : 0), 0),
			};
			showToast(`Blocked ${profile.display_name ?? 'this runner'}`, 'success');
		} catch (e) {
			showToast(`Could not block: ${e}`, 'error');
		} finally {
			blockBusy = false;
		}
	}

	async function unblock() {
		if (!profile || !auth.loggedIn || isSelf || blockBusy) return;
		blockBusy = true;
		try {
			await unblockUser(profile.id);
			viewerHasBlocked = false;
			showToast(`Unblocked ${profile.display_name ?? 'this runner'}`, 'success');
		} catch (e) {
			showToast(`Could not unblock: ${e}`, 'error');
		} finally {
			blockBusy = false;
		}
	}

	async function toggleRowFollow(targetId: string) {
		if (!auth.loggedIn || targetId === auth.user?.id) return;
		if (rowBusy.has(targetId)) return;
		const wasFollowing = viewerFollows.has(targetId);
		rowBusy = new Set([...rowBusy, targetId]);
		// Optimistic flip — the action targets the row, not the page-
		// level profile, so the header counts only adjust when the
		// viewer is on their OWN profile (the rare case where this row
		// IS the page).
		const next = new Set(viewerFollows);
		if (wasFollowing) next.delete(targetId);
		else next.add(targetId);
		viewerFollows = next;
		try {
			if (wasFollowing) await unfollowUser(targetId);
			else await followUser(targetId);
		} catch (e) {
			// Roll back the optimistic flip.
			const rollback = new Set(viewerFollows);
			if (wasFollowing) rollback.add(targetId);
			else rollback.delete(targetId);
			viewerFollows = rollback;
			showToast(`Could not update follow: ${e}`, 'error');
		} finally {
			const done = new Set(rowBusy);
			done.delete(targetId);
			rowBusy = done;
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

	function setTab(t: typeof tab) {
		tab = t;
	}

	async function shareProfile() {
		const url = new URL(`/u/${userId}`, location.origin).toString();
		const title = profile?.display_name ?? 'Runner';
		// Try the OS share sheet first (mobile + Safari desktop). Fall
		// back to clipboard copy on everything else.
		try {
			if (navigator.share) {
				await navigator.share({ title, url });
				return;
			}
		} catch {
			// User dismissed the share sheet — silent.
			return;
		}
		try {
			await navigator.clipboard.writeText(url);
			showToast('Profile link copied', 'success');
		} catch {
			showToast('Could not copy link', 'error');
		}
	}
</script>

<svelte:head>
	<title>{profile?.display_name ?? 'Runner'} — Threkir</title>
</svelte:head>

<div class="page">
	<button type="button" class="back-link" onclick={goBack}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		Back
	</button>

	{#if loading}
		<div class="profile-head skel-head" aria-hidden="true">
			<span class="skel skel-avatar-xl"></span>
			<div class="skel-info">
				<span class="skel skel-line skel-w-50"></span>
				<span class="skel skel-line skel-w-40"></span>
			</div>
		</div>
		<p class="sr-only" role="status">Loading profile…</p>
	{:else if !profile}
		<div class="empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">person_off</span>
			<h3>Profile not found</h3>
			<p class="empty-text">
				This runner doesn't exist or their profile isn't visible. They may have deleted their
				account.
			</p>
			<a href="/dashboard" class="btn btn-primary">Back to dashboard</a>
		</div>
	{:else}
		<header class="profile-head">
			<div class="avatar-xl" aria-hidden="true">
				{#if profile.avatar_url}
					<img src={profile.avatar_url} alt="" />
				{:else}
					{(profile.display_name?.[0] ?? '?').toUpperCase()}
				{/if}
			</div>
			<div class="profile-info">
				<h1>{profile.display_name ?? 'Runner'}</h1>
				<div class="counts">
					<button class="count" type="button" onclick={() => setTab('runs')}>
						<span class="count-num">{runs.length}</span>
						<span class="count-label">Runs</span>
					</button>
					<button class="count" type="button" onclick={() => setTab('followers')}>
						<span class="count-num">{profile.follower_count}</span>
						<span class="count-label">Followers</span>
					</button>
					<button class="count" type="button" onclick={() => setTab('following')}>
						<span class="count-num">{profile.following_count}</span>
						<span class="count-label">Following</span>
					</button>
				</div>
			</div>
			<div class="head-actions">
				{#if !isSelf && auth.loggedIn}
					<button
						class="btn {profile.viewer_follows ? 'btn-outline' : 'btn-primary'} btn-follow"
						type="button"
						disabled={busy}
						onclick={toggleFollow}
						aria-label={profile.viewer_follows ? 'Unfollow' : 'Follow'}
					>
						<span class="material-symbols" aria-hidden="true">
							{profile.viewer_follows ? 'check' : 'person_add'}
						</span>
						<span>{profile.viewer_follows ? 'Following' : 'Follow'}</span>
					</button>
					<a
						class="btn btn-outline btn-message"
						href={`/messages/${userId}`}
						aria-label="Message"
						title="Message"
					>
						<span class="material-symbols" aria-hidden="true">chat_bubble</span>
						<span>Message</span>
					</a>
				{/if}
				<button
					class="btn btn-outline btn-icon-only"
					type="button"
					onclick={shareProfile}
					aria-label="Share profile"
					title="Share profile"
				>
					<span class="material-symbols" aria-hidden="true">share</span>
				</button>
				{#if !isSelf && auth.loggedIn}
					<button
						class="btn btn-outline btn-icon-only"
						type="button"
						onclick={() => (showReportDialog = true)}
						aria-label="Report this profile"
						title="Report this profile"
					>
						<span class="material-symbols" aria-hidden="true">flag</span>
					</button>
					<button
						class="btn btn-outline btn-icon-only btn-block"
						class:active={viewerHasBlocked}
						type="button"
						disabled={blockBusy}
						onclick={() => (viewerHasBlocked ? unblock() : (showBlockConfirm = true))}
						aria-label={viewerHasBlocked ? 'Unblock this profile' : 'Block this profile'}
						title={viewerHasBlocked ? 'Unblock this profile' : 'Block this profile'}
						aria-pressed={viewerHasBlocked}
					>
						<span class="material-symbols" aria-hidden="true">block</span>
					</button>
				{/if}
				{#if isSelf}
					<a
						href="/settings"
						class="btn btn-outline btn-icon-only"
						aria-label="Edit profile"
						title="Edit profile"
					>
						<span class="material-symbols" aria-hidden="true">edit</span>
					</a>
				{/if}
			</div>
		</header>

		<div class="tabs" role="tablist" aria-label="Profile sections">
			<button
				role="tab"
				class="tab"
				class:active={tab === 'runs'}
				aria-selected={tab === 'runs'}
				onclick={() => setTab('runs')}
			>
				Runs
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'followers'}
				aria-selected={tab === 'followers'}
				onclick={() => setTab('followers')}
			>
				Followers
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'following'}
				aria-selected={tab === 'following'}
				onclick={() => setTab('following')}
			>
				Following
			</button>
			{#if isSelf}
				<button
					role="tab"
					class="tab"
					class:active={tab === 'notifications'}
					aria-selected={tab === 'notifications'}
					onclick={() => setTab('notifications')}
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
				<div class="empty-card">
					{#if isSelf}
						<img src="/icon-192.png" alt="" width="64" height="64" class="empty-mark" />
						<h3>You haven't shared a run yet</h3>
						<p class="empty-text">
							Public runs from your history show up here. Record a run on mobile or import one
							from Strava, Garmin, or a GPX file.
						</p>
						<div class="empty-actions">
							<a href="/runs" class="btn btn-primary">
								<span class="material-symbols" aria-hidden="true">history</span>
								Open run history
							</a>
							<a href="/settings?tab=integrations" class="btn btn-outline">
								<span class="material-symbols" aria-hidden="true">sync</span>
								Connect an integration
							</a>
						</div>
					{:else}
						<span class="material-symbols empty-icon" aria-hidden="true">directions_run</span>
						<h3>No public runs yet</h3>
						<p class="empty-text">
							{profile.display_name ?? 'This runner'} hasn't shared a public run. Follow them to see
							private runs in your feed when they do.
						</p>
					{/if}
				</div>
			{:else}
				<div class="run-grid">
					{#each runs as r (r.id)}
						<button type="button" class="run-card" onclick={() => (openRunId = r.id)}>
							{#if r.track_url}
								<div class="run-map-placeholder">
									<RunTrackPreview
										runId={r.id}
										trackUrl={r.track_url}
										ownerUserId={userId}
									/>
								</div>
							{/if}
							<div class="run-details">
								<div class="run-top">
									<span class="run-date">{fmtDate(r.started_at)}</span>
								</div>
								<div class="run-stats">
									<div class="run-stat">
										<span class="run-stat-value">{formatDistance(r.distance_m)}</span>
										<span class="run-stat-label section-label">Distance</span>
									</div>
									<div class="run-stat">
										<span class="run-stat-value">{formatDuration(r.duration_s)}</span>
										<span class="run-stat-label section-label">Time</span>
									</div>
									<div class="run-stat">
										<span class="run-stat-value">{pace(r.distance_m, r.duration_s)}</span>
										<span class="run-stat-label section-label">Pace</span>
									</div>
								</div>
							</div>
						</button>
					{/each}
				</div>
			{/if}
		{:else if tab === 'followers'}
			{#if followers.length === 0}
				<div class="empty-card">
					<span class="material-symbols empty-icon" aria-hidden="true">group_add</span>
					<h3>No followers yet</h3>
					<p class="empty-text">
						{#if isSelf}
							When other runners follow you, they'll show up here and see your public runs in
							their feed.
						{:else}
							{profile.display_name ?? 'This runner'} hasn't picked up any followers yet.
						{/if}
					</p>
					{#if isSelf}
						<a href="/clubs" class="btn btn-primary">
							<span class="material-symbols" aria-hidden="true">groups</span>
							Find a club
						</a>
					{/if}
				</div>
			{:else}
				<div class="people-list">
					{#each followers as p (p.id)}
						{@const isViewer = p.id === auth.user?.id}
						{@const viewerFollowsRow = viewerFollows.has(p.id)}
						<div class="person-row">
							<a href="/u/{p.id}" class="person-main">
								<Avatar url={p.avatar_url} name={p.display_name} size="2rem" font="0.85rem" />
								<span class="person-name">{p.display_name ?? 'Runner'}</span>
							</a>
							{#if auth.loggedIn && !isViewer}
								<button
									type="button"
									class="btn btn-sm {viewerFollowsRow ? 'btn-outline' : 'btn-primary'} person-toggle"
									disabled={rowBusy.has(p.id)}
									onclick={() => toggleRowFollow(p.id)}
									aria-label={viewerFollowsRow
										? `Unfollow ${p.display_name ?? 'runner'}`
										: `Follow ${p.display_name ?? 'runner'}`}
								>
									<span class="material-symbols" aria-hidden="true">
										{viewerFollowsRow ? 'check' : 'person_add'}
									</span>
									<span class="toggle-label">
										{viewerFollowsRow ? 'Following' : 'Follow'}
									</span>
								</button>
							{/if}
						</div>
					{/each}
				</div>
				{#if followersHasMore}
					<div class="load-more">
						<button class="btn btn-outline" onclick={loadMoreFollowers} disabled={followersLoadingMore}>
							{followersLoadingMore ? 'Loading…' : 'Load more'}
						</button>
					</div>
				{/if}
			{/if}
		{:else if tab === 'following'}
			{#if following.length === 0}
				<div class="empty-card">
					<span class="material-symbols empty-icon" aria-hidden="true">person_search</span>
					<h3>
						{isSelf ? 'Not following anyone yet' : 'Not following anyone'}
					</h3>
					<p class="empty-text">
						{#if isSelf}
							Follow other runners to see their public runs in your feed. Browse a club's Members
							tab or open a public run to find someone to follow.
						{:else}
							{profile.display_name ?? 'This runner'} hasn't followed anyone yet.
						{/if}
					</p>
					{#if isSelf}
						<a href="/clubs" class="btn btn-primary">
							<span class="material-symbols" aria-hidden="true">groups</span>
							Browse clubs
						</a>
					{/if}
				</div>
			{:else}
				<div class="people-list">
					{#each following as p (p.id)}
						{@const isViewer = p.id === auth.user?.id}
						{@const viewerFollowsRow = viewerFollows.has(p.id)}
						<div class="person-row">
							<a href="/u/{p.id}" class="person-main">
								<Avatar url={p.avatar_url} name={p.display_name} size="2rem" font="0.85rem" />
								<span class="person-name">{p.display_name ?? 'Runner'}</span>
							</a>
							{#if auth.loggedIn && !isViewer}
								<button
									type="button"
									class="btn btn-sm {viewerFollowsRow ? 'btn-outline' : 'btn-primary'} person-toggle"
									disabled={rowBusy.has(p.id)}
									onclick={() => toggleRowFollow(p.id)}
									aria-label={viewerFollowsRow
										? `Unfollow ${p.display_name ?? 'runner'}`
										: `Follow ${p.display_name ?? 'runner'}`}
								>
									<span class="material-symbols" aria-hidden="true">
										{viewerFollowsRow ? 'check' : 'person_add'}
									</span>
									<span class="toggle-label">
										{viewerFollowsRow ? 'Following' : 'Follow'}
									</span>
								</button>
							{/if}
						</div>
					{/each}
				</div>
				{#if followingHasMore}
					<div class="load-more">
						<button class="btn btn-outline" onclick={loadMoreFollowing} disabled={followingLoadingMore}>
							{followingLoadingMore ? 'Loading…' : 'Load more'}
						</button>
					</div>
				{/if}
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
							<span class="material-symbols" aria-hidden="true">{act.icon}</span>
							<span class="activity-label">{act.label}</span>
						</button>
					{/each}
				</div>
				<span class="window-hint">Last {FEED_WINDOW_DAYS} days</span>
			</div>

			{#if feedLoading && !feedLoaded}
				<div class="feed" aria-hidden="true">
					{#each Array(6) as _, i (i)}
						<div class="skel-card">
							<span class="skel skel-map"></span>
							<div class="skel-card-body">
								<div class="skel-card-top">
									<span class="skel skel-line skel-w-40"></span>
									<span class="skel skel-pill"></span>
								</div>
								<div class="skel-card-stats">
									<div class="skel-card-stat">
										<span class="skel skel-line skel-w-60"></span>
										<span class="skel skel-line skel-w-30"></span>
									</div>
									<div class="skel-card-stat">
										<span class="skel skel-line skel-w-50"></span>
										<span class="skel skel-line skel-w-30"></span>
									</div>
									<div class="skel-card-stat">
										<span class="skel skel-line skel-w-50"></span>
										<span class="skel skel-line skel-w-30"></span>
									</div>
								</div>
							</div>
						</div>
					{/each}
				</div>
				<p class="sr-only" role="status">Loading feed…</p>
			{:else if feedEntries.length === 0}
				<div class="empty-card">
					{#if !followsAnyone}
						<img src="/icon-192.png" alt="" width="64" height="64" class="empty-mark" />
						<h3>Your feed is empty</h3>
						<p class="empty-text">
							Follow other runners to see their public runs here. Visit a club's Members tab or
							open a public run to find a profile to follow.
						</p>
						<a href="/clubs" class="btn btn-primary">
							<span class="material-symbols" aria-hidden="true">groups</span>
							Browse clubs
						</a>
					{:else if activityFilter !== 'all'}
						<span class="material-symbols empty-icon" aria-hidden="true">filter_alt_off</span>
						<h3>No matches</h3>
						<p class="empty-text">
							Nothing matches the current filter in the last {FEED_WINDOW_DAYS} days.
						</p>
						<button
							class="btn btn-primary"
							type="button"
							onclick={() => (activityFilter = 'all')}
						>
							Clear filters
						</button>
					{:else}
						<span class="material-symbols empty-icon" aria-hidden="true">schedule</span>
						<h3>No recent activity</h3>
						<p class="empty-text">
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
									<Avatar url={entry.author.avatar_url} name={entry.author.display_name} size="2rem" font="0.85rem" />
									<span class="author-name">{entry.author.display_name ?? 'Runner'}</span>
								</a>
								<span class="when">{formatRelativeTime(entry.started_at)}</span>
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
									aria-label={eng.viewer_has_kudos ? 'Rescind kudos' : 'Give kudos'}
								>
									<span class="material-symbols" aria-hidden="true">
										{eng.viewer_has_kudos ? 'favorite' : 'favorite_border'}
									</span>
									<span>{eng.kudos_count}</span>
								</button>
								<button
									class="comment-pill"
									type="button"
									onclick={() => (openRunId = entry.id)}
									aria-label="View comments"
								>
									<span class="material-symbols" aria-hidden="true">chat_bubble_outline</span>
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

<ReportDialog
	open={showReportDialog}
	targetKind="user"
	targetId={userId}
	targetLabel={profile?.display_name ?? undefined}
	onclose={() => (showReportDialog = false)}
/>

<ConfirmDialog
	open={showBlockConfirm}
	title="Block {profile?.display_name ?? 'this runner'}?"
	message="They won't be able to follow you, give kudos to your runs, or comment on them. Any existing follow between you in either direction will be cleared. You can unblock from this page at any time."
	confirmLabel="Block"
	cancelLabel="Cancel"
	danger
	onconfirm={confirmBlock}
	oncancel={() => (showBlockConfirm = false)}
/>

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
		font-variant-numeric: tabular-nums;
	}

	.count-label {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.head-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-left: auto;
	}

	.btn-follow {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.btn-follow .material-symbols {
		font-size: 1.1rem;
	}

	/* Icon-only action button — same height as `.btn-follow` so the
	   share / edit pair sits on the same baseline as Follow. */
	.btn-icon-only {
		display: inline-grid;
		place-items: center;
		width: 2.4rem;
		height: 2.4rem;
		padding: 0;
		flex-shrink: 0;
	}

	.btn-icon-only .material-symbols {
		font-size: 1.15rem;
	}

	/* Block button: outline by default, switches to a red-tinted fill
	   when the viewer has the target blocked. The colour cue is the
	   only signal that the toggle is in the active state — the icon
	   stays the same (Material `block`). */
	.btn-block.active {
		background: color-mix(in srgb, var(--color-danger, #d33) 14%, transparent);
		border-color: var(--color-danger, #d33);
		color: var(--color-danger, #d33);
	}

	.btn-block.active:hover {
		background: color-mix(in srgb, var(--color-danger, #d33) 22%, transparent);
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		margin-bottom: var(--space-md);
		border-bottom: 1px solid var(--color-border);
		flex-wrap: wrap;
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
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.tab:hover {
		color: var(--color-text);
	}

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	/* Quieter pill than the brand-saturated primary fill — sits beside
	   the tab label without competing with the active underline. */
	.tab-badge {
		display: inline-grid;
		place-items: center;
		min-width: 1.2rem;
		height: 1.2rem;
		padding: 0 0.4rem;
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
		font-size: 0.7rem;
		font-weight: 700;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
	}

	.tab.active .tab-badge {
		background: var(--color-primary);
		color: white;
	}

	/* Runs tab — card grid that mirrors /runs and the Feed-tab archetype
	   so the page reads as one product rather than two. */
	.run-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.run-card {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
		text-align: left;
		font: inherit;
		color: inherit;
		cursor: pointer;
		padding: 0;
	}

	.run-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.run-map-placeholder {
		width: 100%;
		height: 8rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.run-details {
		flex: 1;
		min-width: 0;
		padding: var(--space-md) var(--space-lg);
	}

	.run-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-sm);
		gap: var(--space-sm);
	}

	.run-date {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-weight: 500;
	}

	.run-stats {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
	}

	.run-stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}

	.run-stat-value {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}

	.run-stat:first-child .run-stat-value {
		font-size: 1.3rem;
		color: var(--color-primary);
	}

	.run-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.people-list {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
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
		transition: border-color var(--transition-fast);
	}

	.person-row:hover {
		border-color: var(--color-primary);
	}

	.person-main {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex: 1;
		min-width: 0;
		text-decoration: none;
		color: inherit;
	}

	.person-name {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 500;
	}

	.person-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		flex-shrink: 0;
	}

	.person-toggle .material-symbols {
		font-size: 1rem;
	}

	@media (max-width: 30rem) {
		.toggle-label {
			display: none;
		}
		.person-toggle {
			padding: 0.35rem 0.55rem;
		}
	}



	/* Empty-state card — same shape as /clubs, /routes, /runs. Card with
	   icon (or brand mark) + h3 + explainer + CTA. */
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}

	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}

	.empty-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}

	.empty-mark {
		display: block;
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-sm);
	}

	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}

	.empty-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.empty-actions .material-symbols,
	.empty-card .btn .material-symbols {
		font-size: 1.1rem;
	}

	/* ── Feed tab (self-only) ─────────────────────────────────────
	   Mirrors the card grid the standalone /feed used to render. */
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
		font-variant-numeric: tabular-nums;
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

	.load-more {
		text-align: center;
		padding: var(--space-xl);
	}

	/* Skeletons — same shimmer language as /clubs, /runs, /routes. */
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}

	.skel-head {
		pointer-events: none;
	}

	.skel-avatar-xl {
		width: 6rem;
		height: 6rem;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.skel-info {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		flex: 1;
		min-width: 0;
	}

	.skel-line {
		height: 0.85rem;
	}

	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		pointer-events: none;
	}

	.skel-map {
		display: block;
		height: 9rem;
		width: 100%;
		border-radius: 0;
	}

	.skel-card-body {
		padding: var(--space-md) var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	.skel-card-top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}

	.skel-pill {
		display: block;
		height: 1rem;
		width: 3.5rem;
		border-radius: 9999px;
	}

	.skel-card-stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
		margin-top: 0.3rem;
	}

	.skel-card-stat {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.skel-w-30 { width: 30%; }
	.skel-w-40 { width: 40%; }
	.skel-w-50 { width: 50%; }
	.skel-w-60 { width: 60%; }

	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}

	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 50rem) {
		.profile-head {
			gap: var(--space-md);
		}
		.avatar-xl {
			width: 4.5rem;
			height: 4.5rem;
			font-size: 1.6rem;
		}
		h1 {
			font-size: 1.4rem;
		}
		.head-actions {
			margin-left: 0;
			width: 100%;
		}
		.btn-follow {
			flex: 1;
			justify-content: center;
		}
	}
</style>
