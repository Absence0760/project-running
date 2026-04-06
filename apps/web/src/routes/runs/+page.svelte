<script lang="ts">
	import {
		mockRuns,
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import type { RunSource } from '$lib/types';

	let sourceFilter = $state<RunSource | 'all'>('all');

	let filteredRuns = $derived(
		sourceFilter === 'all' ? mockRuns : mockRuns.filter((r) => r.source === sourceFilter),
	);

	const sources: { value: RunSource | 'all'; label: string }[] = [
		{ value: 'all', label: 'All Sources' },
		{ value: 'app', label: 'Recorded' },
		{ value: 'strava', label: 'Strava' },
		{ value: 'parkrun', label: 'parkrun' },
		{ value: 'healthkit', label: 'HealthKit' },
	];
</script>

<div class="page">
	<header class="page-header">
		<h1>Run History</h1>
		<div class="filters">
			{#each sources as src}
				<button
					class="filter-btn"
					class:active={sourceFilter === src.value}
					onclick={() => (sourceFilter = src.value)}
				>
					{src.label}
				</button>
			{/each}
		</div>
	</header>

	<div class="run-list">
		{#each filteredRuns as run}
			<a href="/runs/{run.id}" class="run-card">
				<div class="run-map-placeholder">
					<span class="material-symbols">map</span>
				</div>
				<div class="run-details">
					<div class="run-top">
						<span class="run-date">{formatDate(run.started_at)}</span>
						<span class="source-badge" style="background: {sourceColor(run.source)}"
							>{sourceLabel(run.source)}</span
						>
					</div>
					<div class="run-stats">
						<div class="run-stat">
							<span class="run-stat-value">{formatDistance(run.distance_m)}</span>
							<span class="run-stat-label">Distance</span>
						</div>
						<div class="run-stat">
							<span class="run-stat-value">{formatDuration(run.duration_s)}</span>
							<span class="run-stat-label">Time</span>
						</div>
						<div class="run-stat">
							<span class="run-stat-value"
								>{formatPace(run.duration_s, run.distance_m)} /km</span
							>
							<span class="run-stat-label">Pace</span>
						</div>
					</div>
					{#if run.metadata?.event}
						<div class="run-event">
							{run.metadata.event}
							{#if run.metadata.position} &middot; Position {run.metadata.position}{/if}
						</div>
					{/if}
				</div>
			</a>
		{/each}
	</div>

	{#if filteredRuns.length === 0}
		<div class="empty">No runs found for this filter.</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 56rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-md);
	}

	.filters {
		display: flex;
		gap: var(--space-xs);
	}

	.filter-btn {
		padding: var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
	}

	.filter-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.filter-btn.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}

	.run-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.run-card {
		display: flex;
		gap: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		transition: all var(--transition-fast);
	}

	.run-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.run-map-placeholder {
		width: 5rem;
		height: 5rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.run-map-placeholder .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
	}

	.run-details {
		flex: 1;
		min-width: 0;
	}

	.run-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-sm);
	}

	.run-date {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}

	.run-stats {
		display: flex;
		gap: var(--space-xl);
	}

	.run-stat {
		display: flex;
		flex-direction: column;
	}

	.run-stat-value {
		font-weight: 700;
		font-size: 1.05rem;
	}

	.run-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.run-event {
		margin-top: var(--space-sm);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.empty {
		text-align: center;
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
