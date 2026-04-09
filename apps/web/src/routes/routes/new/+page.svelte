<script lang="ts">
	import { goto } from '$app/navigation';
	import RouteBuilder from '$lib/components/RouteBuilder.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import { toGpx, toKml, downloadFile } from '$lib/gpx';
	import { saveRoute } from '$lib/data';

	let routeName = $state('');
	let mode = $state<'road' | 'trail'>('road');
	let waypointCount = $state(0);
	let distance = $state(0);
	let elevation = $state(0);
	let elevations = $state<number[]>([]);
	let coordinates = $state<[number, number][]>([]);
	let builder: RouteBuilder;
	let saving = $state(false);
	let saveError = $state('');

	function handleUpdate(data: {
		waypoints: number;
		distance: number;
		elevation: number;
		elevations: number[];
		coordinates: [number, number][];
	}) {
		waypointCount = data.waypoints;
		distance = data.distance;
		elevation = data.elevation;
		elevations = data.elevations;
		coordinates = data.coordinates;
	}

	// Lap detection: count how many times the route returns to the start point
	let laps = $derived.by(() => {
		const routeData = builder?.getRouteData();
		if (!routeData || routeData.waypoints.length < 3) return { count: 0, lapDistance: 0 };

		const start = routeData.waypoints[0];
		let lapCount = 0;

		for (let i = 1; i < routeData.waypoints.length; i++) {
			const wp = routeData.waypoints[i];
			const dist = Math.sqrt((wp.lat - start.lat) ** 2 + (wp.lng - start.lng) ** 2);
			// Within ~10m of start = a lap completion
			if (dist < 0.0001) {
				lapCount++;
			}
		}

		return {
			count: lapCount,
			lapDistance: lapCount > 0 ? distance / lapCount : 0
		};
	});

	function handleUndo() {
		builder?.undoWaypoint();
		routed = false;
	}

	function handleClear() {
		builder?.clearWaypoints();
		routed = false;
	}

	function handleExportGpx() {
		const name = routeName || 'Untitled Route';
		const gpx = toGpx(name, coordinates, elevations);
		const filename = name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.gpx';
		downloadFile(gpx, filename, 'application/gpx+xml');
	}

	function handleExportKml() {
		const name = routeName || 'Untitled Route';
		const kml = toKml(name, coordinates, elevations);
		const filename = name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.kml';
		downloadFile(kml, filename, 'application/vnd.google-earth.kml+xml');
	}

	let routed = $state(false);

	async function handleCalculateRoute() {
		await builder?.calculateRoute();
		routed = true;
	}

	async function handleSaveRoute() {
		saving = true;
		saveError = '';
		try {
			const routeData = builder?.getRouteData();
			if (!routeData) return;

			const saved = await saveRoute({
				name: routeName || 'Untitled Route',
				waypoints: routeData.waypoints,
				distance_m: Math.round(distance * 100) / 100,
				elevation_m: elevation > 0 ? elevation : null,
				surface: mode === 'trail' ? 'trail' : 'road',
				is_public: false,
			});

			goto(`/routes/${saved.id}`);
		} catch (err) {
			saveError = err instanceof Error ? err.message : 'Failed to save route';
		} finally {
			saving = false;
		}
	}
</script>

<div class="builder-layout">
	<aside class="sidebar">
		<a href="/routes" class="back-link">
			<span class="material-symbols">arrow_back</span>
			Routes
		</a>

		<h1>Route Builder</h1>

		<div class="controls">
			<label>
				<span class="label-text">Route Name</span>
				<input type="text" placeholder="My Route" bind:value={routeName} />
			</label>

			<fieldset>
				<legend class="label-text">Mode</legend>
				<div class="mode-buttons">
					<button
						class="mode-btn"
						class:active={mode === 'road'}
						onclick={() => (mode = 'road')}
					>
						<span class="material-symbols">directions_car</span>
						Road
					</button>
					<button
						class="mode-btn"
						class:active={mode === 'trail'}
						onclick={() => (mode = 'trail')}
					>
						<span class="material-symbols">forest</span>
						Trail
					</button>
				</div>
			</fieldset>

			<div class="stats-row">
				<div class="builder-stat">
					<span class="builder-stat-value">{(distance / 1000).toFixed(2)} km</span>
					<span class="builder-stat-label">Distance</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{elevation} m</span>
					<span class="builder-stat-label">Elevation</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{waypointCount}</span>
					<span class="builder-stat-label">Points</span>
				</div>
			</div>

			{#if laps.count > 0}
				<div class="lap-info">
					<div class="lap-badge">
						<span class="material-symbols">loop</span>
						{laps.count} {laps.count === 1 ? 'lap' : 'laps'}
					</div>
					<span class="lap-detail">{(laps.lapDistance / 1000).toFixed(2)} km per lap</span>
				</div>
			{/if}

			<div class="elevation-preview">
				<span class="label-text">Elevation Profile</span>
				{#if elevations.length >= 2}
					<ElevationProfile {elevations} totalDistance={distance} />
				{:else}
					<div class="elevation-empty">
						<span class="material-symbols">show_chart</span>
						<span>Add waypoints to see profile</span>
					</div>
				{/if}
			</div>

			<div class="action-row">
				<button class="btn btn-ghost" disabled={waypointCount === 0} onclick={handleUndo}>
					<span class="material-symbols">undo</span>
					Undo
				</button>
				<button class="btn btn-ghost" disabled={waypointCount === 0} onclick={handleClear}>
					<span class="material-symbols">delete</span>
					Clear
				</button>
			</div>

			{#if saveError}
				<div class="save-error">{saveError}</div>
			{/if}

			<div class="action-row">
				<button
					class="btn btn-accent"
					disabled={waypointCount < 2}
					onclick={handleCalculateRoute}
				>
					{routed ? 'Recalculate' : 'Calculate Route'}
				</button>
			</div>

			<div class="action-row">
				<button
					class="btn btn-primary"
					disabled={!routed || saving}
					onclick={handleSaveRoute}
				>
					{saving ? 'Saving...' : 'Save Route'}
				</button>
				<button
					class="btn btn-outline"
					disabled={!routed}
					onclick={handleExportGpx}
				>
					GPX
				</button>
				<button
					class="btn btn-outline"
					disabled={!routed}
					onclick={handleExportKml}
				>
					KML
				</button>
			</div>
		</div>

		<div class="sidebar-hint">
			<span class="material-symbols">info</span>
			{#if waypointCount === 0}
				Click on the map to place waypoints along your route.
			{:else if !routed}
				Keep adding waypoints, then hit Calculate Route to snap to {mode === 'road' ? 'roads' : 'walking paths'}.
			{:else}
				Route calculated. Save, export, or add more waypoints.
			{/if}
		</div>
	</aside>

	<main class="map-area">
		<RouteBuilder bind:this={builder} {mode} onupdate={handleUpdate} />
	</main>
</div>

<style>
	.builder-layout {
		display: flex;
		height: 100vh;
	}

	.sidebar {
		width: 22rem;
		border-right: 1px solid var(--color-border);
		padding: var(--space-lg);
		overflow-y: auto;
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
		margin-bottom: var(--space-lg);
	}

	.controls {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		flex: 1;
	}

	.label-text {
		display: block;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xs);
	}

	input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		transition: border-color var(--transition-fast);
		background: var(--color-bg);
	}

	input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	fieldset {
		border: none;
		padding: 0;
	}

	legend {
		margin-bottom: var(--space-sm);
	}

	.mode-buttons {
		display: flex;
		gap: var(--space-sm);
	}

	.mode-btn {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
	}

	.mode-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.mode-btn.active {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.stats-row {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-sm);
	}

	.builder-stat {
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		text-align: center;
	}

	.builder-stat-value {
		display: block;
		font-size: 1rem;
		font-weight: 700;
	}

	.builder-stat-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.elevation-preview {
		margin-top: var(--space-sm);
	}

	.elevation-empty {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	.lap-info {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-sm) var(--space-md);
		background: rgba(139, 92, 246, 0.1);
		border: 1px solid rgba(139, 92, 246, 0.25);
		border-radius: var(--radius-md);
	}

	.lap-badge {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-weight: 700;
		font-size: 0.85rem;
		color: #7c3aed;
	}

	.lap-detail {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.action-row {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		flex: 1;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
	}

	.btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.btn-accent {
		background: var(--color-secondary, #43A047);
		color: white;
		border: none;
		width: 100%;
	}

	.btn-accent:hover:not(:disabled) {
		background: var(--color-secondary-hover, #388E3C);
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover:not(:disabled) {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-ghost {
		background: transparent;
		border: none;
		color: var(--color-text-secondary);
	}

	.btn-ghost:hover:not(:disabled) {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}

	.save-error {
		padding: var(--space-sm) var(--space-md);
		background: var(--color-danger-light, #fef2f2);
		border: 1px solid rgba(229, 57, 53, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-danger, #e53935);
		font-size: 0.8rem;
	}

	.sidebar-hint {
		display: flex;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-primary-light);
		border-radius: var(--radius-md);
		font-size: 0.8rem;
		color: var(--color-primary);
		margin-top: var(--space-lg);
		line-height: 1.4;
	}

	.sidebar-hint .material-symbols {
		flex-shrink: 0;
	}

	.map-area {
		flex: 1;
		background: var(--color-bg-tertiary);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
</style>
