<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatDuration } from '$lib/format/time';
	import { distanceInPreferred } from '$lib/format/units.svelte';
	import {
		fetchGlobalSegment,
		fetchGlobalSegmentLeaderboard,
		SEGMENT_AGE_BANDS,
		type GlobalSegment,
		type GlobalSegmentLeaderboardEntry,
		type SegmentGenderFilter,
		type SegmentAgeBand,
	} from '$lib/core/data';
	import { crownLabel } from '$lib/segments/segments';
	import Avatar from '$lib/components/Avatar.svelte';
	import RunMap from '$lib/components/RunMap.svelte';
	import type { TrackPoint } from '$lib/types';

	let { data } = $props();

	let segment = $state<GlobalSegment | null>(null);
	let loading = $state(true);
	let board = $state<GlobalSegmentLeaderboardEntry[] | null>(null);
	let genderFilter = $state<SegmentGenderFilter | null>(null);
	let ageFilter = $state<SegmentAgeBand | null>(null);

	// The catalogue geometry is public curated data (world-readable table),
	// NOT any athlete's GPS track — safe to render directly. The leaderboard
	// exposes times + ranks only; no other runner's trace ever reaches here.
	const mapTrack = $derived<TrackPoint[]>(
		(segment?.waypoints ?? []).map((w) => ({ lat: Number(w.lat), lng: Number(w.lng), ele: w.ele })),
	);

	async function refreshBoard(segmentId: string) {
		board = null;
		board = await fetchGlobalSegmentLeaderboard(segmentId, {
			gender: genderFilter,
			ageBand: ageFilter,
		});
	}

	// Re-fetch when a filter changes. Read both signals up front so the
	// effect subscribes to each regardless of branch order.
	$effect(() => {
		const _g = genderFilter;
		const _a = ageFilter;
		void _g;
		void _a;
		if (segment) refreshBoard(segment.id);
	});

	onMount(async () => {
		await auth.ready();
		segment = await fetchGlobalSegment(data.id);
		loading = false;
	});

	function fmtDist(metres: number): string {
		const { value, unit } = distanceInPreferred(metres);
		return `${value.toFixed(2)} ${unit}`;
	}
	function fmtTime(s: number): string {
		return formatDuration(Math.round(s));
	}

	const crownHolder = $derived((board ?? []).find((e) => e.rank === 1) ?? null);
	const viewerHoldsCrown = $derived(
		crownHolder != null && crownHolder.effort.user_id === auth.user?.id,
	);
	const surfaceIcon = $derived(
		segment?.surface === 'trail' ? 'terrain' : segment?.surface === 'mixed' ? 'alt_route' : 'add_road',
	);
</script>

{#if loading}
	<div class="segment-detail"><p class="loading">&nbsp;</p></div>
{:else if !segment}
	<div class="segment-detail">
		<a href="/dashboard" class="back-link">
			<span class="material-symbols">arrow_back</span>
			{m('segmentDetail.back')}
		</a>
		<div class="not-found">
			<h1>{m('segmentDetail.notFoundTitle')}</h1>
			<p>{m('segmentDetail.notFoundBody')}</p>
		</div>
	</div>
{:else}
	<div class="segment-detail">
		<a href="/dashboard" class="back-link">
			<span class="material-symbols">arrow_back</span>
			{m('segmentDetail.back')}
		</a>
		<header class="detail-header">
			<h1>{segment.name}</h1>
			{#if segment.region}
				<p class="region">
					<span class="material-symbols">place</span>
					{segment.region}
				</p>
			{/if}
			<div class="key-stats">
				<div class="key-stat">
					<span class="key-stat-value">{fmtDist(Number(segment.distance_m))}</span>
					<span class="key-stat-label">{m('segmentDetail.statDistance')}</span>
				</div>
				{#if segment.elevation_m != null && segment.elevation_m > 0}
					<div class="key-stat">
						<span class="key-stat-value">{segment.elevation_m} m</span>
						<span class="key-stat-label">{m('segmentDetail.statElevation')}</span>
					</div>
				{/if}
				<div class="key-stat key-stat-surface">
					<span class="key-stat-value">
						<span class="material-symbols">{surfaceIcon}</span>
						{segment.surface}
					</span>
					<span class="key-stat-label">{m('segmentDetail.statSurface')}</span>
				</div>
			</div>
			{#if segment.description}
				<p class="description">{segment.description}</p>
			{/if}
		</header>

		{#if mapTrack.length >= 2}
			<section class="section map-section">
				<div class="map-wrap">
					<RunMap track={mapTrack} />
				</div>
			</section>
		{/if}

		<section class="section">
			<h2>{m('segmentDetail.leaderboard')}</h2>
			<div class="tier-filters">
				<label>
					{m('segments.gender')}
					<select bind:value={genderFilter}>
						<option value={null}>{m('segments.all')}</option>
						<option value="male">{m('segments.men')}</option>
						<option value="female">{m('segments.women')}</option>
						<option value="nonbinary">{m('segments.nonbinary')}</option>
					</select>
				</label>
				<label>
					{m('segments.ageBand')}
					<select bind:value={ageFilter}>
						<option value={null}>{m('segments.allAges')}</option>
						{#each SEGMENT_AGE_BANDS as band}
							<option value={band}>{band}</option>
						{/each}
					</select>
				</label>
				{#if genderFilter || ageFilter}
					<button
						class="clear-btn"
						type="button"
						onclick={() => {
							genderFilter = null;
							ageFilter = null;
						}}
					>
						{m('segments.reset')}
					</button>
				{/if}
			</div>

			{#if board == null}
				<p class="muted small">{m('segments.loading')}</p>
			{:else if board.length === 0}
				<p class="muted small">
					{genderFilter || ageFilter
						? m('segments.noEffortsFiltered')
						: m('segmentDetail.noEfforts')}
				</p>
			{:else}
				{#if viewerHoldsCrown}
					<p class="crown-banner" title={crownLabel(genderFilter, ageFilter)}>
						<span class="material-symbols crown-icon">emoji_events</span>
						{m('segments.youHoldCrown', { label: crownLabel(genderFilter, ageFilter) })}
					</p>
				{/if}
				<ol>
					{#each board as entry (entry.effort.id)}
						<li class:viewer={entry.effort.user_id === auth.user?.id}>
							<span class="rank">
								{#if entry.rank === 1}
									<span
										class="material-symbols crown-icon"
										title={crownLabel(genderFilter, ageFilter)}
										aria-label={crownLabel(genderFilter, ageFilter)}
									>
										emoji_events
									</span>
								{:else}
									#{entry.rank}
								{/if}
							</span>
							<a href="/u/{entry.athlete.id}" class="athlete">
								<Avatar
									url={entry.athlete.avatar_url}
									name={entry.athlete.display_name}
									size="1.6rem"
									font="0.72rem"
								/>
								<span class="athlete-name">
									{entry.athlete.display_name ?? m('segments.runnerFallback')}
								</span>
							</a>
							<span class="time">{fmtTime(entry.effort.time_seconds)}</span>
						</li>
					{/each}
				</ol>
			{/if}
		</section>
	</div>
{/if}

<style>
	.segment-detail {
		max-width: 760px;
		margin: 0 auto;
		padding: var(--space-lg) var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		text-decoration: none;
	}
	.back-link:hover {
		color: var(--color-text-primary);
	}
	.loading {
		min-height: 40vh;
	}
	.not-found {
		text-align: center;
		padding: var(--space-xl) 0;
	}
	.detail-header h1 {
		margin: 0 0 0.3rem;
		font-size: 1.4rem;
	}
	.region {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.region .material-symbols {
		font-size: 1rem;
	}
	.key-stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
		gap: 1px;
		background: var(--color-border);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.key-stat {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
	}
	.key-stat-value {
		font-size: 1.05rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.key-stat-value .material-symbols {
		font-size: 1.1rem;
	}
	.key-stat-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.key-stat-surface .key-stat-value {
		text-transform: capitalize;
	}
	.description {
		margin: var(--space-md) 0 0;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.section h2 {
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
	}
	.map-wrap {
		height: 300px;
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.tier-filters {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.tier-filters label {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
	}
	.tier-filters select {
		padding: 0.3rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text-primary);
	}
	.clear-btn {
		background: none;
		border: none;
		color: var(--color-accent);
		cursor: pointer;
		font-size: 0.8rem;
		padding: 0.4rem 0;
	}
	.muted {
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.muted.small {
		font-size: 0.85rem;
	}
	.crown-banner {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.crown-icon {
		color: #facc15;
		font-size: 1.1rem;
	}
	ol {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	li {
		display: grid;
		grid-template-columns: 2.2rem 1fr auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	li.viewer {
		background: var(--color-surface-hover, rgba(99, 102, 241, 0.06));
		border-radius: var(--radius-sm);
	}
	.rank {
		font-variant-numeric: tabular-nums;
		text-align: center;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.athlete {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		text-decoration: none;
		color: var(--color-text-primary);
		min-width: 0;
	}
	.athlete-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.time {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
</style>
