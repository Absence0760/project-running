<script lang="ts">
	import { onMount } from 'svelte';
	import {
		fetchFollowingFeed,
		fetchFollowing,
		fetchEngagementSummaries,
		giveKudos,
		rescindKudos,
		FEED_WINDOW_DAYS,
		type FeedEntry,
	} from '$lib/data';
	import { formatDuration } from '$lib/mock-data';
	import { formatDistance, formatPace } from '$lib/units.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import RunShareView from '$lib/components/RunShareView.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import type { Snapshot } from './$types';

	let entries = $state<FeedEntry[]>([]);
	let engagement = $state<
		Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>
	>(new Map());
	let loading = $state(true);
	let loadingMore = $state(false);
	let exhausted = $state(false);
	let kudosBusy = $state<Set<string>>(new Set());
	let followsAnyone = $state(false);
	let openRunId = $state<string | null>(null);

	function openRun(id: string) {
		openRunId = id;
	}

	function closeRun() {
		openRunId = null;
	}

	async function loadInitial() {
		loading = true;
		const uid = auth.user?.id;
		const [feed, following] = await Promise.all([
			fetchFollowingFeed({ limit: 20 }),
			uid ? fetchFollowing(uid, 1) : Promise.resolve([]),
		]);
		entries = feed;
		followsAnyone = following.length > 0;
		exhausted = entries.length < 20;
		engagement = await fetchEngagementSummaries(entries.map((e) => e.id));
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
		const moreEngagement = await fetchEngagementSummaries(more.map((e) => e.id));
		const merged = new Map(engagement);
		for (const [k, v] of moreEngagement) merged.set(k, v);
		engagement = merged;
		loadingMore = false;
	}

	onMount(() => {
		// Skip the fetch when snapshot already restored the feed.
		if (entries.length === 0 && loading) loadInitial();
	});

	export const snapshot: Snapshot<{
		entries: FeedEntry[];
		engagement: Array<[string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }]>;
		exhausted: boolean;
		followsAnyone: boolean;
	}> = {
		capture: () => ({
			entries,
			engagement: Array.from(engagement.entries()),
			exhausted,
			followsAnyone,
		}),
		restore: (s) => {
			entries = s.entries;
			engagement = new Map(s.engagement);
			exhausted = s.exhausted;
			followsAnyone = s.followsAnyone;
			loading = false;
		},
	};

	async function toggleKudos(runId: string) {
		if (kudosBusy.has(runId)) return;
		const current = engagement.get(runId) ?? {
			kudos_count: 0,
			viewer_has_kudos: false,
			comment_count: 0,
		};
		kudosBusy = new Set([...kudosBusy, runId]);
		try {
			if (current.viewer_has_kudos) {
				await rescindKudos(runId);
				engagement = new Map(engagement).set(runId, {
					...current,
					kudos_count: Math.max(current.kudos_count - 1, 0),
					viewer_has_kudos: false,
				});
			} else {
				await giveKudos(runId);
				engagement = new Map(engagement).set(runId, {
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
			{#if followsAnyone}
				<h2>No recent activity</h2>
				<p>
					Nobody you follow has logged a public run in the last {FEED_WINDOW_DAYS} days. Older runs
					are still on each runner's profile.
				</p>
			{:else}
				<h2>Your feed is empty</h2>
				<p>
					Follow other runners to see their public runs here. Visit a club's Members tab or open a
					public run to find a profile to follow.
				</p>
				<a href="/clubs" class="btn btn-primary">Browse clubs</a>
			{/if}
		</div>
	{:else}
		<div class="feed">
			{#each entries as entry (entry.id)}
				{@const eng = engagement.get(entry.id) ?? { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 }}
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
					<button type="button" class="entry-body" onclick={() => openRun(entry.id)}>
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
						<button class="comment-pill" type="button" onclick={() => openRun(entry.id)}>
							<span class="material-symbols">chat_bubble_outline</span>
							<span>{eng.comment_count}</span>
						</button>
					</footer>
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

<Modal open={openRunId !== null} onclose={closeRun} title="Run" wide>
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
		width: 100%;
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
		background: transparent;
		border: 0;
		text-align: left;
		cursor: pointer;
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
