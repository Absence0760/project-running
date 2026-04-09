<script lang="ts">
	import { onMount } from 'svelte';
	import CalendarHeatmap from '$lib/components/CalendarHeatmap.svelte';
	import {
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		formatDateShort,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import { fetchRuns, fetchWeeklyMileage, fetchPersonalRecords } from '$lib/data';
	import type { Run } from '$lib/types';

	let runs = $state<Run[]>([]);
	let weeklyMileage = $state<{ week: string; distance_km: number }[]>([]);
	let personalRecords = $state<{ distance: string; time_s: number; date: string }[]>([]);
	let loading = $state(true);

	onMount(async () => {
		[runs, weeklyMileage, personalRecords] = await Promise.all([
			fetchRuns(),
			fetchWeeklyMileage(),
			fetchPersonalRecords(),
		]);
		loading = false;
	});

	const now = new Date();
	const weekStart = new Date(now);
	weekStart.setDate(now.getDate() - now.getDay());
	weekStart.setHours(0, 0, 0, 0);

	let thisWeekRuns = $derived(runs.filter((r) => new Date(r.started_at) >= weekStart));
	let thisWeekDistance = $derived(thisWeekRuns.reduce((sum, r) => sum + r.distance_m, 0));
	let totalRuns = $derived(runs.length);
	let longestRun = $derived(runs.length > 0 ? Math.max(...runs.map((r) => r.distance_m)) : 0);
	let maxWeeklyBar = $derived(
		weeklyMileage.length > 0 ? Math.max(...weeklyMileage.map((w) => w.distance_km)) : 1
	);
</script>

<div class="page">
	<header class="page-header">
		<h1>Dashboard</h1>
	</header>

	{#if loading}
		<p class="loading-text">Loading dashboard...</p>
	{:else}
		<!-- Stat cards -->
		<div class="stat-grid">
			<div class="stat-card">
				<span class="stat-label">This Week</span>
				<span class="stat-value">{formatDistance(thisWeekDistance)}</span>
				<span class="stat-sub">{thisWeekRuns.length} run{thisWeekRuns.length !== 1 ? 's' : ''}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Total Runs</span>
				<span class="stat-value">{totalRuns}</span>
				<span class="stat-sub">all sources</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Longest Run</span>
				<span class="stat-value">{formatDistance(longestRun)}</span>
				<span class="stat-sub">all time</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">This Week Pace</span>
				<span class="stat-value">
					{thisWeekRuns.length > 0
						? formatPace(
								thisWeekRuns.reduce((s, r) => s + r.duration_s, 0),
								thisWeekDistance,
							) + ' /km'
						: '--'}
				</span>
				<span class="stat-sub">average</span>
			</div>
		</div>

		<!-- Weekly mileage chart -->
		<section class="card">
			<h2>Weekly Mileage</h2>
			<div class="chart">
				{#each weeklyMileage as week}
					<div class="bar-col">
						<div class="bar-tooltip">{week.distance_km.toFixed(1)} km</div>
						<div
							class="bar"
							style="height: {(week.distance_km / maxWeeklyBar) * 100}%"
						></div>
						<span class="bar-label">{week.week.split(' ')[0]}</span>
					</div>
				{/each}
			</div>
		</section>

		<!-- Calendar heatmap -->
		<section class="card">
			<h2>Activity</h2>
			<CalendarHeatmap {runs} />
		</section>

		<div class="two-col">
			<!-- Personal records -->
			<section class="card">
				<h2>Personal Records</h2>
				{#if personalRecords.length > 0}
					<table class="pr-table">
						<thead>
							<tr>
								<th>Distance</th>
								<th>Time</th>
								<th>Date</th>
							</tr>
						</thead>
						<tbody>
							{#each personalRecords as pr}
								<tr>
									<td class="pr-distance">{pr.distance}</td>
									<td class="pr-time">{formatDuration(pr.time_s)}</td>
									<td class="pr-date">{formatDate(pr.date)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{:else}
					<p class="empty-text">Complete qualifying runs to see PRs</p>
				{/if}
			</section>

			<!-- Recent runs -->
			<section class="card">
				<h2>Recent Runs</h2>
				<div class="run-list">
					{#each runs.slice(0, 7) as run}
						<a href="/runs/{run.id}" class="run-row">
							<div class="run-info">
								<span class="run-date">{formatDateShort(run.started_at)}</span>
								<span class="run-distance">{formatDistance(run.distance_m)}</span>
							</div>
							<div class="run-meta">
								<span class="run-pace">{formatPace(run.duration_s, run.distance_m)} /km</span>
								<span class="source-badge" style="background: {sourceColor(run.source)}">{sourceLabel(run.source)}</span>
							</div>
						</a>
					{/each}
				</div>
			</section>
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}

	h2 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-lg);
		color: var(--color-text);
	}

	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.empty-text {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}

	.stat-grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}

	.stat-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
	}

	.stat-label {
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		margin-bottom: var(--space-xs);
	}

	.stat-value {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-text);
	}

	.stat-sub {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.chart {
		display: flex;
		align-items: flex-end;
		gap: var(--space-sm);
		height: 12rem;
		padding-top: var(--space-md);
	}

	.bar-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		height: 100%;
		justify-content: flex-end;
		position: relative;
	}

	.bar-col:hover .bar-tooltip {
		opacity: 1;
	}

	.bar-tooltip {
		position: absolute;
		top: -1.5rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		opacity: 0;
		transition: opacity var(--transition-fast);
		white-space: nowrap;
	}

	.bar {
		width: 100%;
		max-width: 2.5rem;
		background: var(--color-primary);
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		min-height: 4px;
		transition: height var(--transition-base);
	}

	.bar-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}

	.two-col {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-xl);
	}

	.pr-table {
		width: 100%;
		border-collapse: collapse;
	}

	.pr-table th {
		text-align: left;
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}

	.pr-table td {
		padding: var(--space-md) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
	}

	.pr-distance {
		font-weight: 600;
	}

	.pr-time {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-weight: 600;
		color: var(--color-primary);
	}

	.pr-date {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
	}

	.run-list {
		display: flex;
		flex-direction: column;
	}

	.run-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
		transition: background var(--transition-fast);
	}

	.run-row:last-child {
		border-bottom: none;
	}

	.run-row:hover {
		background: var(--color-bg-secondary);
		margin: 0 calc(-1 * var(--space-sm));
		padding: var(--space-sm);
		border-radius: var(--radius-sm);
	}

	.run-info {
		display: flex;
		gap: var(--space-md);
		align-items: baseline;
	}

	.run-date {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		min-width: 4rem;
	}

	.run-distance {
		font-weight: 600;
		font-size: 0.9rem;
	}

	.run-meta {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.run-pace {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		font-family: 'SF Mono', 'Menlo', monospace;
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

	@media (max-width: 768px) {
		.stat-grid { grid-template-columns: repeat(2, 1fr); }
		.two-col { grid-template-columns: 1fr; }
	}
</style>
