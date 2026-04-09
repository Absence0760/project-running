<script lang="ts">
	import { onMount } from 'svelte';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import {
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import { fetchRunById } from '$lib/data';
	import type { Run } from '$lib/types';

	let { data } = $props();

	let run = $state<Run | null>(null);
	let loading = $state(true);

	onMount(async () => {
		run = await fetchRunById(data.id);
		loading = false;
	});

	const hrZones = [
		{ zone: 'Zone 1', label: 'Recovery', pct: 8, color: '#90CAF9' },
		{ zone: 'Zone 2', label: 'Easy', pct: 32, color: '#4CAF50' },
		{ zone: 'Zone 3', label: 'Aerobic', pct: 35, color: '#FFC107' },
		{ zone: 'Zone 4', label: 'Threshold', pct: 20, color: '#FF9800' },
		{ zone: 'Zone 5', label: 'Max', pct: 5, color: '#F44336' },
	];

	let baseTrack = $derived(run ? (run.track ?? generateMockTrack(run.distance_m)) : []);
	let elevations = $derived(baseTrack.map((p) => p.ele ?? 20 + Math.random() * 30));

	let splits = $derived.by(() => {
		if (!run) return [];
		const distanceKm = run.distance_m / 1000;
		const numSplits = Math.ceil(distanceKm);
		const avgPaceSec = run.duration_s / distanceKm;
		return Array.from({ length: numSplits }, (_, i) => {
			const variance = (Math.random() - 0.5) * 20;
			const splitPace = avgPaceSec + variance;
			const splitDistance = i < numSplits - 1 ? 1000 : (distanceKm - Math.floor(distanceKm)) * 1000 || 1000;
			const elevation = Math.round((Math.random() - 0.3) * 15);
			return { km: i + 1, pace_s: Math.round(splitPace), distance_m: splitDistance, elevation_m: elevation };
		});
	});

	function generateMockTrack(distanceM: number) {
		const points = Math.max(50, Math.round(distanceM / 20));
		const baseLat = -37.8136;
		const baseLng = 144.9631;
		const track = [];
		for (let i = 0; i < points; i++) {
			const angle = (i / points) * Math.PI * 2;
			const radius = (distanceM / 1000) * 0.004;
			track.push({
				lat: baseLat + Math.sin(angle) * radius + (Math.random() - 0.5) * 0.0005,
				lng: baseLng + Math.cos(angle) * radius + (Math.random() - 0.5) * 0.0005,
				ele: 20 + Math.sin(angle * 3) * 15 + Math.random() * 5,
			});
		}
		track.push(track[0]);
		return track;
	}
</script>

{#if loading}
	<div class="run-detail"><p class="loading-text">&nbsp;</p></div>
{:else if run}
<div class="run-detail">
	<main class="map-panel">
		<RunMap track={baseTrack} animatable />
	</main>

	<aside class="stats-panel">
		<header class="detail-header">
			<div>
				<h1>{formatDate(run.started_at)}</h1>
				<a href="/runs" class="back-link">
					<span class="material-symbols">arrow_back</span> All runs
				</a>
			</div>
			<span class="source-badge" style="background: {sourceColor(run.source)}"
				>{sourceLabel(run.source)}</span
			>
		</header>

		<!-- Key stats -->
		<div class="key-stats">
			<div class="key-stat">
				<span class="key-stat-value">{formatDistance(run.distance_m)}</span>
				<span class="key-stat-label">Distance</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{formatDuration(run.duration_s)}</span>
				<span class="key-stat-label">Duration</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{formatPace(run.duration_s, run.distance_m)} /km</span>
				<span class="key-stat-label">Avg Pace</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">152 bpm</span>
				<span class="key-stat-label">Avg HR</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">42 m</span>
				<span class="key-stat-label">Elevation</span>
			</div>
		</div>

		<!-- Elevation Profile -->
		<section class="section">
			<h2>Elevation Profile</h2>
			<ElevationProfile {elevations} totalDistance={run.distance_m} />
		</section>

		<!-- Splits -->
		<section class="section">
			<h2>Splits</h2>
			<table class="splits-table">
				<thead>
					<tr>
						<th>Km</th>
						<th>Pace</th>
						<th>Elev</th>
					</tr>
				</thead>
				<tbody>
					{#each splits as split}
						<tr>
							<td>{split.km}</td>
							<td class="split-pace">
								{Math.floor(split.pace_s / 60)}:{String(split.pace_s % 60).padStart(2, '0')}
							</td>
							<td class="split-elev" class:positive={split.elevation_m > 0} class:negative={split.elevation_m < 0}>
								{split.elevation_m > 0 ? '+' : ''}{split.elevation_m} m
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</section>

		<!-- HR zones -->
		<section class="section">
			<h2>Heart Rate Zones</h2>
			<div class="hr-bar">
				{#each hrZones as zone}
					<div
						class="hr-segment"
						style="width: {zone.pct}%; background: {zone.color}"
						title="{zone.zone}: {zone.pct}%"
					></div>
				{/each}
			</div>
			<div class="hr-legend">
				{#each hrZones as zone}
					<div class="hr-legend-item">
						<span class="hr-dot" style="background: {zone.color}"></span>
						<span class="hr-zone-name">{zone.label}</span>
						<span class="hr-zone-pct">{zone.pct}%</span>
					</div>
				{/each}
			</div>
		</section>
	</aside>
</div>
{/if}

<style>
	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.run-detail {
		display: flex;
		height: 100vh;
	}

	.map-panel {
		flex: 3;
		background: var(--color-bg-tertiary);
	}

	.stats-panel {
		flex: 2;
		border-left: 1px solid var(--color-border);
		padding: var(--space-xl);
		overflow-y: auto;
		background: var(--color-surface);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		margin-top: var(--space-xs);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
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

	.key-stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
		padding-bottom: var(--space-xl);
		border-bottom: 1px solid var(--color-border);
	}

	.key-stat {
		display: flex;
		flex-direction: column;
	}

	.key-stat-value {
		font-size: 1.1rem;
		font-weight: 700;
	}

	.key-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.section {
		margin-bottom: var(--space-xl);
	}

	.splits-table {
		width: 100%;
		border-collapse: collapse;
	}

	.splits-table th {
		text-align: left;
		font-size: 0.7rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}

	.splits-table td {
		padding: var(--space-sm) 0;
		font-size: 0.85rem;
		border-bottom: 1px solid var(--color-bg-secondary);
	}

	.split-pace {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-weight: 600;
	}

	.split-elev {
		font-size: 0.8rem;
	}

	.split-elev.positive {
		color: var(--color-danger);
	}

	.split-elev.negative {
		color: var(--color-secondary);
	}

	.hr-bar {
		display: flex;
		height: 1.5rem;
		border-radius: var(--radius-sm);
		overflow: hidden;
		margin-bottom: var(--space-md);
	}

	.hr-segment {
		transition: width var(--transition-base);
	}

	.hr-legend {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}

	.hr-legend-item {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.8rem;
	}

	.hr-dot {
		width: 0.6rem;
		height: 0.6rem;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.hr-zone-name {
		flex: 1;
		color: var(--color-text-secondary);
	}

	.hr-zone-pct {
		font-weight: 600;
		font-family: 'SF Mono', 'Menlo', monospace;
		font-size: 0.75rem;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}
</style>
