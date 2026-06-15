<script lang="ts">
	import { goto } from '$app/navigation';
	import { smartBack } from '$lib/util/smart_back';
	import { page } from '$app/stores';
	import RouteBuilder from '$lib/components/RouteBuilder.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import SplitPane from '$lib/components/SplitPane.svelte';
	import { toGpx, toKml, downloadFile } from '$lib/routes/gpx';
	import { saveRoute } from '$lib/core/data';
	import { pickSavePolyline } from '$lib/routes/route_save_polyline';
	import { showToast } from '$lib/stores/toast.svelte';
	import { distanceInPreferred, getUnit } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { env } from '$env/dynamic/public';
	import {
		requestRouteConstraints,
		RouteRequestError,
	} from '$lib/routes/route_request_client';

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
	// Set when a generated loop lands outside the accept band because the road
	// network can't form a clean loop at that distance here. Drives the explicit
	// 3-way choice in the warning banner: generate the largest real loop nearby
	// (when `largestLoopM` is present), accept this achievable out-and-back
	// distance, or try a different start.
	let generateShortfall = $state<{ achievedM: number; largestLoopM?: number } | null>(null);
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
			// Lets e2e skip the Satellite/Terrain assertions when a local
			// tileserver override is configured (which collapses the
			// style switcher to Streets-only — see tileOverrideActive).
			tileOverrideActive,
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

	/// Pop history to wherever we actually came from — a /routes tab (its
	/// filter + scroll snapshot survives the popstate) or the club whose
	/// Routes tab launched "New route" via /routes/new?club=. A hard load
	/// falls through to the static /routes parent.
	const back = smartBack();

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

	let showClearConfirm = $state(false);

	function handleClear(): boolean {
		// Confirm before discarding a route the user has actually started —
		// Undo only steps back one waypoint, so a stray Clear is total loss.
		// Returns true so the RouteBuilder's Esc shortcut treats this as the
		// owner of the clear (and routes Esc through the same confirm gate as
		// the Clear button) instead of clearing the canvas directly.
		if (waypointCount >= 2) {
			showClearConfirm = true;
			return true;
		}
		doClear();
		return true;
	}

	function doClear() {
		builder?.clearWaypoints();
		routed = false;
	}

	// Strip a route name down to a filesystem-safe ASCII basename for the
	// export filename. A non-Latin name (ja/zh/emoji) — or even the
	// localized `untitledRoute` fallback in a non-Latin locale — reduces
	// to an empty string here, which previously produced a bare ".gpx" /
	// ".kml". Guard with a constant so the download always has a real
	// basename. The file's <name> tag still carries the full Unicode name.
	function exportBasename(name: string): string {
		return name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') || 'route';
	}

	function handleExportGpx() {
		const name = routeName || m('routeNew.untitledRoute');
		const gpx = toGpx(name, coordinates, elevations);
		downloadFile(gpx, `${exportBasename(name)}.gpx`, 'application/gpx+xml');
	}

	function handleExportKml() {
		const name = routeName || m('routeNew.untitledRoute');
		const kml = toKml(name, coordinates, elevations);
		downloadFile(kml, `${exportBasename(name)}.kml`, 'application/vnd.google-earth.kml+xml');
	}

	let routed = $state(false);
	let currentMapStyle = $state<'streets' | 'satellite' | 'terrain'>('streets');
	let paceMin = $state(5);
	let paceSec = $state(30);
	let targetKm = $state(5);
	let showDistanceTarget = $state(false);
	// Avoid-highways / prefer-residential preference for distance generation.
	// Off → today's generation; on → the server biases the loop onto quiet
	// streets via a GraphHopper custom model, falling back to plain generation
	// if the engine can't honour it.
	let quietRoads = $state(false);
	let pickingPoint = $state<'start' | 'end' | null>(null);
	let startPoint = $state<{ lat: number; lng: number } | null>(null);
	let endPoint = $state<{ lat: number; lng: number } | null>(null);
	let startLabel = $state('');
	let endLabel = $state('');
	// Keyboard-accessible coordinate entry (WCAG 2.1.1): picking a
	// start/end via the map is pointer-only, so these inputs let a
	// keyboard user type lat/lng instead. audit-findings 2026-05-30 High.
	let startLatInput = $state('');
	let startLngInput = $state('');
	let endLatInput = $state('');
	let endLngInput = $state('');
	let startCoordError = $state('');
	let endCoordError = $state('');

	function applyCoords(target: 'start' | 'end') {
		const setErr = (msg: string) => {
			if (target === 'start') startCoordError = msg;
			else endCoordError = msg;
		};
		setErr('');
		const latStr = target === 'start' ? startLatInput : endLatInput;
		const lngStr = target === 'start' ? startLngInput : endLngInput;
		const lat = Number(latStr);
		const lng = Number(lngStr);
		if (latStr.trim() === '' || lngStr.trim() === '' || Number.isNaN(lat) || Number.isNaN(lng)) {
			setErr(m('routeNew.coordNumericError'));
			return;
		}
		if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
			setErr(m('routeNew.coordRangeError'));
			return;
		}
		const point = { lat, lng };
		const label = `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
		if (target === 'start') { startPoint = point; startLabel = label; }
		else { endPoint = point; endLabel = label; }
		// Bring the typed point into view — same visual-confirmation
		// reasoning as useMyLocation. Typed coords are just as likely to
		// land off-screen as a geolocated fix.
		builder?.flyTo(point);
	}

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

	// --- AI route request (NL → constraints) ---
	// Purely additive: the box asks the Pro-gated extractor to turn a
	// plain-English request into the generation constraints, then populates
	// the manual form below for the user to review + adjust before
	// generating. The LLM never routes — it only fills the form. On any
	// failure (non-Pro, unconfigured, model error) the manual form is
	// untouched and we show a one-line hint.
	let nlRequest = $state('');
	let nlBusy = $state(false);
	let nlError = $state<string | null>(null);
	// Set after a successful extraction so the user sees what was applied
	// (incl. constraints the form can't render directly — shape /
	// avoid-highways) and which fields were assumed from a default.
	let nlApplied = $state<{
		shape: 'loop' | 'out_and_back' | 'point_to_point';
		avoidHighways: boolean;
		assumptions: string[];
	} | null>(null);

	const METRES_PER_KM = 1000;

	async function handleNlRequest() {
		const text = nlRequest.trim();
		if (text.length === 0 || nlBusy) return;
		nlBusy = true;
		nlError = null;
		nlApplied = null;
		try {
			// Pass the picked start label as a location hint only (never raw
			// coordinates — the handler takes a label and the start point
			// stays the user's explicit pick / map centre on generate).
			const locationLabel = startLabel || null;
			const c = await requestRouteConstraints(text, locationLabel);

			// Map the validated constraints onto the manual form. The user
			// reviews these before pressing Generate — nothing auto-runs.
			targetKm = Math.round((c.distanceM / METRES_PER_KM) * 10) / 10;
			// surface trail → trail mode; road/mixed → road. (The form's
			// Surface toggle is binary; "mixed" maps to road, the default.)
			mode = c.surface === 'trail' ? 'trail' : 'road';
			// Make the distance panel visible so the populated controls show.
			showDistanceTarget = true;
			nlApplied = {
				shape: c.shape,
				avoidHighways: c.avoidHighways,
				assumptions: c.assumptions,
			};
		} catch (err) {
			if (err instanceof RouteRequestError) {
				nlError =
					err.kind === 'upgrade'
						? m('routeNew.aiRequestProOnly')
						: err.kind === 'not_understood'
							? m('routeNew.aiRequestNotUnderstood')
							: err.kind === 'not_authenticated'
								? m('routeNew.aiRequestSignedOut')
								: m('routeNew.aiRequestUnavailable');
			} else {
				nlError = m('routeNew.aiRequestUnavailable');
			}
		} finally {
			nlBusy = false;
		}
	}

	let canSave = $derived(routed && routeName.trim().length > 0);

	function handleOutAndBack() {
		builder?.outAndBack();
		routed = false;
	}

	function handleMapStyle(style: 'streets' | 'satellite' | 'terrain') {
		currentMapStyle = style;
		builder?.setMapStyle(style);
	}

	function useMyLocation(target: 'start' | 'end') {
		// Match the map's locate button: `navigator.geolocation` is
		// undefined on an insecure (http-over-LAN) context, where calling
		// getCurrentPosition would throw uncaught and the button would
		// truly do nothing. Surface it instead.
		if (!navigator.geolocation) {
			showToast(m('routeBuilder.geolocationNeedsHttps'), 'error');
			return;
		}
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				const point = { lat: pos.coords.latitude, lng: pos.coords.longitude };
				const label = m('routeNew.myLocation');
				if (target === 'start') { startPoint = point; startLabel = label; }
				else { endPoint = point; endLabel = label; }
				// Pan the map to the located point. Without this the click
				// only updated the sidebar label + painted a marker that
				// could be off-screen, so on the default world view the
				// button looked dead — the reported "does nothing".
				builder?.flyTo(point);
			},
			(err) => {
				// Don't fail silently — the old empty callback left the button
				// looking dead on denial/timeout. Surface each error code.
				const msg =
					err.code === 1
						? m('routeBuilder.locationPermissionDenied')
						: err.code === 2
							? m('routeBuilder.locationUnavailable')
							: err.code === 3
								? m('routeBuilder.locationTimedOut')
								: m('routeBuilder.locationFailed');
				showToast(msg, 'error');
			},
			// Same as the map's locate button: a cached fix + a realistic timeout
			// so desktop/Brave IP geolocation doesn't time out at 5s.
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 }
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
		// Clear any prior shortfall affordance — this run decides anew.
		generateShortfall = null;
		// Pass startPoint through verbatim (or undefined when the user
		// hasn't picked one). The builder's own zoom-sanity guard
		// refuses with a pan-first message when start is undefined AND
		// the map is still in world view — falling back to
		// map.getCenter() here would mask that guard, since the
		// builder receives a defined start and skips the check, then
		// runs from a useless [0, 20] (mid-Atlantic) origin.
		const start = startPoint ?? undefined;
		const end = endPoint ?? undefined;

		const ok = await builder?.generateLoop(
			targetKm * 1000,
			start,
			end,
			quietRoads ? 'quiet' : undefined,
		);
		routed = !!ok;
	}

	// Accept the distance the road network could actually loop. Aligns the target
	// to the drawn route and clears the shortfall warning; the route itself stays
	// exactly as generated.
	function useAchievedDistance() {
		if (!generateShortfall) return;
		targetKm = Math.round(generateShortfall.achievedM / 100) / 10;
		generateShortfall = null;
		routingError = null;
	}

	// Choice (a): generate the largest genuinely clean loop the graph search found
	// near this start. Re-runs generation at that distance, so the user gets a real
	// loop instead of the out-and-back fallback. Aligns the target to it too.
	async function generateLargestLoop() {
		const largest = generateShortfall?.largestLoopM;
		if (!largest) return;
		generateShortfall = null;
		routingError = null;
		targetKm = Math.round(largest / 100) / 10;
		const start = startPoint ?? undefined;
		const end = endPoint ?? undefined;
		const ok = await builder?.generateLoop(largest, start, end, quietRoads ? 'quiet' : undefined);
		routed = !!ok;
	}

	// Choice (c): try a different start. Clear the failed route + the shortfall and
	// drop into start-picking so the user can choose a loop-richer location.
	function tryDifferentStart() {
		generateShortfall = null;
		routingError = null;
		builder?.clearWaypoints();
		routed = false;
		pickingPoint = 'start';
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
			saveError = m('routeNew.nameRequiredError');
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
			showToast(m('routeNew.savedToast'), 'success');
			goto(`/routes/${saved.id}`);
		} catch (err) {
			// Surface the failure IN the save modal (persistent, in-context)
			// and keep it open with the user's work intact — a transient toast
			// would vanish and read as a half-navigated dead end.
			saveError = err instanceof Error ? err.message : m('routeNew.saveFailedError');
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head>
	<title>{m('routeNew.routeBuilder')} — Threkir</title>
</svelte:head>

<div class="builder-layout">
	<SplitPane storageKey="route-builder-split" min={280} initialFraction={0.28}>
		{#snippet left()}
	<aside class="sidebar">
		<a href="/routes" class="back-link" onclick={back.handle}>
			<span class="material-symbols">arrow_back</span>
			{m('routeNew.myRoutes')}
		</a>

		<header class="sidebar-head">
			<p class="kicker">{m('routeNew.newRoute')}</p>
			<h1>{m('routeNew.routeBuilder')}</h1>
			<p class="tagline">
				{m('routeNew.tagline')}
			</p>
		</header>

		<div class="controls">
			<fieldset class="control-group">
				<legend class="section-label">{m('routeNew.surface')}</legend>
				<div class="mode-buttons">
					<button
						class="mode-btn"
						class:active={mode === 'road'}
						onclick={() => (mode = 'road')}
					>
						<span class="material-symbols" aria-hidden="true">directions_car</span>
						{m('routeNew.road')}
					</button>
					<button
						class="mode-btn"
						class:active={mode === 'trail'}
						onclick={() => (mode = 'trail')}
					>
						<span class="material-symbols" aria-hidden="true">forest</span>
						{m('routeNew.trail')}
					</button>
				</div>
			</fieldset>

			<fieldset class="control-group">
				<legend class="section-label">{m('routeNew.mapStyle')}</legend>
				<div class="style-toggle">
					<button class="style-btn" class:active={currentMapStyle === 'streets'} onclick={() => handleMapStyle('streets')}>{m('routeNew.streets')}</button>
					{#if !tileOverrideActive}
						<button class="style-btn" class:active={currentMapStyle === 'satellite'} onclick={() => handleMapStyle('satellite')}>{m('routeNew.satellite')}</button>
						<button class="style-btn" class:active={currentMapStyle === 'terrain'} onclick={() => handleMapStyle('terrain')}>{m('routeNew.terrain')}</button>
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
					<span class="builder-stat-label">{m('routeNew.metresGain')}</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{waypointCount}</span>
					<span class="builder-stat-label">{m('routeNew.points')}</span>
				</div>
			</div>

			{#if distance > 0}
				<div class="time-estimate">
					<span class="time-value">{estimatedTime}</span>
					<div class="pace-input">
						<span class="pace-label">{m('routeNew.paceAt')}</span>
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
						{laps.count === 1 ? m('routeNew.lapCountOne', { count: laps.count }) : m('routeNew.lapCountOther', { count: laps.count })}
					</div>
					<span class="lap-detail">{m('routeNew.perLap', { distance: `${lapDisp.value.toFixed(2)} ${lapDisp.unit}` })}</span>
				</div>
			{/if}

			<div class="elevation-preview">
				<span class="section-label">{m('routeNew.elevationProfile')}</span>
				{#if elevations.length >= 2}
					<ElevationProfile {elevations} totalDistance={distance} />
				{:else}
					<div class="elevation-empty">
						<span class="material-symbols">show_chart</span>
						<span>{m('routeNew.elevationEmpty')}</span>
					</div>
				{/if}
			</div>

			<div class="toolbar-group" role="toolbar" aria-label={m('routeNew.waypointActions')}>
				<button class="btn btn-ghost btn-sm" disabled={waypointCount === 0 || builderBusy} onclick={handleUndo} title={m('routeNew.undoTitle')}>
					<span class="material-symbols">undo</span>
					{m('routeNew.undo')}
				</button>
				<button class="btn btn-ghost btn-sm" disabled={waypointCount < 2 || builderBusy} onclick={handleOutAndBack} title={m('routeNew.outAndBackTitle')}>
					<span class="material-symbols">swap_horiz</span>
					{m('routeNew.outAndBack')}
				</button>
				<button class="btn btn-ghost btn-sm" disabled={waypointCount === 0} onclick={handleClear} title={m('routeNew.clearTitle')}>
					<span class="material-symbols">delete</span>
					{m('routeNew.clear')}
				</button>
			</div>

			<button
				class="target-btn"
				class:active={showDistanceTarget}
				onclick={() => (showDistanceTarget = !showDistanceTarget)}
			>
				<span class="material-symbols">route</span>
				<span class="target-btn-text">
					{showDistanceTarget ? m('routeNew.hideDistanceTarget') : m('routeNew.generateByDistance')}
				</span>
				<span class="target-btn-sub">{m('routeNew.distancePresetsHint')}</span>
			</button>
			{#if showDistanceTarget}
				<div class="target-panel">
					<div class="ai-request">
						<span class="section-label">{m('routeNew.aiRequestLabel')}</span>
						<p class="ai-request-hint">{m('routeNew.aiRequestHint')}</p>
						<form
							class="ai-request-form"
							onsubmit={(e) => { e.preventDefault(); handleNlRequest(); }}
						>
							<input
								type="text"
								class="ai-request-input"
								bind:value={nlRequest}
								placeholder={m('routeNew.aiRequestPlaceholder')}
								aria-label={m('routeNew.aiRequestLabel')}
								disabled={nlBusy}
							/>
							<button
								type="submit"
								class="btn btn-secondary btn-sm"
								disabled={nlBusy || nlRequest.trim().length === 0}
							>
								{#if nlBusy}
									<span class="btn-spinner" aria-hidden="true"></span>
									{m('routeNew.aiRequestWorking')}
								{:else}
									{m('routeNew.aiRequestButton')}
								{/if}
							</button>
						</form>
						{#if nlError}
							<p class="ai-request-error" role="alert">{nlError}</p>
						{/if}
						{#if nlApplied}
							<div class="ai-request-applied" role="status">
								<p class="ai-request-applied-title">{m('routeNew.aiRequestApplied')}</p>
								<ul class="ai-request-applied-list">
									{#if nlApplied.shape !== 'loop'}
										<li>
											{nlApplied.shape === 'out_and_back'
												? m('routeNew.aiRequestShapeOutBack')
												: m('routeNew.aiRequestShapePointToPoint')}
										</li>
									{/if}
									{#if nlApplied.avoidHighways}
										<li>{m('routeNew.aiRequestAvoidHighways')}</li>
									{/if}
									{#if nlApplied.assumptions.length > 0}
										<li>{m('routeNew.aiRequestAssumed')}</li>
									{/if}
								</ul>
							</div>
						{/if}
					</div>

					<span class="section-label">{m('routeNew.start')}</span>
					<div class="point-row">
						{#if startPoint}
							<span class="point-set">{startLabel}</span>
						{:else}
							<span class="point-unset">{m('routeNew.startUnset')}</span>
						{/if}
						<button class="point-btn" onclick={() => useMyLocation('start')} aria-label={m('routeNew.useMyLocationStart')}>
							<span class="material-symbols">my_location</span>
						</button>
						<button class="point-btn" class:active={pickingPoint === 'start'} onclick={() => pickOnMap('start')} aria-label={m('routeNew.pickStartOnMap')}>
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if startPoint}
							<button class="point-btn" onclick={() => { startPoint = null; startLabel = ''; }} aria-label={m('routeNew.clearStart')}>
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>
					<!-- Keyboard alternative to map-tap (WCAG 2.1.1). -->
					<form class="coord-entry" onsubmit={(e) => { e.preventDefault(); applyCoords('start'); }}>
						<input class="coord-input" type="text" inputmode="decimal" bind:value={startLatInput} aria-label={m('routeNew.startLatitude')} placeholder={m('routeNew.latPlaceholder')} />
						<input class="coord-input" type="text" inputmode="decimal" bind:value={startLngInput} aria-label={m('routeNew.startLongitude')} placeholder={m('routeNew.lngPlaceholder')} />
						<button type="submit" class="btn btn-sm btn-secondary">{m('routeNew.setStart')}</button>
					</form>
					{#if startCoordError}
						<p class="coord-error" role="alert">{startCoordError}</p>
					{/if}

					<span class="section-label">{m('routeNew.end')} <span class="label-hint">{m('routeNew.endHint')}</span></span>
					<div class="point-row">
						{#if endPoint}
							<span class="point-set">{endLabel}</span>
						{:else}
							<span class="point-unset">{m('routeNew.endUnset')}</span>
						{/if}
						<button class="point-btn" onclick={() => useMyLocation('end')} aria-label={m('routeNew.useMyLocationEnd')}>
							<span class="material-symbols">my_location</span>
						</button>
						<button class="point-btn" class:active={pickingPoint === 'end'} onclick={() => pickOnMap('end')} aria-label={m('routeNew.pickEndOnMap')}>
							<span class="material-symbols">pin_drop</span>
						</button>
						{#if endPoint}
							<button class="point-btn" onclick={() => { endPoint = null; endLabel = ''; }} aria-label={m('routeNew.clearEnd')}>
								<span class="material-symbols">close</span>
							</button>
						{/if}
					</div>
					<!-- Keyboard alternative to map-tap (WCAG 2.1.1). -->
					<form class="coord-entry" onsubmit={(e) => { e.preventDefault(); applyCoords('end'); }}>
						<input class="coord-input" type="text" inputmode="decimal" bind:value={endLatInput} aria-label={m('routeNew.endLatitude')} placeholder={m('routeNew.latPlaceholder')} />
						<input class="coord-input" type="text" inputmode="decimal" bind:value={endLngInput} aria-label={m('routeNew.endLongitude')} placeholder={m('routeNew.lngPlaceholder')} />
						<button type="submit" class="btn btn-sm btn-secondary">{m('routeNew.setEnd')}</button>
					</form>
					{#if endCoordError}
						<p class="coord-error" role="alert">{endCoordError}</p>
					{/if}

					<span class="section-label">{m('routeNew.distance')}</span>
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
					<label class="quiet-roads" title={m('routeNew.quietRoadsHint')}>
						<input type="checkbox" bind:checked={quietRoads} data-testid="quiet-roads-toggle" />
						<span>{m('routeNew.quietRoads')}</span>
					</label>
					{#if builderBusy}
						<button class="btn btn-outline" onclick={() => builder?.cancelGeneration()}>
							{m('routeNew.cancelGenerating')}
						</button>
					{:else}
						<button class="btn btn-secondary" onclick={handleGenerateLoop}>
							{endPoint
								? m('routeNew.generateRoute', { distance: `${targetDisplayValue.toFixed(1)} ${unitLabel}` })
								: m('routeNew.generateLoop', { distance: `${targetDisplayValue.toFixed(1)} ${unitLabel}` })}
						</button>
					{/if}
				</div>
			{/if}

			{#if pickingPoint}
				<div class="pick-hint" role="status">
					{pickingPoint === 'start' ? m('routeNew.pickHintStart') : m('routeNew.pickHintEnd')}
				</div>
			{/if}

			<div class="primary-actions">
				<button
					class="btn btn-primary"
					disabled={!routed || builderBusy}
					onclick={openSaveModal}
				>
					<span class="material-symbols" aria-hidden="true">save</span>
					{m('routeNew.saveRoute')}
				</button>
				<button
					class="btn btn-outline btn-sm"
					disabled={!routed || builderBusy}
					onclick={handleExportGpx}
					title={m('routeNew.exportGpx')}
				>
					GPX
				</button>
				<button
					class="btn btn-outline btn-sm"
					disabled={!routed || builderBusy}
					onclick={handleExportKml}
					title={m('routeNew.exportKml')}
				>
					KML
				</button>
			</div>
		</div>

		<details class="help" bind:open={showHelp}>
			<summary>
				<span class="material-symbols">keyboard</span>
				{m('routeNew.tipsShortcuts')}
			</summary>
			<ul>
				<li><kbd>{m('routeNew.kbdClick')}</kbd> {m('routeNew.tipClickWaypoint')}</li>
				<li><kbd>{m('routeNew.kbdClick')}</kbd> {m('routeNew.tipClickLoop')}</li>
				<li><kbd>{m('routeNew.kbdClick')}</kbd> {m('routeNew.tipClickInsert')}</li>
				<li><kbd>{m('routeNew.kbdDrag')}</kbd> {m('routeNew.tipDrag')}</li>
				<li><kbd>{m('routeNew.kbdRightClick')}</kbd> {m('routeNew.tipRightClick')}</li>
				<li><kbd>{m('routeNew.kbdCtrl')}</kbd>+<kbd>Z</kbd> {m('routeNew.tipUndo')}</li>
				<li><kbd>{m('routeNew.kbdEsc')}</kbd> {m('routeNew.tipEsc')}</li>
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
			ongeneratemismatch={(achievedM, _targetM, largestLoopM) =>
				(generateShortfall = { achievedM, largestLoopM })}
			onrequestclear={handleClear}
		/>

		{#if waypointCount === 0 && !pickingPoint}
			<div class="canvas-empty" role="status">
				<span class="material-symbols">add_location</span>
				<h3>{m('routeNew.canvasEmptyTitle')}</h3>
				<p>{m('routeNew.canvasEmptyPrefix')} <strong>{m('routeNew.canvasEmptyAuto')}</strong> {m('routeNew.canvasEmptySuffix')}</p>
			</div>
		{/if}

		{#if routingError}
			<div
				class="routing-error"
				class:routing-warning={routingErrorSeverity === 'warning'}
				class:routing-error-wide={!!generateShortfall}
				role={routingErrorSeverity === 'warning' ? 'status' : 'alert'}
			>
				<span class="material-symbols">
					{routingErrorSeverity === 'warning' ? 'warning' : 'error'}
				</span>
				<div class="routing-error-text">{routingError}</div>
				<button
					class="routing-error-dismiss"
					aria-label={m('routeNew.dismiss')}
					onclick={() => { routingError = null; generateShortfall = null; }}
				>
					<span class="material-symbols">close</span>
				</button>
				{#if generateShortfall}
					{@const sd = distanceInPreferred(generateShortfall.achievedM)}
					<div class="routing-error-choices">
						<p class="routing-error-choices-prompt">{m('routeNew.loopPoorPrompt')}</p>
						<div class="routing-error-action">
							{#if generateShortfall.largestLoopM}
								{@const ld = distanceInPreferred(generateShortfall.largestLoopM)}
								<button class="btn btn-primary btn-sm" onclick={generateLargestLoop}>
									{m('routeNew.generateLargestLoop', { distance: `${ld.value.toFixed(1)} ${ld.unit}` })}
								</button>
							{/if}
							<button class="btn btn-secondary btn-sm" onclick={useAchievedDistance}>
								{m('routeNew.useThisDistance', { distance: `${sd.value.toFixed(1)} ${sd.unit}` })}
							</button>
							<button class="btn btn-outline btn-sm" onclick={tryDifferentStart}>
								{m('routeNew.tryDifferentStart')}
							</button>
						</div>
					</div>
				{/if}
			</div>
		{/if}
	</main>
		{/snippet}
	</SplitPane>
</div>

<Modal open={showSaveModal} title={m('routeNew.saveModalTitle')} onclose={() => (showSaveModal = false)}>
	<form
		class="save-form"
		onsubmit={(e) => { e.preventDefault(); handleSaveRoute(); }}
	>
		<label class="field">
			<span class="section-label">{m('routeNew.nameLabel')}</span>
			<input
				type="text"
				placeholder={m('routeNew.namePlaceholder')}
				bind:value={routeName}
				required
			/>
		</label>

		<label class="field">
			<span class="section-label">{m('routeNew.descriptionLabel')} <span class="label-hint">{m('routeNew.optionalHint')}</span></span>
			<textarea
				rows="3"
				placeholder={m('routeNew.descriptionPlaceholder')}
				bind:value={routeDescription}
			></textarea>
		</label>

		<div class="save-summary">
			<div>
				<span class="save-summary-value">{distanceDisp.value.toFixed(2)} {distanceDisp.unit}</span>
				<span class="save-summary-label">{m('routeNew.distance')}</span>
			</div>
			<div>
				<span class="save-summary-value">{elevation} m</span>
				<span class="save-summary-label">{m('routeNew.elevation')}</span>
			</div>
			<div>
				<span class="save-summary-value">{mode === 'trail' ? m('routeNew.trail') : m('routeNew.road')}</span>
				<span class="save-summary-label">{m('routeNew.surface')}</span>
			</div>
		</div>

		<label class="visibility">
			<input type="checkbox" bind:checked={isPublic} />
			<span>
				<strong>{m('routeNew.public')}</strong>
				<span class="visibility-hint">{m('routeNew.publicHint')}</span>
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
				{m('routeNew.cancel')}
			</button>
			<button
				type="submit"
				class="btn btn-primary"
				disabled={!canSave || saving}
			>
				{#if saving}
					<span class="btn-spinner" aria-hidden="true"></span>
					{m('routeNew.saving')}
				{:else}
					{m('routeNew.saveRouteModal')}
				{/if}
			</button>
		</div>
	</form>
</Modal>

<ConfirmDialog
	open={showClearConfirm}
	title={m('routeNew.clearConfirmTitle')}
	message={m('routeNew.clearConfirmMessage')}
	confirmLabel={m('routeNew.clearConfirmButton')}
	danger
	onconfirm={() => {
		showClearConfirm = false;
		doClear();
	}}
	oncancel={() => (showClearConfirm = false)}
/>

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
		border-inline-end: 1px solid var(--color-border);
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
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input:focus-visible, textarea:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
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
		border-inline-end: 1px solid var(--color-border);
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

	/* AI route-request box — additive NL input above the manual controls. */
	.ai-request {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding-bottom: var(--space-sm);
		margin-bottom: var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	.ai-request-hint {
		margin: 0;
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		line-height: 1.4;
	}
	.ai-request-form {
		display: flex;
		gap: var(--space-xs);
		align-items: stretch;
	}
	.ai-request-input {
		flex: 1;
		min-inline-size: 0;
	}
	.ai-request-form .btn {
		flex-shrink: 0;
		white-space: nowrap;
	}
	.ai-request-error {
		margin: 0;
		font-size: 0.72rem;
		color: var(--color-danger);
		line-height: 1.4;
	}
	.ai-request-applied {
		padding: var(--space-xs) var(--space-sm);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 22%, transparent);
		border-radius: var(--radius-sm);
	}
	.ai-request-applied-title {
		margin: 0 0 var(--space-2xs);
		font-size: 0.72rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.ai-request-applied-list {
		margin: 0;
		padding-inline-start: 1rem;
		font-size: 0.7rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
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
	.coord-entry {
		display: flex;
		gap: var(--space-xs);
		margin-bottom: var(--space-sm);
	}
	.coord-input {
		inline-size: 4.5rem;
		min-inline-size: 0;
		flex: 1;
		padding: var(--space-2xs) var(--space-xs);
		font-size: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
	}
	.coord-error {
		margin: 0 0 var(--space-sm);
		font-size: 0.72rem;
		color: var(--color-danger);
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
		text-align: end;
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

	.quiet-roads {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.8rem;
		color: var(--color-text);
		cursor: pointer;
	}
	.quiet-roads input[type="checkbox"] {
		width: auto;
		flex-shrink: 0;
		accent-color: var(--color-primary);
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
		inset-inline-start: var(--space-md);
		z-index: 5;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		text-align: start;
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
		flex-wrap: wrap;
		gap: var(--space-sm);
		max-width: 28rem;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		/* WCAG AA: white on --color-danger was 3.06:1 in dark; -strong is 6.06:1. */
		background: var(--color-danger-strong);
		color: white;
		box-shadow: var(--shadow-lg);
		font-size: 0.9rem;
	}
	/* Partial-success warning — route is drawn but some OSRM segments
	   dropped. Visually distinct from a hard failure so the user
	   doesn't think their work was lost. */
	.routing-error.routing-warning {
		/* WCAG AA: white on --color-warning was 2.05:1; -strong is 5.42:1. */
		background: var(--color-warning-strong, #9A5B0A);
	}
	/* The 3-way loop-poor choice needs room for up to three action buttons. */
	.routing-error-wide {
		max-width: 34rem;
	}
	.routing-error-text {
		flex: 1;
		line-height: 1.35;
	}
	/* The loop-poor 3-way choice drops to its own full-width row under the
	   message (the banner is flex-wrap). */
	.routing-error-choices {
		flex: 0 0 100%;
	}
	.routing-error-choices-prompt {
		margin: 0 0 var(--space-sm);
		line-height: 1.35;
	}
	.routing-error-action {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
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
			border-inline-end: none;
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
