<script lang="ts">
	import { page } from '$app/stores';
	import {
		fetchPublicProfile,
		fetchPublicRunsByUser,
		fetchFollowers,
		fetchFollowing,
		followUser,
		unfollowUser,
		type ProfileSummary,
		type PublicProfile,
	} from '$lib/data';
	import { formatDuration } from '$lib/mock-data';
	import { formatDistance, formatPace } from '$lib/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import RunShareView from '$lib/components/RunShareView.svelte';
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
	let tab = $state<'runs' | 'followers' | 'following' | 'notifications'>('runs');

	let isSelf = $derived(auth.user?.id === userId);
	let openRunId = $state<string | null>(null);

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

	// Deep-link the followers / following / notifications tab via
	// `?tab=…` so the feed-header chips and the bell popover can link
	// straight into the right panel. The notifications tab is gated to
	// `isSelf` — even if a deep link asks for it on someone else's
	// profile, RLS hides their notifications anyway, so collapse the
	// invalid case to the runs tab.
	$effect(() => {
		const t = $page.url.searchParams.get('tab');
		if (t === 'followers' || t === 'following' || t === 'runs') tab = t;
		else if (t === 'notifications' && isSelf) tab = 'notifications';
	});

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
		// preserves the user's mental flow; the /feed fallback covers
		// direct navigation / fresh tabs where there's nothing to go
		// back to.
		if (typeof history !== 'undefined' && history.length > 1) {
			history.back();
		} else {
			location.href = '/feed';
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
</style>
