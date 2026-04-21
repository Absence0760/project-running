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
	import { fetchRunById, deleteRun, makeRunPublic, updateRunMetadata } from '$lib/data';
	import { movingTimeSeconds, elevationGainMetres } from '$lib/run_stats';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import type { Run } from '$lib/types';

	let { data: pageData } = $props();

	let run = $state<Run | null>(null);
	let loading = $state(true);
	let editing = $state(false);
	let editTitle = $state('');
	let editNotes = $state('');
	let showDeleteConfirm = $state(false);

	onMount(async () => {
		run = await fetchRunById(pageData.id);
		loading = false;
	});

	let runTitle = $derived((run?.metadata as Record<string, unknown> | null)?.title as string ?? '');
	let runNotes = $derived((run?.metadata as Record<string, unknown> | null)?.notes as string ?? '');
	let estimatedCalories = $derived(run ? Math.round(70 * 1.0 * run.distance_m / 1000) : 0);

	function startEdit() {
		editTitle = runTitle;
		editNotes = runNotes;
		editing = true;
	}

	async function saveEdit() {
		if (!run) return;
		try {
			await updateRunMetadata(run.id, { title: editTitle, notes: editNotes });
			const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), title: editTitle, notes: editNotes };
			run = { ...run, metadata } as Run;
			editing = false;
		} catch (e) {
			showToast(`Save failed: ${e}`, 'error');
		}
	}

	function handleDelete() {
		if (!run) return;
		showDeleteConfirm = true;
	}

	async function confirmDelete() {
		if (!run) return;
		showDeleteConfirm = false;
		try {
			await deleteRun(run.id);
			goto('/runs');
		} catch (e) {
			showToast(`Delete failed: ${e}`, 'error');
		}
	}

	async function handleShare() {
		if (!run) return;
		try {
			await makeRunPublic(run.id);
			const url = `${window.location.origin}/share/run/${run.id}`;
			await navigator.clipboard.writeText(url);
			showToast('Share link copied to clipboard', 'success');
		} catch (e) {
			showToast(`Share failed: ${e}`, 'error');
		}
	}

	/**
	 * Mobile-recorded runs stamp the activity into `metadata.activity_type`.
	 * Map to a human label + Material Symbols icon.
	 */
	const activityMeta: Record<
		string,
		{ label: string; icon: string }
	> = {
		run: { label: 'Run', icon: 'directions_run' },
		walk: { label: 'Walk', icon: 'directions_walk' },
		cycle: { label: 'Cycle', icon: 'directions_bike' },
		hike: { label: 'Hike', icon: 'terrain' },
	};

	let activity = $derived.by(() => {
		const key = run?.metadata?.['activity_type'];
		if (typeof key !== 'string') return null;
		return activityMeta[key] ?? { label: key, icon: 'directions_run' };
	});

	/** Derived from the GPS track rather than stored, matching mobile. */
	let movingSeconds = $derived(run?.track ? movingTimeSeconds(run.track) : 0);

	/** Prefer a real track-based elevation gain over the randomly-generated
	 *  mock value. Falls back to 0 for runs without elevation data. */
	let realElevationGain = $derived(run?.track ? elevationGainMetres(run.track) : 0);

	/** Total steps are stored on mobile save in `metadata.steps`. */
	let totalSteps = $derived.by(() => {
		const v = run?.metadata?.['steps'];
		return typeof v === 'number' ? v : null;
	});

	/** Average cadence = steps / moving_time_minutes. Null when we don't
	 *  have enough data to compute meaningfully. */
	let avgCadence = $derived.by(() => {
		if (totalSteps == null || movingSeconds < 30) return null;
		return Math.round((totalSteps / (movingSeconds / 60)) || 0);
	});

	/** Average heart rate. Watch apps (watch_ios, watch_wear) record this
	 *  into `metadata.avg_bpm` during a run. See `docs/metadata.md`. */
	let avgBpm = $derived.by(() => {
		const v = run?.metadata?.['avg_bpm'];
		return typeof v === 'number' && v > 0 ? Math.round(v) : null;
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
				<h1>{runTitle || formatDate(run.started_at)}</h1>
				{#if runTitle}
					<div class="run-date-sub">{formatDate(run.started_at)}</div>
				{/if}
				{#if runNotes}
					<p class="run-notes">{runNotes}</p>
				{/if}
				<div class="detail-meta">
					<a href="/runs" class="back-link">
						<span class="material-symbols">arrow_back</span> All runs
					</a>
					{#if activity}
						<span class="activity-badge">
							<span class="material-symbols">{activity.icon}</span>
							{activity.label}
						</span>
					{/if}
				</div>
			</div>
			<div class="header-actions">
				<span class="source-badge" style="background: {sourceColor(run.source)}"
					>{sourceLabel(run.source)}</span>
				{#if auth.loggedIn}
					<div class="action-btns">
						<button class="icon-btn" title="Edit" onclick={startEdit}>
							<span class="material-symbols">edit</span>
						</button>
						<button class="icon-btn" title="Share link" onclick={handleShare}>
							<span class="material-symbols">share</span>
						</button>
						<button class="icon-btn danger" title="Delete" onclick={handleDelete}>
							<span class="material-symbols">delete</span>
						</button>
					</div>
				{/if}
			</div>
		</header>

		{#if editing}
			<div class="edit-form">
				<input type="text" bind:value={editTitle} placeholder="Run title" class="edit-input" />
				<textarea bind:value={editNotes} placeholder="Notes" class="edit-textarea" rows="2"></textarea>
				<div class="edit-actions">
					<button class="btn-sm btn-outline-sm" onclick={() => editing = false}>Cancel</button>
					<button class="btn-sm btn-primary-sm" onclick={saveEdit}>Save</button>
				</div>
			</div>
		{/if}

		<!-- Key stats -->
		<div class="key-stats">
			<div class="key-stat">
				<span class="key-stat-value">{formatDistance(run.distance_m)}</span>
				<span class="key-stat-label">Distance</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{formatDuration(run.duration_s)}</span>
				<span class="key-stat-label">Time</span>
			</div>
			{#if movingSeconds > 0 && movingSeconds !== run.duration_s}
				<div class="key-stat">
					<span class="key-stat-value">{formatDuration(movingSeconds)}</span>
					<span class="key-stat-label">Moving</span>
				</div>
			{/if}
			<div class="key-stat">
				<span class="key-stat-value"
					>{formatPace(
						movingSeconds > 0 ? movingSeconds : run.duration_s,
						run.distance_m
					)} /km</span
				>
				<span class="key-stat-label">Avg Pace</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{realElevationGain} m</span>
				<span class="key-stat-label">Elevation</span>
			</div>
			{#if estimatedCalories > 0}
				<div class="key-stat">
					<span class="key-stat-value">{estimatedCalories}</span>
					<span class="key-stat-label">Calories kcal</span>
				</div>
			{/if}
			{#if totalSteps != null}
				<div class="key-stat">
					<span class="key-stat-value">{totalSteps.toLocaleString()}</span>
					<span class="key-stat-label">Steps</span>
				</div>
			{/if}
			{#if avgCadence != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgCadence}</span>
					<span class="key-stat-label">Cadence spm</span>
				</div>
			{/if}
			{#if avgBpm != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgBpm}</span>
					<span class="key-stat-label">Avg HR bpm</span>
				</div>
			{/if}
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

<ConfirmDialog
	open={showDeleteConfirm}
	title="Delete run"
	message="Delete this run? This cannot be undone."
	confirmLabel="Delete"
	onconfirm={confirmDelete}
	oncancel={() => showDeleteConfirm = false}
	danger
/>
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

	.detail-meta {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin-top: var(--space-xs);
		flex-wrap: wrap;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.activity-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.2rem 0.6rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		font-weight: 600;
	}

	.activity-badge .material-symbols {
		font-size: 0.95rem;
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

	.run-date-sub {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.run-notes {
		margin-top: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
	}

	.header-actions {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-sm);
	}

	.action-btns {
		display: flex;
		gap: var(--space-xs);
	}

	.icon-btn {
		background: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: var(--space-xs);
		cursor: pointer;
		color: var(--color-text-secondary);
		display: flex;
		align-items: center;
	}

	.icon-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.icon-btn.danger:hover {
		border-color: var(--color-danger, #ef4444);
		color: var(--color-danger, #ef4444);
	}

	.edit-form {
		margin-bottom: var(--space-lg);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.edit-input, .edit-textarea {
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		font-size: 0.85rem;
		background: var(--color-surface);
		color: var(--color-text);
	}

	.edit-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
	}

	.btn-sm {
		padding: var(--space-xs) var(--space-md);
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
	}

	.btn-outline-sm {
		background: none;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
	}

	.btn-primary-sm {
		background: var(--color-primary);
		border: none;
		color: white;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}
</style>
