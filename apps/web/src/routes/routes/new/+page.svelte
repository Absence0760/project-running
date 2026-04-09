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
	let currentMapStyle = $state<'streets' | 'satellite' | 'terrain'>('streets');
	let paceMin = $state(5);
	let paceSec = $state(30);
	let targetKm = $state(5);
	let showDistanceTarget = $state(false);
	let pickingPoint = $state<'start' | 'end' | null>(null);
	let startPoint = $state<{ lat: number; lng: number } | null>(null);
	let endPoint = $state<{ lat: number; lng: number } | null>(null);
	let startLabel = $state('');
	let endLabel = $state('');

	let estimatedTime = $derived.by(() => {
		if (distance === 0) return '';
		const paceSecondsPerKm = paceMin * 60 + paceSec;
		const totalSeconds = Math.round((distance / 1000) * paceSecondsPerKm);
		const h = Math.floor(totalSeconds / 3600);
		const m = Math.floor((totalSeconds % 3600) / 60);
		const s = totalSeconds % 60;
		if (h > 0) return `~${h}h ${m}m`;
		return `~${m}m ${s}s`;
	});

	async function handleCalculateRoute() {
		await builder?.calculateRoute();
		routed = true;
	}

	function handleUndoCalculate() {
		builder?.undoCalculate();
		routed = false;
	}

	function handleOutAndBack() {
		builder?.outAndBack();
		routed = false;
	}

	function handleMapStyle(style: 'streets' | 'satellite' | 'terrain') {
		currentMapStyle = style;
		builder?.setMapStyle(style);
	}

	function useMyLocation(target: 'start' | 'end') {
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				const point = { lat: pos.coords.latitude, lng: pos.coords.longitude };
				const label = 'My location';
				if (target === 'start') { startPoint = point; startLabel = label; }
				else { endPoint = point; endLabel = label; }
			},
			() => {},
			{ timeout: 5000 }
		);
	}

	function pickOnMap(target: 'start' | 'end') {
		pickingPoint = target;
	}

	// Called from RouteBuilder when user clicks while picking
	function handleMapPick(lngLat: { lng: number; lat: number }) {
		if (!pickingPoint) return false;
		const point = { lat: lngLat.lat, lng: lngLat.lng };
		const label = `${point.lat.toFixed(4)}, ${point.lng.toFixed(4)}`;
		if (pickingPoint === 'start') { startPoint = point; startLabel = label; }
		else { endPoint = point; endLabel = label; }
		pickingPoint = null;
		return true; // consumed the click
	}

	async function handleGenerateLoop() {
		// Default start to map center if not set
		const start = startPoint ?? (() => {
			const c = builder?.getMapCenter?.();
			return c ? { lat: c.lat, lng: c.lng } : undefined;
		})();

		// End defaults to start (loop) if not set
		const end = endPoint ?? undefined;

		await builder?.generateLoop(targetKm * 1000, start, end);
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

			<!-- Map style toggle -->
			<div class="style-toggle">
				<button class="style-btn" class:active={currentMapStyle === 'streets'} onclick={() => handleMapStyle('streets')}>Streets</button>
				<button class="style-btn" class:active={currentMapStyle === 'satellite'} onclick={() => handleMapStyle('satellite')}>Satellite</button>
				<button class="style-btn" class:active={currentMapStyle === 'terrain'} onclick={() => handleMapStyle('terrain')}>Terrain</button>
			</div>

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

			<!-- Time estimate -->
			{#if distance > 0}
				<div class="time-estimate">
					<span class="time-value">{estimatedTime}</span>
					<div class="pace-input">
						<span class="pace-label">at</span>
						<input type="number" min="2" max="15" bind:value={paceMin} class="pace-num" />
						<span>:</span>
						<input type="number" min="0" max="59" bind:value={paceSec} class="pace-num" />
						<span class="pace-label">/km</span>
					</div>
				</div>
			{/if}

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
				<button class="btn btn-ghost" disabled={waypointCount < 2} onclick={handleOutAndBack}>
					<span class="material-symbols">swap_horiz</span>
					Out & Back
				</button>
				<button class="btn btn-ghost" disabled={waypointCount === 0} onclick={handleClear}>
					<span class="material-symbols">delete</span>
					Clear
				</button>
			</div>

			<!-- Distance target -->
			<button
				class="target-btn"
				class:active={showDistanceTarget}
				onclick={() => (showDistanceTarget = !showDistanceTarget)}
			>
				<span class="material-symbols">route</span>
				<span class="target-btn-text">
					{showDistanceTarget ? 'Hide Distance Target' : 'Generate a route by distance'}
				</span>
				<span class="target-btn-sub">Set a target like 5k, 10k, or marathon</span>
			</button>
			{#if showDistanceTarget}
				<div class="target-panel">
					<span class="label-text">Start</span>
					<div class="point-row">
						{#if startPoint}
							<span class="point-set">{startLabel}</span>
						{:else}
							<span class="point-unset">Not set (uses map center)</span>
						{/if}
						<button class="btn-sm" onclick={() => useMyLocation('start')}>
							<span class="material-symbols">my_location</span>
						</button>
						<button class="btn-sm" class:active={pickingPoint === 'start'} onclick={() => pickOnMap('start')}>
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if startPoint}
							<button class="btn-sm" onclick={() => { startPoint = null; startLabel = ''; }}>
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>

					<span class="label-text">End <span class="label-hint">(optional — defaults to start for loop)</span></span>
					<div class="point-row">
						{#if endPoint}
							<span class="point-set">{endLabel}</span>
						{:else}
							<span class="point-unset">Same as start (loop)</span>
						{/if}
						<button class="btn-sm" onclick={() => useMyLocation('end')}>
							<span class="material-symbols">my_location</span>
						</button>
						<button class="btn-sm" class:active={pickingPoint === 'end'} onclick={() => pickOnMap('end')}>
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if endPoint}
							<button class="btn-sm" onclick={() => { endPoint = null; endLabel = ''; }}>
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>

					<span class="label-text">Distance</span>
					<div class="target-row">
						<input type="range" min="1" max="42" step="0.5" bind:value={targetKm} class="target-slider" />
						<span class="target-value">{targetKm} km</span>
					</div>
					<div class="target-presets">
						<button onclick={() => (targetKm = 5)}>5k</button>
						<button onclick={() => (targetKm = 10)}>10k</button>
						<button onclick={() => (targetKm = 21.1)}>Half</button>
						<button onclick={() => (targetKm = 42.2)}>Full</button>
					</div>
					<button class="btn btn-accent" onclick={handleGenerateLoop}>
						Generate {targetKm} km {endPoint ? 'Route' : 'Loop'}
					</button>
				</div>
			{/if}

			{#if pickingPoint}
				<div class="pick-hint">
					Click on the map to set {pickingPoint} point
				</div>
			{/if}

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
				{#if routed}
					<button class="btn btn-ghost" onclick={handleUndoCalculate}>
						<span class="material-symbols">undo</span>
					</button>
				{/if}
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
		<RouteBuilder bind:this={builder} {mode} onupdate={handleUpdate} onmapclick={handleMapPick} />
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

	/* Map style toggle */
	.style-toggle {
		display: flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}

	.style-btn {
		flex: 1;
		padding: var(--space-xs) var(--space-sm);
		border: none;
		background: var(--color-surface);
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.style-btn:not(:last-child) {
		border-right: 1px solid var(--color-border);
	}

	.style-btn.active {
		background: var(--color-primary);
		color: white;
	}

	/* Time estimate */
	.time-estimate {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.time-value {
		font-weight: 700;
		font-size: 1rem;
	}

	.pace-input {
		display: flex;
		align-items: center;
		gap: 2px;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.pace-num {
		width: 2.2rem;
		padding: 2px 4px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		text-align: center;
		background: var(--color-surface);
	}

	.pace-label {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}

	/* Distance target panel */
	.target-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.point-row {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin-bottom: var(--space-sm);
	}

	.point-set {
		flex: 1;
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.point-unset {
		flex: 1;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		font-style: italic;
	}

	.btn-sm {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		cursor: pointer;
		color: var(--color-text-secondary);
		flex-shrink: 0;
		transition: all var(--transition-fast);
	}

	.btn-sm:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-sm.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}

	.btn-sm .material-symbols {
		font-size: 0.85rem;
	}

	.label-hint {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.7rem;
	}

	.pick-hint {
		padding: var(--space-sm) var(--space-md);
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-size: 0.8rem;
		font-weight: 500;
		text-align: center;
		animation: pulse-bg 1.5s ease-in-out infinite;
	}

	@keyframes pulse-bg {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.7; }
	}

	.target-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.target-slider {
		flex: 1;
		accent-color: var(--color-primary);
	}

	.target-value {
		font-weight: 700;
		font-size: 0.9rem;
		min-width: 4rem;
		text-align: right;
	}

	.target-presets {
		display: flex;
		gap: var(--space-xs);
	}

	.target-presets button {
		flex: 1;
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.75rem;
		font-weight: 600;
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.target-presets button:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.target-btn {
		width: 100%;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-md);
		border: 2px dashed var(--color-primary);
		border-radius: var(--radius-lg);
		background: var(--color-primary-light);
		cursor: pointer;
		transition: all var(--transition-fast);
		color: var(--color-primary);
	}

	.target-btn:hover {
		background: rgba(30, 136, 229, 0.15);
		border-style: solid;
	}

	.target-btn.active {
		border-style: solid;
		background: var(--color-primary);
		color: white;
	}

	.target-btn .material-symbols {
		font-size: 1.5rem;
	}

	.target-btn-text {
		font-weight: 600;
		font-size: 0.85rem;
	}

	.target-btn-sub {
		font-size: 0.7rem;
		opacity: 0.7;
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
