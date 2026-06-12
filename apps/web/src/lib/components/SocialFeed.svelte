<script lang="ts">
	import { onMount } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { formatDuration, formatRelativeTime } from '$lib/format/time';
	import { currentLocale, m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import {
		fetchFollowingActivityFeed,
		fetchEngagementSummaries,
		giveKudos,
		rescindKudos,
		FEED_WINDOW_DAYS,
		type ActivityFeedEntry,
		type RunFeedEntry,
		type LiftFeedEntry,
	} from '$lib/core/data';

	import { formatDistance, formatPace, formatWeight } from '$lib/format/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';

	const FEED_ACTIVITIES: { value: string; labelKey: MessageKey; icon: string }[] = [
		{ value: 'all', labelKey: 'socialFeed.activityAll', icon: 'apps' },
		{ value: 'run', labelKey: 'socialFeed.activityRun', icon: 'directions_run' },
		{ value: 'walk', labelKey: 'socialFeed.activityWalk', icon: 'directions_walk' },
		{ value: 'cycle', labelKey: 'socialFeed.activityCycle', icon: 'directions_bike' },
		{ value: 'hike', labelKey: 'socialFeed.activityHike', icon: 'terrain' },
		{ value: 'lift', labelKey: 'socialFeed.activityLift', icon: 'fitness_center' },
	];

	let entries = $state<ActivityFeedEntry[]>([]);
	let engagement = $state<
		Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>
	>(new Map());
	let loading = $state(false);
	let loaded = $state(false);
	let exhausted = $state(false);
	let loadingMore = $state(false);
	let kudosBusy = $state<Set<string>>(new Set());
	let activityFilter = $state<string>('all');
	let followingCount = $state(0);
	let followsAnyone = $derived(followingCount > 0);

	let mounted = false;

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await Promise.all([refreshFollowingCount(), load()]);
		mounted = true;
	});

	$effect(() => {
		const _ = activityFilter;
		if (mounted) load();
	});

	async function refreshFollowingCount() {
		const viewerId = auth.user?.id;
		if (!viewerId) {
			followingCount = 0;
			return;
		}
		const { count } = await (
			await import('$lib/core/supabase')
		).supabase
			.from('user_follows')
			.select('followee_id', { count: 'exact', head: true })
			.eq('follower_id', viewerId);
		followingCount = count ?? 0;
	}

	// Engagement (kudos / comments) only exists for runs — run_kudos /
	// run_comments key on a run id. Lift cards carry no engagement footer.
	function runIds(es: ActivityFeedEntry[]): string[] {
		return es.filter((e) => e.kind === 'run').map((e) => e.id);
	}

	async function load() {
		loading = true;
		try {
			entries = await fetchFollowingActivityFeed({ limit: 20, activityType: activityFilter });
			exhausted = entries.length < 20;
			engagement = await fetchEngagementSummaries(runIds(entries));
		} catch (e) {
			showToast(m('socialFeed.loadFeedError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			loading = false;
			loaded = true;
		}
	}

	async function loadMore() {
		if (loadingMore || exhausted || entries.length === 0) return;
		loadingMore = true;
		try {
			const last = entries[entries.length - 1];
			const more = await fetchFollowingActivityFeed({
				limit: 20,
				cursor: { started_at: last.started_at, id: last.id },
				activityType: activityFilter,
			});
			entries = [...entries, ...more];
			exhausted = more.length < 20;
			const moreEng = await fetchEngagementSummaries(runIds(more));
			const merged = new Map(engagement);
			for (const [k, v] of moreEng) merged.set(k, v);
			engagement = merged;
		} catch (e) {
			// Without this catch, a network error on the explicit "load
			// more" scroll trigger left the user scrolling forever
			// waiting for entries that never arrived. Surface so they
			// know to retry.
			showToast(m('socialFeed.loadMoreError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			loadingMore = false;
		}
	}

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
			showToast(m('socialFeed.kudosError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			const next = new Set(kudosBusy);
			next.delete(runId);
			kudosBusy = next;
		}
	}

	function pace(distance_m: number, duration_s: number): string {
		if (distance_m <= 0 || duration_s <= 0) return '—';
		return formatPace(duration_s, distance_m);
	}

	function runTitle(entry: RunFeedEntry): string {
		const t = (entry.metadata as Record<string, unknown> | null)?.title;
		return typeof t === 'string' ? t.trim() : '';
	}

	function liftTitle(entry: LiftFeedEntry): string {
		return entry.title?.trim() || m('socialFeed.liftUntitled');
	}

</script>

<div class="social-feed">
	<div class="feed-toolbar">
		<div class="activity-group" role="group" aria-label={m('socialFeed.activityTypeGroup')}>
			{#each FEED_ACTIVITIES as act}
				<button
					class="activity-btn"
					class:active={activityFilter === act.value}
					onclick={() => (activityFilter = act.value)}
					title={m(act.labelKey)}
					aria-label={m(act.labelKey)}
					aria-pressed={activityFilter === act.value}
					type="button"
				>
					<span class="material-symbols" aria-hidden="true">{act.icon}</span>
					<span class="activity-label">{m(act.labelKey)}</span>
				</button>
			{/each}
		</div>
		<span class="window-hint">{m('socialFeed.windowHint', { n: FEED_WINDOW_DAYS })}</span>
	</div>

	{#if loading && !loaded}
		<div class="feed" aria-hidden="true">
			{#each Array(4) as _, i (i)}
				<div class="skel-card">
					<span class="skel skel-map"></span>
					<div class="skel-card-body">
						<span class="skel skel-line skel-w-60"></span>
						<span class="skel skel-line skel-w-40"></span>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('socialFeed.loadingFeed')}</p>
	{:else if entries.length === 0}
		<div class="empty-card">
			{#if !followsAnyone}
				<img src="/icon-192.png" alt="" width="64" height="64" class="empty-mark" />
				<h3>{m('socialFeed.emptyTitle')}</h3>
				<p class="empty-text">
					{m('socialFeed.emptyText')}
				</p>
				<a href="/social?tab=people" class="btn btn-primary">
					<span class="material-symbols" aria-hidden="true">person_search</span>
					{m('socialFeed.findPeople')}
				</a>
			{:else if activityFilter !== 'all'}
				<span class="material-symbols empty-icon" aria-hidden="true">filter_alt_off</span>
				<h3>{m('socialFeed.noMatchesTitle')}</h3>
				<p class="empty-text">
					{m('socialFeed.noMatchesText', { n: FEED_WINDOW_DAYS })}
				</p>
				<button
					class="btn btn-primary"
					type="button"
					onclick={() => (activityFilter = 'all')}
				>
					{m('socialFeed.clearFilters')}
				</button>
			{:else}
				<span class="material-symbols empty-icon" aria-hidden="true">schedule</span>
				<h3>{m('socialFeed.noActivityTitle')}</h3>
				<p class="empty-text">
					{m('socialFeed.noActivityText', { n: FEED_WINDOW_DAYS })}
				</p>
			{/if}
		</div>
	{:else}
		<div class="feed">
			{#each entries as entry (entry.id)}
				<article class="entry">
					<header class="entry-head">
						<a href="/u/{entry.author.id}" class="author">
							<Avatar
								url={entry.author.avatar_url}
								name={entry.author.display_name}
								size="1.75rem"
								font="0.8rem"
								bg="primary"
							/>
							<span class="author-name">{entry.author.display_name ?? m('socialFeed.runnerFallback')}</span>
						</a>
						<span class="when">{formatRelativeTime(entry.started_at, undefined, currentLocale())}</span>
					</header>
					{#if entry.kind === 'lift'}
						<a class="entry-body" href="/share/workout/{entry.id}" data-testid="lift-card">
							<div class="entry-stats-wrap">
								<h3 class="entry-title lift-title">
									<span class="material-symbols lift-glyph" aria-hidden="true">fitness_center</span>
									{liftTitle(entry)}
								</h3>
								<div class="stats stats-2">
									<div class="stat">
										<span class="stat-num">{entry.set_count}</span>
										<span class="stat-label">{m('socialFeed.liftSetsLabel')}</span>
									</div>
									{#if entry.volume_kg > 0}
										<div class="stat">
											<span class="stat-num">{formatWeight(entry.volume_kg)}</span>
											<span class="stat-label">{m('socialFeed.liftVolume')}</span>
										</div>
									{/if}
								</div>
							</div>
						</a>
					{:else}
						{@const eng = engagement.get(entry.id) ?? { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 }}
						<a class="entry-body" href="/runs/{entry.id}">
							{#if entry.has_track}
								<div class="entry-map">
									<!-- public_runs dropped track_url; the non-owner clip
									     path fetches by runId via clip-public-track. -->
									<RunTrackPreview
										runId={entry.id}
										trackUrl={null}
										ownerUserId={entry.author.id}
									/>
								</div>
							{/if}
							<div class="entry-stats-wrap">
								{#if runTitle(entry)}
									<h3 class="entry-title">{runTitle(entry)}</h3>
								{/if}
								<div class="stats">
									<div class="stat">
										<span class="stat-num">{formatDistance(entry.distance_m)}</span>
										<span class="stat-label">{m('socialFeed.statDistance')}</span>
									</div>
									<div class="stat">
										<span class="stat-num">{formatDuration(entry.duration_s)}</span>
										<span class="stat-label">{m('socialFeed.statTime')}</span>
									</div>
									<div class="stat">
										<span class="stat-num">{pace(entry.distance_m, entry.duration_s)}</span>
										<span class="stat-label">{m('socialFeed.statPace')}</span>
									</div>
								</div>
							</div>
						</a>
						<footer class="entry-foot">
							<button
								class="kudos-pill"
								class:given={eng.viewer_has_kudos}
								type="button"
								disabled={kudosBusy.has(entry.id)}
								onclick={() => toggleKudos(entry.id)}
								aria-label={eng.viewer_has_kudos ? m('socialFeed.rescindKudos') : m('socialFeed.giveKudos')}
							>
								<span class="material-symbols" aria-hidden="true">
									{eng.viewer_has_kudos ? 'favorite' : 'favorite_border'}
								</span>
								<span>{eng.kudos_count}</span>
							</button>
							<a class="comment-pill" href="/runs/{entry.id}" aria-label={m('socialFeed.viewComments')}>
								<span class="material-symbols" aria-hidden="true">chat_bubble_outline</span>
								<span>{eng.comment_count}</span>
							</a>
						</footer>
					{/if}
				</article>
			{/each}
		</div>

		{#if !exhausted}
			<div class="load-more">
				<button class="btn btn-outline" onclick={loadMore} disabled={loadingMore}>
					{loadingMore ? m('shell.loading') : m('socialFeed.loadMore')}
				</button>
			</div>
		{/if}
	{/if}
</div>

<style>
	.social-feed {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.feed-toolbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.activity-group {
		display: inline-flex;
		gap: 0.3rem;
		flex-wrap: wrap;
	}
	.activity-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.35rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		font-weight: 500;
		cursor: pointer;
	}
	.activity-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-text);
	}
	.activity-btn.active {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.activity-btn .material-symbols { font-size: 1rem; }
	.window-hint {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
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
	}
	.entry-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
	}
	.author {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		text-decoration: none;
		color: inherit;
	}
	.author-name {
		font-weight: 600;
		font-size: 0.9rem;
	}
	.when {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.entry-body {
		display: flex;
		flex-direction: column;
		text-align: start;
		background: transparent;
		border: none;
		padding: 0;
		text-decoration: none;
		color: inherit;
		cursor: pointer;
	}
	.entry-map {
		aspect-ratio: 16 / 9;
		background: var(--color-bg-tertiary);
	}
	.entry-stats-wrap {
		padding: var(--space-sm) var(--space-md);
	}
	.entry-title {
		margin: 0 0 var(--space-sm);
		font-size: 0.95rem;
		font-weight: 600;
		line-height: 1.3;
		color: var(--color-text);
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 0.5rem;
	}
	.stats-2 {
		grid-template-columns: repeat(2, 1fr);
	}
	.lift-title {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.lift-glyph {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.stat {
		display: flex;
		flex-direction: column;
	}
	.stat-num {
		font-weight: 700;
		font-size: 1rem;
	}
	.stat-label {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.entry-foot {
		display: flex;
		gap: 0.4rem;
		padding: var(--space-sm) var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.kudos-pill,
	.comment-pill {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.25rem 0.65rem;
		font-size: 0.82rem;
		border: 1px solid var(--color-border);
		background: transparent;
		border-radius: 999px;
		cursor: pointer;
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.kudos-pill .material-symbols,
	.comment-pill .material-symbols { font-size: 1rem; }
	.kudos-pill.given {
		background: color-mix(in srgb, var(--color-danger) 12%, transparent);
		color: var(--color-danger);
		border-color: color-mix(in srgb, var(--color-danger) 40%, transparent);
	}
	.kudos-pill:disabled { opacity: 0.6; cursor: progress; }
	.load-more {
		display: flex;
		justify-content: center;
	}
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
	.empty-card h3 { margin: 0; font-size: 1.1rem; font-weight: 600; }
	.empty-icon {
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
	.material-symbols { font-family: 'Material Symbols Outlined'; }
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
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	.skel-map {
		aspect-ratio: 16 / 9;
		border-radius: 0;
	}
	.skel-card-body {
		padding: var(--space-sm) var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.skel-line { height: 0.75rem; }
	.skel-w-40 { width: 40%; }
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
</style>
