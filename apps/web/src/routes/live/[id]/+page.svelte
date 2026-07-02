<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { formatPace, formatDistance } from '$lib/core/mock-data';
	import { formatDuration } from '$lib/format/time';
	import { fetchRouteById, fetchRouteMarkers } from '$lib/core/data';
	import { buildRoadbook, type RoadbookLeg } from '$lib/routes/roadbook';
	import { distanceAlongRoute, type RouteWaypoint } from '$lib/routes/route_geometry';
	import { nextCutoffEta } from '$lib/runs/live_cutoff_eta';
	import { supabase } from '$lib/core/supabase';
	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	import {
		isLiveHubConfigured,
		fetchLiveSnapshot,
		openLiveWebSocket,
		type LivePing,
	} from '$lib/runs/live_hub';
	import { runnerHandle, shouldRevealDisplayName } from '$lib/social/runner_handle';
	import { freshnessFor, type Freshness } from '$lib/runs/live_freshness';
	import { m } from '$lib/i18n/store.svelte';

	// audit/cookie-consent (2026-05-25): MapTiler tile fetches log
	// requester IPs per tile, so initialising MapLibre before consent
	// has been recorded leaks an EU visitor's IP to a US sub-processor
	// before any banner action. The live spectator page is anon-
	// accessible, so we gate the map init either on the global consent
	// state (banner-accepted) or on an explicit "Load map" click here.
	let mapConsented = $state(false);

	let { data } = $props();

	let mapContainer = $state<HTMLDivElement>();
	let map: maplibregl.Map;
	let runnerMarker: maplibregl.Marker;
	let stopResizeWatch: (() => void) | null = null;
	let elapsed = $state(0);
	let distance = $state(0);
	let currentPace = $state('--:--');
	let runnerName = $state<string | null>(null);
	type Status = 'connecting' | 'live' | 'finished' | 'demo' | 'error' | 'not-found';
	let status = $state<Status>('connecting');
	let demoTicker: ReturnType<typeof setInterval> | null = null;
	// Demo-mode animation state. `demoActive` gates the Page Visibility
	// pause: once the demo is running, we stop the interval while the
	// tab is backgrounded and restart it on return so a multi-day
	// spectator tab doesn't animate (and re-render the map) every 3 s
	// off-screen. `demoAngle` is module-scope so it survives a pause.
	let demoActive = false;
	let demoAngle = 0;
	let onVisibilityChange: (() => void) | null = null;
	// Freshness: the ms timestamp of the last ping we rendered, plus a
	// once-a-second clock so "updated N ago" / the stale badge recompute
	// even while no new ping arrives. Without this a runner who lost
	// signal stays a fresh green "LIVE" dot forever (the spectator /
	// SAR staleness-honesty bug).
	let lastPingAtMs = $state<number | null>(null);
	let nowMs = $state(Date.now());
	let freshnessTicker: ReturnType<typeof setInterval> | null = null;
	const freshness = $derived(lastPingAtMs != null ? freshnessFor(lastPingAtMs, nowMs) : null);
	const isStale = $derived(freshness?.stale ?? false);
	// True once the latest rendered ping carries the privacy-zone
	// `coarse` flag (migration 20270121_001): a ~1 km-coarsened in-zone
	// last-seen fix the DB keeps for SAR. When set, the dot is rendered
	// as approximate and a "last seen near here" badge is shown — a SAR
	// watcher must not read the dot as a precise current position.
	let lastPingCoarse = $state(false);

	// Next cut-off card state. Only wired when the run links a PUBLIC route
	// (public_runs nulls route_id otherwise) that carries >=1 cutoff marker.
	// `routeWaypoints` + `cutoffLegs` are seeded once on load; the runner's
	// latest position + a small recent-pings buffer drive the live ETA.
	let routeWaypoints = $state<RouteWaypoint[]>([]);
	let cutoffLegs = $state<RoadbookLeg[]>([]);
	let latestPosition = $state<{ lat: number; lng: number } | null>(null);
	let recentPings = $state<Array<{ distance_m: number; elapsed_s: number }>>([]);
	const hasCutoffRoute = $derived(cutoffLegs.some((l) => l.cutoff != null));

	const recentPaceSecPerKm = $derived.by((): number | null => {
		if (recentPings.length < 2) return null;
		const oldest = recentPings[0];
		const newest = recentPings[recentPings.length - 1];
		const dDist = newest.distance_m - oldest.distance_m;
		const dElapsed = newest.elapsed_s - oldest.elapsed_s;
		if (dDist <= 0) return null;
		return dElapsed / (dDist / 1000);
	});

	const distAlongRouteM = $derived.by((): number | null => {
		if (!latestPosition || routeWaypoints.length < 2) return null;
		return distanceAlongRoute(latestPosition, routeWaypoints);
	});

	const eta = $derived(
		hasCutoffRoute
			? nextCutoffEta({
					distAlongRouteM: distAlongRouteM ?? 0,
					elapsedS: elapsed,
					recentPaceSecPerKm,
					legs: cutoffLegs,
					stale: isStale,
				})
			: null,
	);
	let realtimeChannel: ReturnType<typeof supabase.channel> | null = null;
	// Go live-hub teardown handle. Held alongside `realtimeChannel`
	// because exactly one of the two transports is active per session
	// — `subscribeLive` picks based on `isLiveHubConfigured()`.
	let liveHubHandle: { close: () => void } | null = null;
	// Synchronously-readable mirror of the viewer's current Supabase
	// access token. Seeded from `getSession()` and refreshed by
	// `onAuthStateChange` (which fires on `TOKEN_REFRESHED`), so the
	// live-hub reconnect loop — which needs a token synchronously on
	// each attempt — always sees the live JWT rather than a stale one.
	// /audit/livehub May 2026 C1.
	let currentAccessToken: string | null = null;
	let authSub: { unsubscribe: () => void } | null = null;

	// Runner position + completed trace. Held as mutable module-scope
	// state rather than `$state` because MapLibre mutates the GeoJSON
	// source directly and the chrome doesn't need to re-render on every
	// tick (only the stat strip below does).
	const traceCoords: [number, number][] = [];

	// Used to compute the initial map centre when the first ping arrives
	// so the view snaps to the runner regardless of geography.
	let centred = false;

	// Defaults that match the simulation: Melbourne CBD so the map isn't
	// blank during `connecting` or `demo` with no credentials.
	const fallbackLat = -37.8136;
	const fallbackLng = 144.9631;

	function initials(name: string): string {
		const parts = name.trim().split(/\s+/).slice(0, 2);
		return parts.map((p) => p.charAt(0).toUpperCase()).join('') || '?';
	}

	function freshnessText(f: Freshness): string {
		switch (f.bucket) {
			case 'now':
				return m('live.updatedNow');
			case 'seconds':
				return m('live.updatedSeconds', { n: f.value });
			case 'minutes':
				return m('live.updatedMinutes', { n: f.value });
			case 'hours':
				return m('live.updatedHours', { n: f.value });
			case 'days':
				return m('live.updatedDays', { n: f.value });
		}
	}

	function ensureMarker(lat: number, lng: number) {
		if (!map) return;
		if (!runnerMarker) {
			const el = document.createElement('div');
			el.className = 'runner-dot';
			runnerMarker = new maplibregl.Marker({ element: el })
				.setLngLat([lng, lat])
				.addTo(map);
		} else {
			runnerMarker.setLngLat([lng, lat]);
		}
		// The coarse last-seen fix renders with a distinct hollow ring so
		// it reads as approximate next to the solid live dot.
		runnerMarker.getElement().classList.toggle('coarse', lastPingCoarse);
	}

	function pushPing(ping: {
		lat: number;
		lng: number;
		distance_m?: number | null;
		elapsed_s?: number | null;
		sent_at_ms?: number | null;
		at?: string | null;
		coarse?: boolean | null;
	}) {
		// Stamp freshness from the ping's own clock — `sent_at_ms` on the
		// Go-hub path, the `at` column on the Supabase path. Finite-guard
		// so a malformed `at` doesn't reset the age to NaN.
		const ts = ping.sent_at_ms ?? (ping.at != null ? Date.parse(ping.at) : NaN);
		if (Number.isFinite(ts)) lastPingAtMs = ts as number;
		lastPingCoarse = ping.coarse === true;
		traceCoords.push([ping.lng, ping.lat]);
		// Stat-strip values update regardless of map readiness — a slow or
		// failing map style fetch (e.g. MapTiler down, missing key) must
		// not stall the LIVE badge or the distance / elapsed / pace
		// readout. Map-touching calls below are individually guarded.
		if (ping.distance_m != null) distance = ping.distance_m;
		if (ping.elapsed_s != null) elapsed = ping.elapsed_s;
		if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);

		// Feed the next-cut-off card: latest fix + a 5-ping recent buffer
		// (only pings that carry both odometer fields, so the pace delta is
		// real). Reassigned (not mutated) so the $derived ETA recomputes.
		latestPosition = { lat: ping.lat, lng: ping.lng };
		if (ping.distance_m != null && ping.elapsed_s != null) {
			recentPings = [
				...recentPings,
				{ distance_m: ping.distance_m, elapsed_s: ping.elapsed_s },
			].slice(-5);
		}

		if (!map) return;
		ensureMarker(ping.lat, ping.lng);
		if (!centred) {
			map.jumpTo({ center: [ping.lng, ping.lat], zoom: 15 });
			centred = true;
		} else {
			map.panTo([ping.lng, ping.lat], { animate: true });
		}
		const source = map.getSource('live-trace') as maplibregl.GeoJSONSource | undefined;
		source?.setData({
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: traceCoords },
		});
	}

	async function hydrateBacklog() {
		if (isLiveHubConfigured()) {
			// On the Go-hub path the full ping history is replayed over
			// the WS on connect (server.go `handleSubscribe` sends up to
			// HistoryRingSize buffered pings before streaming new ones),
			// so the trace is populated by `subscribeLive` — we must NOT
			// also seed a point from the snapshot or the first point
			// double-renders. The snapshot is fetched only to decide
			// whether the room has any data yet, which gates the demo
			// fallback. Persona round-5 runner-ultra: a crew opening the
			// page mid-run sees the whole traversed course, not one dot.
			// Forward the viewer's Supabase JWT so the Go authorizer
			// accepts the request on private runs (public runs work
			// either way). /audit/livehub May 2026 C1.
			const sess = (await supabase.auth.getSession()).data.session;
			const snap = await fetchLiveSnapshot(data.id, sess?.access_token ?? null);
			return snap != null;
		}
		const { data: rows, error } = await supabase
			.from('live_run_pings')
			.select('lat, lng, distance_m, elapsed_s, at, coarse')
			.eq('run_id', data.id)
			.order('at', { ascending: true });
		if (error || !rows || rows.length === 0) return false;
		for (const row of rows) pushPing(row);
		return true;
	}

	function subscribeLive() {
		// Privacy-zone trust contract: pings are rendered verbatim. The
		// broadcaster's privacy zones are NOT fetched here (doing so
		// would defeat the purpose — anyone watching a public live run
		// could read off the broadcaster's home / work coordinates).
		// On the Supabase Realtime path, the single line of defence is
		// the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger from
		// migration `20260618_001_clip_live_run_pings_to_privacy_zones.sql`,
		// which silently drops in-zone pings before they reach Realtime.
		// Pinned by `apps/backend/supabase/tests/rls_live_run_pings_trigger_test.sql`
		// so a future migration can't silently undo it. On the Go
		// live-hub path, the broadcaster (LiveBroadcaster) must apply
		// the same clip before it pushes to the hub — server-side
		// clipping is on the migration list (followups #13).
		if (isLiveHubConfigured()) {
			// JWT goes on the WS upgrade URL as `?token=…`; browsers can't
			// set Authorization headers on a WS upgrade. /audit/livehub C1.
			// `getToken` re-reads `currentAccessToken` on every (re)connect,
			// so a reconnect after the original token expires (~1 h)
			// authorizes with the refreshed JWT instead of looping on a
			// stale 403.
			liveHubHandle = openLiveWebSocket(data.id, {
				getToken: () => currentAccessToken,
				onPing: (p: LivePing) => {
					pushPing({
						lat: p.lat,
						lng: p.lng,
						distance_m: p.distance_m ?? null,
						elapsed_s: p.elapsed_s ?? null,
						sent_at_ms: p.sent_at_ms ?? null,
						coarse: p.coarse ?? null,
					});
					if (status !== 'live') status = 'live';
				},
				onStatus: (s) => {
					if (s === 'closed' && status === 'live') {
						status = 'connecting';
					}
				},
			});
			return;
		}
		realtimeChannel = supabase
			.channel(`live-run:${data.id}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'live_run_pings',
					filter: `run_id=eq.${data.id}`,
				},
				(payload) => {
					const row = payload.new as {
						lat: number;
						lng: number;
						distance_m: number | null;
						elapsed_s: number | null;
						at: string | null;
						coarse: boolean | null;
					};
					pushPing(row);
					if (status !== 'live') status = 'live';
				},
			)
			.subscribe();
	}

	function startDemoTicker() {
		if (demoTicker) return;
		demoTicker = setInterval(() => {
			demoAngle += 0.02;
			elapsed += 3;
			distance += 12 + Math.random() * 5;
			const lng = fallbackLng + Math.cos(demoAngle) * 0.005;
			const lat = fallbackLat + Math.sin(demoAngle) * 0.003;
			pushPing({ lat, lng, distance_m: distance, elapsed_s: elapsed, sent_at_ms: Date.now() });
		}, 3000);
	}

	function stopDemoTicker() {
		if (demoTicker) {
			clearInterval(demoTicker);
			demoTicker = null;
		}
	}

	function startDemo() {
		status = 'demo';
		if (map) {
			ensureMarker(fallbackLat, fallbackLng);
			map.jumpTo({ center: [fallbackLng, fallbackLat], zoom: 15 });
		}
		demoActive = true;
		demoAngle = 0;
		// Pause the animation while the tab is hidden — a backgrounded
		// multi-day spectator tab shouldn't burn CPU + re-render the map
		// every 3 s with no one watching. Resume on return.
		if (typeof document !== 'undefined' && !onVisibilityChange) {
			onVisibilityChange = () => {
				if (!demoActive) return;
				if (document.hidden) stopDemoTicker();
				else startDemoTicker();
			};
			document.addEventListener('visibilitychange', onVisibilityChange);
		}
		if (typeof document !== 'undefined' && document.hidden) return;
		startDemoTicker();
	}

	type VisibleRun = {
		user_id: string;
		started_at: string;
		duration_s: number;
		distance_m: number;
		route_id: string | null;
	};
	let visibleRun: VisibleRun | null = null;

	async function ensureRunIsVisible(): Promise<boolean> {
		// Visibility check: the spectator surface is a public-broadcast
		// page, so the visible-runs set is exactly what `public_runs`
		// exposes (decisions §33, migration 20260626_001).
		const { data: row, error } = await supabase
			.from('public_runs')
			.select('id, user_id, started_at, duration_s, distance_m, route_id')
			.eq('id', data.id)
			.maybeSingle();
		if (error || !row) {
			status = 'not-found';
			return false;
		}
		visibleRun = {
			user_id: row.user_id as string,
			started_at: row.started_at as string,
			duration_s: Number(row.duration_s ?? 0),
			distance_m: Number(row.distance_m ?? 0),
			route_id: (row.route_id as string | null) ?? null,
		};
		if (row.user_id) {
			// `public_profile_by_id` SECURITY DEFINER RPC — replaces
			// the old anon SELECT on the public_profiles view, which
			// PostgREST exposed with bulk filter+pagination. Anon
			// callers can now only look up a profile they already know
			// the uuid for (which we do, from the public_runs row
			// above). See migration 20260530_002.
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: row.user_id })
				.maybeSingle();
			const dn =
				(profile as { display_name?: string | null } | null)?.display_name ??
				null;

			// Persona-hunt Round 3 finding Privacy #5. Only reveal the
			// display_name to friends (one-way follow in either
			// direction, or the runner themselves). Strangers + anon
			// see the anonymous `runnerHandle` instead so sharing a
			// live URL doesn't unmask the runner to anyone with the
			// link. Two follow-edge probes — both small index lookups
			// — gate the reveal.
			const viewerId = (await supabase.auth.getSession()).data.session?.user
				?.id ?? null;
			let viewerFollowsRunner = false;
			let runnerFollowsViewer = false;
			if (viewerId && viewerId !== row.user_id) {
				const [vfr, rfv] = await Promise.all([
					supabase
						.from('user_follows')
						.select('follower_id')
						.eq('follower_id', viewerId)
						.eq('followee_id', row.user_id)
						.maybeSingle(),
					supabase
						.from('user_follows')
						.select('follower_id')
						.eq('follower_id', row.user_id)
						.eq('followee_id', viewerId)
						.maybeSingle(),
				]);
				viewerFollowsRunner = vfr.data != null;
				runnerFollowsViewer = rfv.data != null;
			}
			const reveal = shouldRevealDisplayName({
				viewerUserId: viewerId,
				runnerUserId: row.user_id as string,
				viewerFollowsRunner,
				runnerFollowsViewer,
			});
			runnerName = reveal && dn ? dn : runnerHandle(row.user_id as string);
		}
		return true;
	}

	// Load the linked public route + its course markers and build the
	// roadbook legs ONCE, so the live ETA can re-project against a stable
	// cutoff timeline. The roadbook's cutoff `limitElapsedS` is independent
	// of `goalSeconds`, so any positive goal works — we use the run's saved
	// duration (the broadcaster's plan) and fall back to the elapsed-so-far
	// or one hour. Start clock is the run's local start time. Auxiliary —
	// wrapped so a failed route / marker fetch never disturbs the core
	// spectator surface (layered-resilience contract).
	async function loadRouteCutoffs(run: VisibleRun) {
		if (!run.route_id) return;
		try {
			const [route, markers] = await Promise.all([
				fetchRouteById(run.route_id),
				fetchRouteMarkers(run.route_id),
			]);
			const waypoints = (route?.waypoints ?? []) as RouteWaypoint[];
			if (waypoints.length < 2) return;
			const start = new Date(run.started_at);
			const startClockMin = Number.isFinite(start.getTime())
				? start.getHours() * 60 + start.getMinutes()
				: null;
			const roadbook = buildRoadbook(
				waypoints.map((w) => ({
					lat: w.lat,
					lng: w.lng,
					ele: w.elevation_m ?? null,
				})),
				markers.map((mk) => ({
					position_m: (mk as { position_m: number | null }).position_m ?? null,
					kind: mk.kind,
					label: mk.label,
					meta: mk.meta,
				})),
				{
					goalSeconds: run.duration_s || elapsed || 3600,
					startClockMin,
					model: 'even',
				},
			);
			routeWaypoints = waypoints;
			cutoffLegs = roadbook.legs;
		} catch (err) {
			console.warn('next cut-off card: route load failed', err);
		}
	}

	// A run is treated as already finished if its saved duration places
	// its end >2 minutes in the past. The 2 min slack covers the gap
	// between the last ping and the recorder posting the final row +
	// any clock skew. While finished, the spectator surface freezes on
	// the saved totals and skips the demo / realtime paths — opening a
	// stale share link to a completed run should read "Finished" with
	// final stats, not loop forever on "Connecting…" or "LIVE".
	function runIsFinished(r: VisibleRun): boolean {
		if (!r.duration_s || r.duration_s <= 0) return false;
		const endedMs = new Date(r.started_at).getTime() + r.duration_s * 1000;
		return Number.isFinite(endedMs) && endedMs < Date.now() - 2 * 60 * 1000;
	}

	onMount(() => {
		// Honour the global banner choice. The "Load map" button below
		// is the per-page acceptance path when the banner hasn't been
		// answered yet.
		if (hasAcceptedConsent()) mapConsented = true;
		// Drives the freshness readout / stale-badge transition while no
		// new ping arrives.
		freshnessTicker = setInterval(() => {
			nowMs = Date.now();
		}, 1000);
		// Seed + keep the synchronous token mirror current. The auth
		// listener fires on TOKEN_REFRESHED, so the next reconnect picks
		// up the rotated JWT. /audit/livehub May 2026 C1.
		authSub = supabase.auth.onAuthStateChange((_event, session) => {
			currentAccessToken = session?.access_token ?? null;
		}).data.subscription;
		(async () => {
			currentAccessToken =
				(await supabase.auth.getSession()).data.session?.access_token ?? null;
			if (!(await ensureRunIsVisible())) return;
			if (visibleRun) void loadRouteCutoffs(visibleRun);
			if (visibleRun && runIsFinished(visibleRun)) {
				distance = visibleRun.distance_m;
				elapsed = visibleRun.duration_s;
				if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);
				// Best-effort backlog hydrate so the map still gets the
				// trace shape, but don't open realtime / demo — the run
				// is over.
				await hydrateBacklog();
				status = 'finished';
				return;
			}
			const hadBacklog = await hydrateBacklog();
			subscribeLive();
			if (hadBacklog) {
				status = 'live';
			} else {
				setTimeout(() => {
					if (status === 'connecting' && traceCoords.length === 0) {
						startDemo();
					}
				}, 5000);
			}
		})();

		if (mapConsented) initMap();
	});

	function loadMapNow() {
		mapConsented = true;
		// $effect below would normally pick this up, but the map
		// container only mounts when `mapConsented` flips, so we wait
		// one microtask for the DOM to render before initialising.
		queueMicrotask(initMap);
	}

	function initMap() {
		if (map || !mapContainer) return;
		map = new maplibregl.Map({
			container: mapContainer,
			// Honours PUBLIC_TILE_STYLE_URL override the same way every
			// other map surface does (decisions.md § 68). `prefersDark`
			// isn't read here — the live spectator page renders dark
			// the same way the run-detail map does (the helper handles
			// the OS-preference path internally).
			style: mapStyleUrlFromEnv(
				PUBLIC_MAPTILER_KEY,
				typeof window !== 'undefined' &&
					window.matchMedia('(prefers-color-scheme: dark)').matches,
			),
			center: [fallbackLng, fallbackLat],
			zoom: 15,
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		stopResizeWatch = watchMapResize(mapContainer, map);

		map.on('load', () => {
			map.addSource('live-trace', {
				type: 'geojson',
				data: {
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: traceCoords },
				},
			});
			map.addLayer({
				id: 'live-trace-line',
				type: 'line',
				source: 'live-trace',
				paint: { 'line-color': '#2C5F6E', 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			if (traceCoords.length > 0) {
				const last = traceCoords[traceCoords.length - 1];
				ensureMarker(last[1], last[0]);
				map.jumpTo({ center: [last[0], last[1]], zoom: 15 });
				centred = true;
			}
		});
	}

	onDestroy(() => {
		demoActive = false;
		stopDemoTicker();
		if (onVisibilityChange && typeof document !== 'undefined') {
			document.removeEventListener('visibilitychange', onVisibilityChange);
			onVisibilityChange = null;
		}
		if (freshnessTicker) clearInterval(freshnessTicker);
		if (realtimeChannel) supabase.removeChannel(realtimeChannel);
		liveHubHandle?.close();
		authSub?.unsubscribe();
		stopResizeWatch?.();
		map?.remove();
	});
</script>

<svelte:head>
	<title>{m('live.pageTitle')}</title>
	<meta name="description" content={m('live.pageDescription')} />
	<meta property="og:title" content={m('live.pageTitle')} />
	<meta property="og:description" content={m('live.pageDescription')} />
	<meta property="og:type" content="website" />
</svelte:head>

<!-- Public page — no sidebar, no auth required -->
<div class="live-page">
	<header class="live-header">
		<a href="/" class="live-logo">
			<img src="/logo-mark.svg" alt="" class="live-logo-mark" />
			Threkir
		</a>
		<div
			class="live-badge"
			class:active={status === 'live' && !isStale}
			class:stale={status === 'live' && isStale}
			class:demo={status === 'demo'}
			class:finished={status === 'finished'}
			class:not-found={status === 'not-found'}
		>
			{#if status === 'connecting'}
				<span class="badge-spinner" aria-hidden="true"></span>
				{m('live.badgeConnecting')}
			{:else if status === 'live'}
				{#if isStale}
					{m('live.badgeStale')}
				{:else}
					<span class="pulse-dot"></span> {m('live.badgeLive')}
				{/if}
			{:else if status === 'demo'}
				{m('live.badgeDemo')}
			{:else if status === 'finished'}
				{m('live.badgeFinished')}
			{:else if status === 'not-found'}
				{m('live.badgeNotBroadcasting')}
			{:else}
				{m('live.badgeConnectionLost')}
			{/if}
		</div>
		{#if status === 'live' && lastPingCoarse}
			<span class="approx-badge" data-testid="coarse-badge">
				<span class="material-symbols" aria-hidden="true">location_searching</span>
				{m('live.approximateBadge')}
			</span>
		{/if}
	</header>

	{#if status === 'not-found'}
		<div class="live-empty">
			<div class="live-empty-icon" aria-hidden="true">
				<span class="material-symbols">satellite_alt</span>
			</div>
			<h1>{m('live.notFoundTitle')}</h1>
			<p>
				{m('live.notFoundBody')}
			</p>
			<a href="/" class="btn btn-primary">{m('live.backToThrekir')}</a>
		</div>
	{:else}
		<section class="live-strip" aria-label={m('live.liveStatusAria')}>
			<div class="live-runner">
				<span class="avatar" aria-hidden="true">{initials(runnerName ?? 'R')}</span>
				<div class="live-runner-text">
					<span class="live-runner-name">{runnerName ?? m('live.anonymousRunner')}</span>
					<span class="live-runner-sub">
						{#if status === 'connecting'}
							{m('live.subWaitingFirstPing')}
						{:else if status === 'demo'}
							{m('live.subSynthesisedDemo')}
						{:else if status === 'live'}
							{#if lastPingCoarse}
								{m('live.approximateSub')}
							{:else if freshness}
								{freshnessText(freshness)}
							{:else}
								{m('live.subLiveFromDevice')}
							{/if}
						{:else if status === 'finished'}
							{m('live.subRunFinished')}
						{:else}
							{m('live.subReconnecting')}
						{/if}
					</span>
				</div>
			</div>
			<div class="live-stats" role="group" aria-label={m('live.liveStatsAria')}>
				<div class="live-stat">
					<span class="live-stat-value">{formatDistance(distance)}</span>
					<span class="live-stat-label">{m('live.statDistance')}</span>
				</div>
				<div class="live-stat">
					<span class="live-stat-value">{formatDuration(elapsed)}</span>
					<span class="live-stat-label">{m('live.statElapsed')}</span>
				</div>
				<div class="live-stat">
					<span class="live-stat-value">{currentPace}</span>
					<span class="live-stat-label">{m('live.statPace')}</span>
				</div>
			</div>
		</section>

			{#if hasCutoffRoute && eta?.checkpoint}
				<section
					class="cutoff-card"
					class:on={eta.status === 'on'}
					class:tight={eta.status === 'tight'}
					class:behind={eta.status === 'behind'}
					aria-label={m('live.cutoffTitle')}
				>
					<div class="cutoff-head">
						<span class="cutoff-title">{m('live.cutoffTitle')}</span>
						<span class="cutoff-checkpoint">{eta.checkpoint.label}</span>
					</div>
					<div class="cutoff-body">
						<div class="cutoff-metrics">
							<span class="cutoff-togo"
								>{m('live.cutoffToGo', { d: formatDistance(eta.distanceToM) })}</span
							>
							{#if eta.status !== 'unknown' && eta.projectedArrivalElapsedS != null}
								<span class="cutoff-eta"
									>{m('live.cutoffEta', {
										t: formatDuration(eta.projectedArrivalElapsedS),
									})}</span
								>
							{/if}
						</div>
						{#if eta.status === 'unknown'}
							<span class="cutoff-waiting">{m('live.cutoffWaitingSignal')}</span>
						{:else if eta.marginS != null}
							<span class="cutoff-chip">
								{#if eta.status === 'behind'}
									{m('live.cutoffBehind', { n: formatDuration(Math.abs(eta.marginS)) })}
								{:else}
									{m('live.cutoffAhead', { n: formatDuration(Math.abs(eta.marginS)) })}
								{/if}
							</span>
						{/if}
					</div>
				</section>
			{/if}

		<div class="live-map-wrap">
			{#if mapConsented}
				<div class="live-map" bind:this={mapContainer}></div>
				{#if status === 'connecting'}
					<div class="map-veil" aria-hidden="true">
						<div class="map-veil-card">
							<span class="badge-spinner" aria-hidden="true"></span>
							<p>{m('live.waitingToStartBroadcasting')}</p>
						</div>
					</div>
				{/if}
			{:else}
				<!--
					audit/cookie-consent (2026-05-25): MapTiler logs the
					requester IP per tile fetch. Anonymous visitors on a
					shared-link page must opt in explicitly before the
					map mounts (ePrivacy / GDPR). A "Load map" tap is the
					affirmative act that satisfies the disclosure.
				-->
				<div class="map-consent-veil">
					<div class="map-consent-card">
						<h2>{m('live.consentTitle')}</h2>
						<p>
							{m('live.consentBodyPrefix')}<strong>MapTiler</strong>{m('live.consentBodyMid')}<strong
								>{m('live.loadMap')}</strong
							>{m('live.consentBodyBeforeLink')}<a href="/cookie-notice">{m('live.consentCookieNoticeLink')}</a>{m('live.consentBodySuffix')}
						</p>
						<button type="button" class="btn btn-primary" onclick={loadMapNow}>
							{m('live.loadMap')}
						</button>
					</div>
				</div>
			{/if}
		</div>
	{/if}
</div>

<style>
	.live-page {
		display: flex;
		flex-direction: column;
		height: 100vh;
		background: var(--color-bg);
	}

	.live-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.live-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		text-decoration: none;
	}
	.live-logo-mark {
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-md);
		display: block;
		object-fit: cover;
	}

	.live-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-xs) var(--space-md);
		border-radius: 9999px;
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
	}

	.live-badge.active {
		background: var(--color-success-light);
		color: var(--color-success);
		border-color: color-mix(in srgb, var(--color-success) 35%, transparent);
	}

	.live-badge.demo,
	.live-badge.stale {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		border-color: color-mix(in srgb, var(--color-warning) 35%, transparent);
	}

	.live-badge.not-found {
		background: var(--color-danger-light);
		color: var(--color-danger);
		border-color: color-mix(in srgb, var(--color-danger) 35%, transparent);
	}

	.live-badge.finished {
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		border-color: var(--color-border);
	}

	.pulse-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--color-success);
		animation: pulse 1.5s ease-in-out infinite;
	}
	.badge-spinner {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		border: 2px solid currentColor;
		border-top-color: transparent;
		animation: spin 0.9s linear infinite;
		display: inline-block;
	}
	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.3; }
	}
	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	.live-empty {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		padding: var(--space-2xl) var(--space-xl);
		gap: var(--space-md);
		color: var(--color-text-secondary);
	}

	.live-empty-icon {
		width: 4rem;
		height: 4rem;
		border-radius: 50%;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: center;
		margin-bottom: var(--space-xs);
	}
	.live-empty-icon .material-symbols {
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.live-empty h1 {
		font-size: 1.6rem;
		color: var(--color-text);
		margin: 0;
		font-weight: 800;
	}

	.live-empty p {
		max-width: 32rem;
		margin: 0;
		line-height: 1.5;
	}

	.live-strip {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-lg);
		padding: var(--space-md) var(--space-xl);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		flex-wrap: wrap;
		/* Container query target — lets the inner stats row adapt
		 * to the strip's actual width regardless of viewport
		 * (forward-compat if the page ever gains a side panel). */
		container-type: inline-size;
		container-name: live-strip;
	}

	.live-runner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		min-width: 0;
	}
	.avatar {
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 50%;
		background: var(--color-primary-light);
		color: var(--color-primary);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 800;
		font-size: 0.95rem;
		letter-spacing: 0.02em;
		flex-shrink: 0;
	}
	.live-runner-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.live-runner-name {
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.live-runner-sub {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.live-stats {
		display: flex;
		gap: var(--space-2xl);
		align-items: center;
	}

	.live-stat {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		min-width: 4.5rem;
	}

	.live-stat-value {
		font-size: 1.5rem;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.01em;
		line-height: 1.05;
	}

	.live-stat-label {
		font-size: 0.68rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-weight: 600;
		margin-top: var(--space-2xs);
	}

	@media (max-width: 48rem) {
		.live-strip {
			flex-direction: column;
			align-items: stretch;
			gap: var(--space-md);
		}
		.live-stats {
			justify-content: space-around;
			gap: var(--space-md);
		}
		.live-stat {
			align-items: center;
		}
	}

	/* Container-query mirror of the viewport rule above. Triggers
	 * when the strip itself goes narrow (i.e. parent gives it less
	 * room) even if the viewport is wide. Matches the panel-
	 * polish pattern from /runs/[id] + /routes/[id]. */
	@container live-strip (max-width: 36rem) {
		.live-stat-value {
			font-size: 1.25rem;
		}
		.live-stats {
			gap: var(--space-md);
		}
	}
	@container live-strip (max-width: 28rem) {
		.live-stat {
			min-width: 3rem;
		}
		.live-stat-value {
			font-size: 1.1rem;
		}
		.live-runner-name {
			font-size: 0.9rem;
		}
	}

	.cutoff-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding: var(--space-md) var(--space-xl);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		border-inline-start: 4px solid var(--color-border);
	}
	.cutoff-card.on {
		border-inline-start-color: var(--color-success);
	}
	.cutoff-card.tight {
		border-inline-start-color: var(--color-warning);
	}
	.cutoff-card.behind {
		border-inline-start-color: var(--color-danger);
	}
	.cutoff-head {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.cutoff-title {
		font-size: 0.68rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-weight: 700;
		color: var(--color-text-tertiary);
	}
	.cutoff-checkpoint {
		font-size: 1rem;
		font-weight: 700;
		color: var(--color-text);
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.cutoff-body {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.cutoff-metrics {
		display: flex;
		align-items: baseline;
		gap: var(--space-md);
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
		font-size: 0.92rem;
	}
	.cutoff-togo {
		font-weight: 700;
		color: var(--color-text);
	}
	.cutoff-chip {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2xs) var(--space-md);
		border-radius: 9999px;
		font-size: 0.78rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
	}
	.cutoff-card.on .cutoff-chip {
		background: var(--color-success-light);
		color: var(--color-success);
		border-color: color-mix(in srgb, var(--color-success) 35%, transparent);
	}
	.cutoff-card.tight .cutoff-chip {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		border-color: color-mix(in srgb, var(--color-warning) 35%, transparent);
	}
	.cutoff-card.behind .cutoff-chip {
		background: var(--color-danger-light);
		color: var(--color-danger);
		border-color: color-mix(in srgb, var(--color-danger) 35%, transparent);
	}
	.cutoff-waiting {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		font-style: italic;
	}

	.live-map-wrap {
		flex: 1;
		position: relative;
		min-height: 0;
	}
	.live-map {
		position: absolute;
		inset: 0;
	}
	.map-veil {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		pointer-events: none;
		background: color-mix(in srgb, var(--color-bg) 35%, transparent);
	}
	.map-veil-card {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}
	.map-veil-card p {
		margin: 0;
	}
	.map-consent-veil {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-bg);
		padding: var(--space-md);
	}
	.map-consent-card {
		max-width: 30rem;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-md);
		text-align: start;
	}
	.map-consent-card h2 { margin: 0 0 var(--space-sm); font-size: 1.1rem; }
	.map-consent-card p { margin: 0 0 var(--space-md); line-height: 1.5; color: var(--color-text-secondary); font-size: 0.92rem; }

	:global(.runner-dot) {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--color-primary);
		border: 3px solid var(--color-surface);
		box-shadow: 0 0 0 4px color-mix(in srgb, var(--color-primary) 30%, transparent),
			0 2px 6px rgba(0, 0, 0, 0.3);
	}

	/* Coarse last-seen marker: a hollow amber ring with a wide soft halo,
	 * deliberately distinct from the solid live dot so a SAR watcher reads
	 * it as an approximate ~1 km cell, not a precise current position. */
	:global(.runner-dot.coarse) {
		width: 22px;
		height: 22px;
		background: transparent;
		border-color: var(--color-warning);
		box-shadow: 0 0 0 8px color-mix(in srgb, var(--color-warning) 22%, transparent),
			0 2px 6px rgba(0, 0, 0, 0.3);
	}

	.approx-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		margin-inline-start: var(--space-sm);
		padding: var(--space-xs) var(--space-md);
		border-radius: 9999px;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning);
		border: 1px solid color-mix(in srgb, var(--color-warning) 35%, transparent);
	}
	.approx-badge .material-symbols {
		font-size: 1rem;
	}
</style>
