<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchFollowingFeed, type FeedEntry } from '$lib/data';
	import { formatDuration } from '$lib/mock-data';
	import { formatDistance, formatPace } from '$lib/units.svelte';

	let entries = $state<FeedEntry[]>([]);
	let loading = $state(true);
	let loadingMore = $state(false);
	let exhausted = $state(false);

	async function loadInitial() {
		loading = true;
		entries = await fetchFollowingFeed({ limit: 20 });
		exhausted = entries.length < 20;
		loading = false;
	}

	async function loadMore() {
		if (loadingMore || exhausted || entries.length === 0) return;
		loadingMore = true;
		const last = entries[entries.length - 1];
		const more = await fetchFollowingFeed({
			limit: 20,
			cursor: { started_at: last.started_at, id: last.id },
		});
		entries = [...entries, ...more];
		exhausted = more.length < 20;
		loadingMore = false;
	}

	onMount(loadInitial);

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

	function pace(distance_m: number, duration_s: number): string {
		if (distance_m <= 0 || duration_s <= 0) return '—';
		return formatPace(duration_s, distance_m);
	}
</script>

<svelte:head>
	<title>Feed — Run Onward</title>
</svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">Loading…</p>
	{:else if entries.length === 0}
		<div class="empty">
			<span class="material-symbols empty-icon">groups</span>
			<h2>Your feed is empty</h2>
			<p>
				Follow other runners to see their public runs here. Visit a club's Members tab or open a
				public run to find a profile to follow.
			</p>
			<a href="/clubs" class="btn btn-primary">Browse clubs</a>
		</div>
	{:else}
		<div class="feed">
			{#each entries as entry (entry.id)}
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
					<a href="/share/run/{entry.id}" class="entry-body">
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
					</a>
				</article>
			{/each}
		</div>

		{#if !exhausted}
			<div class="load-more">
				<button class="btn btn-outline" onclick={loadMore} disabled={loadingMore}>
					{loadingMore ? 'Loading…' : 'Load more'}
				</button>
			</div>
		{/if}
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}

	.feed {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		max-width: 48rem;
	}

	.entry {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
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

	.when {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}

	.entry-body {
		display: block;
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
		transition: background var(--transition-fast);
	}

	.entry-body:hover {
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

	.empty {
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

	.empty h2 {
		font-size: 1.25rem;
		font-weight: 700;
		margin: 0;
	}

	.empty p {
		color: var(--color-text-secondary);
		margin: 0;
	}

	.muted {
		color: var(--color-text-tertiary);
	}

	.load-more {
		text-align: center;
		padding: var(--space-xl);
	}
</style>
