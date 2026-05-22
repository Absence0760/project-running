<script lang="ts">
	import { goto, afterNavigate } from '$app/navigation';
	import { page } from '$app/stores';
	import RouteBuilder from '$lib/components/RouteBuilder.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import SplitPane from '$lib/components/SplitPane.svelte';
	import { toGpx, toKml, downloadFile } from '$lib/gpx';
	import { saveRoute } from '$lib/data';
	import { pickSavePolyline } from '$lib/route_save_polyline';
	import { showToast } from '$lib/stores/toast.svelte';
	import { distanceInPreferred, getUnit } from '$lib/units.svelte';
	import { env } from '$env/dynamic/public';

	// True when the local Protomaps tile-style override is set —
	// in that mode all three map-style buttons (streets/satellite/
	// terrain) collapse to the same self-hosted style and become
	// visually identical, which confuses the user into thinking the
	// buttons are broken. Hide the satellite + terrain buttons when
	// the override is on so only the "Streets" affordance shows.
	// See decisions.md § 68 + the May 2026 audit pass.
	const tileOverrideActive =
		(env.PUBLIC_TILE_STYLE_URL ?? '').trim().length > 0;

	const METRES_PER_MILE = 1609.344;

	// `?club=<uuid>` makes the new route club-owned. The club home page's
	// Routes tab links here with this param so route creation lands the
	// row directly under the club rather than the user.
	let clubId = $derived($page.url.searchParams.get('club'));

	let routeName = $state('');
	let routeDescription = $state('');
	let isPublic = $state(false);
	let mode = $state<'road' | 'trail'>('road');
	let waypointCount = $state(0);
	let distance = $state(0);
	let elevation = $state(0);
	let elevations = $state<number[]>([]);
	let coordinates = $state<[number, number][]>([]);
	let builder: RouteBuilder;
	let saving = $state(false);
	let saveError = $state('');
	let routingError = $state<string | null>(null);
	let routingErrorSeverity = $state<'error' | 'warning'>('error');
	let showSaveModal = $state(false);
	let showHelp = $state(false);
	// Mirrors the builder's internal isRouting so the Generate button
	// can flip to a Cancel button mid-batch. The public OSRM demo's
	// 8s per-segment timeout means a stuck batch can otherwise tie the
	// UI up for ~30s with no way out short of clearing the whole route.
	let builderBusy = $state(false);

	// Dev-only test hooks: Playwright drives the page against `vite dev`
	// (where import.meta.env.DEV is true). Two surfaces are exposed —
	//   - `__routeBuilder`: the RouteBuilder component instance, which
	//     already exports addWaypoint / clearWaypoints / generateLoop /
	//     etc. Specs use these instead of synthetic canvas clicks
	//     because the MapLibre WebGL pointer-event pipeline doesn't
	//     deliver clicks reliably in headless chromium, and converting
	//     a target lat/lng to a canvas pixel position would couple
	//     every spec to MapTiler's projection.
	//   - `__routeBuilderPage`: the page-level pickingPoint /
	//     startPoint / endPoint state, so a spec can set a start
	//     without dispatching the pick-on-map flow.
	// Production builds (`adapter-static` with DEV=false) never reach
	// this branch, so no leak.
	$effect(() => {
		if (typeof window === 'undefined') return;
		if (!import.meta.env.DEV) return;
		if (!builder) return;
		const w = window as unknown as Record<string, unknown>;
		w.__routeBuilder = builder;
		w.__routeBuilderPage = {
			setStartPoint(p: { lat: number; lng: number } | null) {
				startPoint = p;
				startLabel = p ? `${p.lat.toFixed(4)}, ${p.lng.toFixed(4)}` : '';
			},
			setEndPoint(p: { lat: number; lng: number } | null) {
				endPoint = p;
				endLabel = p ? `${p.lat.toFixed(4)}, ${p.lng.toFixed(4)}` : '';
			}
		};
	});

	// Reactive: tracks the module-level unit signal so every km/mi
	// label in the template re-renders the instant the user flips the
	// preference on /settings/preferences. Without these derived
	// values, the route builder kept showing km even after Save —
	// formatDistance-based pages already worked because they read the
	// signal indirectly; these inline strings were hardcoded.
	let preferredUnit = $derived(getUnit());
	let unitLabel = $derived(preferredUnit === 'mi' ? 'mi' : 'km');
	let distanceDisp = $derived(distanceInPreferred(distance));

	/// Same back-link contract as /plans/[id] and /guided — only pop the
	/// history entry when we actually came from /routes (or one of its
	/// tabs) so the parent's tab + filter snapshot survives. Otherwise
	/// fall through to a normal soft-nav.
	let cameFromRoutes = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromRoutes || !from) return;
		if (from.url.pathname === '/routes' || from.url.pathname.startsWith('/routes?')) {
			cameFromRoutes = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromRoutes) {
			e.preventDefault();
			history.back();
		}
	}

	function handleUpdate(data: {
		waypoints: number;
		distance: number;
		elevation: number;
		elevations: number[];
		coordinates: [number, number][];
		routed: boolean;
	}) {
		waypointCount = data.waypoints;
		distance = data.distance;
		elevation = data.elevation;
		elevations = data.elevations;
		coordinates = data.coordinates;
		// The builder tells us explicitly whether the emitted
		// `coordinates` is an OSRM-snapped polyline (Save-eligible) or
		// the straight-line preview between dropped waypoints. Reading
		// the flag instead of guessing from coords.length lets a
		// 2-waypoint snapped route enable Save without also enabling
		// it for the 2-waypoint preview that fires before Calculate.
		routed = data.routed;
	}

	function handleRoutingError(message: string | null, severity: 'error' | 'warning' = 'error') {
		routingError = message;
		routingErrorSeverity = severity;
		// Only hard errors invalidate the route. A 'warning' (partial
		// success — some OSRM segments dropped) still produced a usable
		// polyline, so the Save button should stay enabled.
		if (message && severity === 'error') routed = false;
	}

	let laps = $derived.by(() => {
		const routeData = builder?.getRouteData();
		if (!routeData || routeData.waypoints.length < 3) return { count: 0, lapDistance: 0 };

		const start = routeData.waypoints[0];
		let lapCount = 0;

		for (let i = 1; i < routeData.waypoints.length; i++) {
			const wp = routeData.waypoints[i];
			const dist = Math.sqrt((wp.lat - start.lat) ** 2 + (wp.lng - start.lng) ** 2);
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
		// paceMin:paceSec is per the user's preferred unit (per km in
		// metric, per mi in imperial). Convert the route distance into
		// that same unit before multiplying so a 10km route at 5:00/mi
		// reports the same total time it would in km mode at 8:03/km.
		const paceSecondsPerUnit = paceMin * 60 + paceSec;
		const distanceInUnit =
			preferredUnit === 'mi' ? distance / METRES_PER_MILE : distance / 1000;
		const totalSeconds = Math.round(distanceInUnit * paceSecondsPerUnit);
		const h = Math.floor(totalSeconds / 3600);
		const m = Math.floor((totalSeconds % 3600) / 60);
		const s = totalSeconds % 60;
		if (h > 0) return `~${h}h ${m}m`;
		return `~${m}m ${s}s`;
	});

	// targetKm is always stored in kilometres (the internal currency
	// of generateLoop's distanceMetres math). The slider + presets +
	// label are derived in the user's preferred unit. Slider min/max
	// adapt so a mile-mode user gets a 1-26 mi range instead of the
	// km-mode 1-42 km range.
	let targetDisplayValue = $derived(
		preferredUnit === 'mi' ? targetKm * (1000 / METRES_PER_MILE) : targetKm,
	);
	let targetDisplayMax = $derived(preferredUnit === 'mi' ? 26.2 : 42);
	let targetDisplayMin = $derived(preferredUnit === 'mi' ? 1 : 1);
	function setTargetFromDisplay(displayValue: number) {
		targetKm =
			preferredUnit === 'mi'
				? displayValue * (METRES_PER_MILE / 1000)
				: displayValue;
	}
	function setTargetFromKm(km: number) {
		targetKm = km;
	}

	let canSave = $derived(routed && routeName.trim().length > 0);

	async function handleCalculateRoute() {
		// Only flip `routed` to true when OSRM actually produced a
		// polyline. The old code set routed unconditionally after the
		// awaited call, even if the routing service was down — and the
		// Save button then submitted an empty/stale route.
		const ok = await builder?.calculateRoute();
		routed = !!ok;
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

	function handleMapPick(lngLat: { lng: number; lat: number }) {
		if (!pickingPoint) return false;
		const point = { lat: lngLat.lat, lng: lngLat.lng };
		const label = `${point.lat.toFixed(4)}, ${point.lng.toFixed(4)}`;
		if (pickingPoint === 'start') { startPoint = point; startLabel = label; }
		else { endPoint = point; endLabel = label; }
		pickingPoint = null;
		return true;
	}

	async function handleGenerateLoop() {
		// Pass startPoint through verbatim (or undefined when the user
		// hasn't picked one). The builder's own zoom-sanity guard
		// refuses with a pan-first message when start is undefined AND
		// the map is still in world view — falling back to
		// map.getCenter() here would mask that guard, since the
		// builder receives a defined start and skips the check, then
		// runs from a useless [0, 20] (mid-Atlantic) origin.
		const start = startPoint ?? undefined;
		const end = endPoint ?? undefined;

		const ok = await builder?.generateLoop(targetKm * 1000, start, end);
		routed = !!ok;
	}

	// Mirror the picked start / end into the map as a transient marker
	// so the user gets visual confirmation BEFORE clicking Generate.
	// Pre-fix, picking a start only updated the sidebar text label —
	// the user couldn't tell where their click actually landed without
	// running generation. Driven by a $effect so cleared picks
	// (startPoint = null) also clear the marker.
	$effect(() => {
		builder?.setGenerationStart(startPoint);
	});
	$effect(() => {
		builder?.setGenerationEnd(endPoint);
	});

	function openSaveModal() {
		saveError = '';
		showSaveModal = true;
	}

	async function handleSaveRoute() {
		if (!routeName.trim()) {
			saveError = 'Give your route a name.';
			return;
		}
		saving = true;
		saveError = '';
		try {
			const routeData = builder?.getRouteData();
			if (!routeData) return;

			// Persist the OSRM-snapped polyline (not the 2-10 click
			// points) so list-card thumbnails + the detail map have a
			// real route to draw. See route_save_polyline.ts for the
			// rationale + the regression test that pins it.
			const polyline = pickSavePolyline(routeData.waypoints, routeData.coordinates);

			const saved = await saveRoute({
				name: routeName.trim(),
				waypoints: polyline,
				distance_m: Math.round(distance * 100) / 100,
				elevation_m: elevation > 0 ? elevation : null,
				surface: mode === 'trail' ? 'trail' : 'road',
				is_public: isPublic,
				club_id: clubId,
				description: routeDescription,
			});

			showSaveModal = false;
			showToast('Route saved.', 'success');
			goto(`/routes/${saved.id}`);
		} catch (err) {
			saveError = err instanceof Error ? err.message : 'Failed to save route';
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head>
	<title>Route Builder — Threkir</title>
</svelte:head>

<div class="builder-layout">
	<SplitPane storageKey="route-builder-split" min={280} initialFraction={0.28}>
		{#snippet left()}
	<aside class="sidebar">
		<a href="/routes" class="back-link" onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			My routes
		</a>

		<header class="sidebar-head">
			<p class="kicker">New route</p>
			<h1>Route Builder</h1>
			<p class="tagline">
				Click the map to drop waypoints, snap to walkable paths, then save. The Surface toggle tags the saved route — it doesn't change the routing.
			</p>
		</header>

		<div class="controls">
			<fieldset class="control-group">
				<legend class="section-label">Surface</legend>
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

			<fieldset class="control-group">
				<legend class="section-label">Map style</legend>
				<div class="style-toggle">
					<button class="style-btn" class:active={currentMapStyle === 'streets'} onclick={() => handleMapStyle('streets')}>Streets</button>
					{#if !tileOverrideActive}
						<button class="style-btn" class:active={currentMapStyle === 'satellite'} onclick={() => handleMapStyle('satellite')}>Satellite</button>
						<button class="style-btn" class:active={currentMapStyle === 'terrain'} onclick={() => handleMapStyle('terrain')}>Terrain</button>
					{/if}
				</div>
			</fieldset>

			<div class="stats-row">
				<div class="builder-stat">
					<span class="builder-stat-value">{distanceDisp.value.toFixed(2)}</span>
					<span class="builder-stat-label">{distanceDisp.unit}</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{elevation}</span>
					<span class="builder-stat-label">m gain</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{waypointCount}</span>
					<span class="builder-stat-label">points</span>
				</div>
			</div>

			{#if distance > 0}
				<div class="time-estimate">
					<span class="time-value">{estimatedTime}</span>
					<div class="pace-input">
						<span class="pace-label">at</span>
						<input type="number" min="2" max="15" bind:value={paceMin} class="pace-num" />
						<span>:</span>
						<input type="number" min="0" max="59" bind:value={paceSec} class="pace-num" />
						<span class="pace-label">/{unitLabel}</span>
					</div>
				</div>
			{/if}

			{#if laps.count > 0}
				{@const lapDisp = distanceInPreferred(laps.lapDistance)}
				<div class="lap-info">
					<div class="lap-badge">
						<span class="material-symbols">loop</span>
						{laps.count} {laps.count === 1 ? 'lap' : 'laps'}
					</div>
					<span class="lap-detail">{lapDisp.value.toFixed(2)} {lapDisp.unit} per lap</span>
				</div>
			{/if}

			<div class="elevation-preview">
				<span class="section-label">Elevation profile</span>
				{#if elevations.length >= 2}
					<ElevationProfile {elevations} totalDistance={distance} />
				{:else}
					<div class="elevation-empty">
						<span class="material-symbols">show_chart</span>
						<span>Add waypoints to see the profile</span>
					</div>
				{/if}
			</div>

			<div class="toolbar-group" role="toolbar" aria-label="Waypoint actions">
				<button class="btn btn-ghost btn-sm" disabled={waypointCount === 0 || builderBusy} onclick={handleUndo} title="Undo last waypoint (Ctrl+Z)">
					<span class="material-symbols">undo</span>
					Undo
				</button>
				<button class="btn btn-ghost btn-sm" disabled={waypointCount < 2 || builderBusy} onclick={handleOutAndBack} title="Mirror the route back to start">
					<span class="material-symbols">swap_horiz</span>
					Out &amp; back
				</button>
				<button class="btn btn-ghost btn-sm" disabled={waypointCount === 0} onclick={handleClear} title="Clear all waypoints (Esc)">
					<span class="material-symbols">delete</span>
					Clear
				</button>
			</div>

			<button
				class="target-btn"
				class:active={showDistanceTarget}
				onclick={() => (showDistanceTarget = !showDistanceTarget)}
			>
				<span class="material-symbols">route</span>
				<span class="target-btn-text">
					{showDistanceTarget ? 'Hide distance target' : 'Generate a route by distance'}
				</span>
				<span class="target-btn-sub">5k, 10k, half, full — or any distance</span>
			</button>
			{#if showDistanceTarget}
				<div class="target-panel">
					<span class="section-label">Start</span>
					<div class="point-row">
						{#if startPoint}
							<span class="point-set">{startLabel}</span>
						{:else}
							<span class="point-unset">Not set (uses map center)</span>
						{/if}
						<button class="point-btn" onclick={() => useMyLocation('start')} aria-label="Use my location for start">
							<span class="material-symbols">my_location</span>
						</button>
						<button class="point-btn" class:active={pickingPoint === 'start'} onclick={() => pickOnMap('start')} aria-label="Pick start on map">
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if startPoint}
							<button class="point-btn" onclick={() => { startPoint = null; startLabel = ''; }} aria-label="Clear start">
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>

					<span class="section-label">End <span class="label-hint">(optional — defaults to start for loop)</span></span>
					<div class="point-row">
						{#if endPoint}
							<span class="point-set">{endLabel}</span>
						{:else}
							<span class="point-unset">Same as start (loop)</span>
						{/if}
						<button class="point-btn" onclick={() => useMyLocation('end')} aria-label="Use my location for end">
							<span class="material-symbols">my_location</span>
						</button>
						<button class="point-btn" class:active={pickingPoint === 'end'} onclick={() => pickOnMap('end')} aria-label="Pick end on map">
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if endPoint}
							<button class="point-btn" onclick={() => { endPoint = null; endLabel = ''; }} aria-label="Clear end">
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>

					<span class="section-label">Distance</span>
					<div class="target-row">
						<input
							type="range"
							min={targetDisplayMin}
							max={targetDisplayMax}
							step="0.1"
							value={targetDisplayValue}
							oninput={(e) => setTargetFromDisplay(parseFloat((e.target as HTMLInputElement).value))}
							class="target-slider"
						/>
						<span class="target-value">{targetDisplayValue.toFixed(1)} {unitLabel}</span>
					</div>
					<div class="target-presets">
						<!-- Race-distance names stay constant — "5k" / "Half" /
						     "Full" are how runners refer to them regardless
						     of preferred unit. The slider value displays in
						     whichever unit the user prefers. -->
						<button onclick={() => setTargetFromKm(5)}>5k</button>
						<button onclick={() => setTargetFromKm(10)}>10k</button>
						<button onclick={() => setTargetFromKm(21.1)}>Half</button>
						<button onclick={() => setTargetFromKm(42.2)}>Full</button>
					</div>
					{#if builderBusy}
						<button class="btn btn-outline" onclick={() => builder?.cancelGeneration()}>
							Cancel generating…
						</button>
					{:else}
						<button class="btn btn-secondary" onclick={handleGenerateLoop}>
							Generate {targetDisplayValue.toFixed(1)} {unitLabel} {endPoint ? 'route' : 'loop'}
						</button>
					{/if}
				</div>
			{/if}

			{#if pickingPoint}
				<div class="pick-hint" role="status">
					Click on the map to set the {pickingPoint} point
				</div>
			{/if}

			<div class="primary-actions">
				<button
					class="btn btn-secondary"
					disabled={waypointCount < 2 || builderBusy}
					onclick={handleCalculateRoute}
				>
					{routed ? 'Recalculate' : 'Calculate Route'}
				</button>
				{#if routed}
					<button
						class="btn btn-outline btn-sm"
						disabled={builderBusy}
						onclick={handleUndoCalculate}
						aria-label="Undo calculation"
					>
						<span class="material-symbols">undo</span>
					</button>
				{/if}
			</div>

			<div class="primary-actions">
				<button
					class="btn btn-primary"
					disabled={!routed || builderBusy}
					onclick={openSaveModal}
				>
					<span class="material-symbols" aria-hidden="true">save</span>
					Save Route
				</button>
				<button
					class="btn btn-outline btn-sm"
					disabled={!routed || builderBusy}
					onclick={handleExportGpx}
					title="Export as GPX"
				>
					GPX
				</button>
				<button
					class="btn btn-outline btn-sm"
					disabled={!routed || builderBusy}
					onclick={handleExportKml}
					title="Export as KML"
				>
					KML
				</button>
			</div>
		</div>

		<details class="help" bind:open={showHelp}>
			<summary>
				<span class="material-symbols">keyboard</span>
				Tips &amp; shortcuts
			</summary>
			<ul>
				<li><kbd>Click</kbd> map to drop a waypoint</li>
				<li><kbd>Click</kbd> the green start marker to close a loop</li>
				<li><kbd>Click</kbd> the route line to insert a mid-route point</li>
				<li><kbd>Drag</kbd> a marker to reposition it</li>
				<li><kbd>Right-click</kbd> a marker to delete</li>
				<li><kbd>Ctrl</kbd>+<kbd>Z</kbd> undo last waypoint</li>
				<li><kbd>Esc</kbd> clear everything</li>
			</ul>
		</details>
	</aside>
		{/snippet}

		{#snippet right()}
	<main class="map-area">
		<RouteBuilder
			bind:this={builder}
			{mode}
			onupdate={handleUpdate}
			onmapclick={handleMapPick}
			onerror={handleRoutingError}
			onbusy={(b) => (builderBusy = b)}
		/>

		{#if waypointCount === 0 && !pickingPoint}
			<div class="canvas-empty" role="status">
				<span class="material-symbols">add_location</span>
				<h3>Click anywhere to start</h3>
				<p>Drop waypoints to sketch your route. Hit <strong>Calculate route</strong> when you're ready to snap to walkable paths.</p>
			</div>
		{/if}

		{#if routingError}
			<div
				class="routing-error"
				class:routing-warning={routingErrorSeverity === 'warning'}
				role={routingErrorSeverity === 'warning' ? 'status' : 'alert'}
			>
				<span class="material-symbols">
					{routingErrorSeverity === 'warning' ? 'warning' : 'error'}
				</span>
				<div class="routing-error-text">{routingError}</div>
				<button
					class="routing-error-dismiss"
					aria-label="Dismiss"
					onclick={() => (routingError = null)}
				>
					<span class="material-symbols">close</span>
				</button>
			</div>
		{/if}
	</main>
		{/snippet}
	</SplitPane>
</div>

<Modal open={showSaveModal} title="Save route" onclose={() => (showSaveModal = false)}>
	<form
		class="save-form"
		onsubmit={(e) => { e.preventDefault(); handleSaveRoute(); }}
	>
		<label class="field">
			<span class="section-label">Name</span>
			<input
				type="text"
				placeholder="My Route"
				bind:value={routeName}
				required
			/>
		</label>

		<label class="field">
			<span class="section-label">Description <span class="label-hint">(optional)</span></span>
			<textarea
				rows="3"
				placeholder="Notes about the route — terrain, water stops, parking…"
				bind:value={routeDescription}
			></textarea>
		</label>

		<div class="save-summary">
			<div>
				<span class="save-summary-value">{distanceDisp.value.toFixed(2)} {distanceDisp.unit}</span>
				<span class="save-summary-label">Distance</span>
			</div>
			<div>
				<span class="save-summary-value">{elevation} m</span>
				<span class="save-summary-label">Elevation</span>
			</div>
			<div>
				<span class="save-summary-value">{mode === 'trail' ? 'Trail' : 'Road'}</span>
				<span class="save-summary-label">Surface</span>
			</div>
		</div>

		<label class="visibility">
			<input type="checkbox" bind:checked={isPublic} />
			<span>
				<strong>Public</strong>
				<span class="visibility-hint">Anyone with the link can view this route.</span>
			</span>
		</label>

		{#if saveError}
			<div class="save-error" role="alert">{saveError}</div>
		{/if}

		<div class="save-actions">
			<button
				type="button"
				class="btn btn-outline"
				onclick={() => (showSaveModal = false)}
				disabled={saving}
			>
				Cancel
			</button>
			<button
				type="submit"
				class="btn btn-primary"
				disabled={!canSave || saving}
			>
				{#if saving}
					<span class="btn-spinner" aria-hidden="true"></span>
					Saving…
				{:else}
					Save route
				{/if}
			</button>
		</div>
	</form>
</Modal>

<style>
	.builder-layout {
		display: flex;
		height: 100vh;
		min-height: 0;
	}

	.sidebar {
		/* Width comes from SplitPane (resizable). The sidebar fills
		 * the left pane and scrolls internally when content
		 * overflows. Border-right is the visual edge between panel
		 * and map; the SplitPane divider sits on top of it. */
		width: 100%;
		height: 100%;
		flex-shrink: 0;
		border-right: 1px solid var(--color-border);
		padding: var(--space-lg) var(--space-lg) var(--space-xl);
		overflow-y: auto;
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		/* Container queries so the dense layouts inside (stats row,
		 * surface + map-style toggles, target-presets row) respond
		 * to the PANEL width when the user drags the SplitPane in. */
		container-type: inline-size;
		container-name: sidebar;
	}

	@container sidebar (max-width: 360px) {
		/* Surface toggle + map-style toggle are 2-button + 3-button
		 * pill rows. Below 360 px the labels wrap or truncate ugly. */
		.mode-buttons {
			gap: var(--space-xs);
		}
		.mode-btn {
			padding: var(--space-xs) var(--space-sm);
			font-size: 0.8rem;
		}
		.style-btn {
			font-size: 0.7rem;
			padding: var(--space-2xs) var(--space-xs);
		}
		/* Stats row: distance / elevation / waypoints. At narrow
		 * widths the 1.05rem value font overflows the cell. */
		.builder-stat-value {
			font-size: 0.95rem;
		}
		.target-presets {
			flex-wrap: wrap;
		}
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.05rem;
	}

	.sidebar-head .kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-2xs);
	}
	.sidebar-head h1 {
		font-size: 1.4rem;
		font-weight: 700;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.sidebar-head .tagline {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.45;
		margin: 0;
	}

	.controls {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.control-group {
		border: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.control-group legend {
		padding: 0;
		margin-bottom: var(--space-2xs);
	}

	input[type="text"],
	input[type="number"],
	textarea {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		font-family: inherit;
		transition: border-color var(--transition-fast);
		background: var(--color-bg);
		color: var(--color-text);
	}
	input:focus,
	textarea:focus {
		outline: none;
		border-color: var(--color-primary);
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
		cursor: pointer;
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
		font-size: 1.05rem;
		font-weight: 700;
		line-height: 1.1;
	}
	.builder-stat-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.elevation-preview {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
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
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 25%, transparent);
		border-radius: var(--radius-md);
	}
	.lap-badge {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-weight: 700;
		font-size: 0.85rem;
		color: var(--color-primary);
	}
	.lap-detail {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

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
		width: 2.4rem;
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

	.target-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
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

	.point-btn {
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
	.point-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.point-btn.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}
	.point-btn .material-symbols {
		font-size: 0.85rem;
	}

	.label-hint {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.7rem;
		text-transform: none;
		letter-spacing: 0;
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
		margin-top: var(--space-xs);
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
		color: var(--color-text);
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
		gap: var(--space-2xs);
		padding: var(--space-md);
		border: 2px dashed var(--color-primary);
		border-radius: var(--radius-lg);
		background: var(--color-primary-light);
		cursor: pointer;
		transition: all var(--transition-fast);
		color: var(--color-primary);
	}
	.target-btn:hover {
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

	/*
	 * `.toolbar-group` and `.primary-actions` are local layout, not
	 * button variants — the buttons themselves use `.btn` / `.btn-ghost`
	 * / `.btn-primary` etc. from app.css (per conventions § Web buttons).
	 */
	.toolbar-group {
		display: flex;
		gap: var(--space-2xs);
		padding: var(--space-2xs);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.toolbar-group .btn {
		flex: 1;
		justify-content: center;
		padding: var(--space-xs) var(--space-sm);
	}
	.toolbar-group .material-symbols {
		font-size: 1rem;
	}

	.btn-ghost {
		background: transparent;
		border: none;
		color: var(--color-text-secondary);
	}
	.btn-ghost:hover:not(:disabled) {
		background: var(--color-surface);
		color: var(--color-text);
	}

	.primary-actions {
		display: flex;
		gap: var(--space-sm);
	}
	.primary-actions .btn:first-child {
		flex: 1;
	}

	/*
	 * Map-overlay empty state. Rendered on top of the MapLibre canvas
	 * when no waypoints exist — pointer-events disabled so a click on
	 * the card still drops a waypoint behind it. Fades out when the
	 * cursor is over the map so the user can see where they're about
	 * to drop the first waypoint; comes back when the cursor leaves.
	 */
	.canvas-empty {
		position: absolute;
		/* Tucked into the bottom-left so it doesn't sit over the
		 * area the user is about to click. The map's top-right
		 * is occupied by MapLibre's nav + locate controls and the
		 * AppBar's search box is centered up top — bottom-left is
		 * the empty corner. */
		bottom: var(--space-md);
		left: var(--space-md);
		z-index: 5;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		text-align: left;
		gap: var(--space-xs);
		padding: var(--space-md) var(--space-lg);
		background: color-mix(in srgb, var(--color-surface) 92%, transparent);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-lg);
		backdrop-filter: blur(8px);
		max-width: 20rem;
		pointer-events: none;
		transition: opacity 180ms ease-out;
	}
	.map-area:hover .canvas-empty {
		opacity: 0.15;
	}
	.canvas-empty .material-symbols {
		font-size: 2.4rem;
		color: var(--color-primary);
		margin-bottom: var(--space-2xs);
	}
	.canvas-empty h3 {
		font-size: 1.05rem;
		font-weight: 700;
		margin: 0;
	}
	.canvas-empty p {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.45;
		margin: 0;
	}

	.help {
		margin-top: auto;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		font-size: 0.8rem;
	}
	.help summary {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		cursor: pointer;
		font-weight: 600;
		color: var(--color-text-secondary);
		list-style: none;
	}
	.help summary::-webkit-details-marker {
		display: none;
	}
	.help summary .material-symbols {
		font-size: 1rem;
	}
	.help[open] summary {
		margin-bottom: var(--space-sm);
		color: var(--color-text);
	}
	.help ul {
		margin: 0;
		padding: 0;
		list-style: none;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
	}
	.help kbd {
		display: inline-block;
		padding: 0 0.35em;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-family: inherit;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text);
	}

	.map-area {
		flex: 1;
		min-width: 0;
		background: var(--color-bg-tertiary);
		position: relative;
	}

	.routing-error {
		position: absolute;
		top: 1rem;
		left: 50%;
		transform: translateX(-50%);
		z-index: 10;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		max-width: 28rem;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-danger);
		color: white;
		box-shadow: var(--shadow-lg);
		font-size: 0.9rem;
	}
	/* Partial-success warning — route is drawn but some OSRM segments
	   dropped. Visually distinct from a hard failure so the user
	   doesn't think their work was lost. */
	.routing-error.routing-warning {
		background: var(--color-warning, #b45309);
	}
	.routing-error-text {
		flex: 1;
		line-height: 1.35;
	}
	.routing-error-dismiss {
		background: transparent;
		border: 0;
		color: white;
		cursor: pointer;
		padding: 0;
		display: inline-flex;
		align-items: center;
	}

	/* Save modal */
	.save-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.save-summary {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		text-align: center;
	}
	.save-summary-value {
		display: block;
		font-size: 1rem;
		font-weight: 700;
	}
	.save-summary-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.visibility {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.visibility input[type="checkbox"] {
		width: auto;
		margin-top: 3px;
		flex-shrink: 0;
		accent-color: var(--color-primary);
	}
	.visibility strong {
		display: block;
		font-size: 0.9rem;
	}
	.visibility-hint {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}
	.save-error {
		padding: var(--space-sm) var(--space-md);
		background: var(--color-danger-light);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		border-radius: var(--radius-md);
		color: var(--color-danger);
		font-size: 0.85rem;
	}
	.save-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		padding-top: var(--space-xs);
	}

	.btn-spinner {
		display: inline-block;
		width: 0.9em;
		height: 0.9em;
		border: 2px solid color-mix(in srgb, currentColor 40%, transparent);
		border-top-color: currentColor;
		border-radius: 50%;
		animation: btn-spin 0.6s linear infinite;
	}
	@keyframes btn-spin {
		to { transform: rotate(360deg); }
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	/*
	 * At < 720px the 22rem sidebar + map flex side-by-side leaves the
	 * map too narrow to actually plan on. Stack vertically with the map
	 * dominant — sidebar caps at 60vh and scrolls.
	 */
	@media (max-width: 720px) {
		.builder-layout {
			flex-direction: column-reverse;
		}
		.sidebar {
			width: 100%;
			max-height: 60vh;
			border-right: none;
			border-top: 1px solid var(--color-border);
		}
		.map-area {
			flex: 1;
			min-height: 50vh;
		}
		.canvas-empty {
			max-width: calc(100vw - 2rem);
			padding: var(--space-lg) var(--space-xl);
		}
	}
</style>
