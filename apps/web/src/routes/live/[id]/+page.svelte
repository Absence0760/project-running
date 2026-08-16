<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from '$lib/routes/maplibre';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { basemapIsDarkFromEnv, mapStyleUrlFromEnv } from '$lib/routes/map-style.svelte';
	import { mapLiveLine } from '$lib/routes/basemap_contrast';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { formatPace, formatDistance } from '$lib/core/mock-data';
	import { formatDuration } from '$lib/format/time';
	import { fetchRouteById, fetchRouteMarkers, setRunExpectedReturn } from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { buildRoadbook, type RoadbookLeg } from '$lib/routes/roadbook';
	import {
		distanceAlongRoute,
		polylineLengthMetres,
		type RouteWaypoint,
	} from '$lib/routes/route_geometry';
	import { nextCutoffEta } from '$lib/runs/live_cutoff_eta';
	import { supabase } from '$lib/core/supabase';
	import { TABLES } from '$lib/core/schema';
	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	import {
		isLiveHubConfigured,
		fetchLiveSnapshot,
		openLiveWebSocket,
		type LivePing,
	} from '$lib/runs/live_hub';
	import { runnerHandle, shouldRevealDisplayName } from '$lib/social/runner_handle';
	import { freshnessFor, liveElapsedS, type Freshness } from '$lib/runs/live_freshness';
	import { motionFor } from '$lib/safety/live_motion';
	import { isFinishedStale, statusAfterHydrate } from '$lib/runs/live_spectator_status';
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
	// Owner-only "not back by X" escalation override. Only the run owner
	// viewing their own in-progress broadcast can set it; the RPC re-checks
	// ownership + in_progress, so this is a convenience gate, not the guard.
	let isOwner = $state(false);
	let expectedReturnIso = $state<string | null>(null);
	let expectedReturnInput = $state('');
	let savingReturn = $state(false);
	const expectedReturnDisplay = $derived(
		expectedReturnIso
			? new Date(expectedReturnIso).toLocaleString(undefined, {
					dateStyle: 'medium',
					timeStyle: 'short',
				})
			: '',
	);
	type Status = 'connecting' | 'live' | 'finished' | 'error' | 'not-found';
	let status = $state<Status>('connecting');
	// Freshness: the ms timestamp of the last ping we rendered, plus a
	// once-a-second clock so "updated N ago" / the stale badge recompute
	// even while no new ping arrives. Without this a runner who lost
	// signal stays a fresh green "LIVE" dot forever (the spectator /
	// SAR staleness-honesty bug).
	let lastPingAtMs = $state<number | null>(null);
	let nowMs = $state(Date.now());
	let freshnessTicker: ReturnType<typeof setInterval> | null = null;
	// Counts freshness ticks so the concluded_at re-check fires ~every 15s
	// (not every second) while live.
	let concludedCheckTick = 0;
	// Flips true on the MapLibre `load` event so the fit-to-trace effect
	// fires once the map is actually ready (not merely consented).
	let mapReady = $state(false);
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
	let recentPings = $state<
		Array<{ distance_m: number; elapsed_s: number; at_ms: number | null }>
	>([]);
	const hasCutoffRoute = $derived(cutoffLegs.some((l) => l.cutoff != null));

	// Two windows over one buffer, deliberately different lengths: pace is
	// the last handful of pings (a live number the cut-off ETA projects
	// from), motion needs an hour to state how long a runner has been
	// standing in the same place.
	const PACE_WINDOW_PINGS = 5;
	const MOTION_BUFFER_MS = 60 * 60 * 1000;
	const MOTION_BUFFER_MAX = 1000;

	const recentPaceSecPerKm = $derived.by((): number | null => {
		const window = recentPings.slice(-PACE_WINDOW_PINGS);
		if (window.length < 2) return null;
		const oldest = window[0];
		const newest = window[window.length - 1];
		const dDist = newest.distance_m - oldest.distance_m;
		const dElapsed = newest.elapsed_s - oldest.elapsed_s;
		if (dDist <= 0) return null;
		return dElapsed / (dDist / 1000);
	});

	const distAlongRouteM = $derived.by((): number | null => {
		if (!latestPosition || routeWaypoints.length < 2) return null;
		return distanceAlongRoute(latestPosition, routeWaypoints);
	});

	// Course progress (0..100) — how far along a linked route the runner is.
	// Only meaningful when the run follows a public route we could load
	// waypoints for; otherwise null and the bar hides.
	const courseProgressPct = $derived.by((): number | null => {
		if (distAlongRouteM == null || routeWaypoints.length < 2) return null;
		const total = polylineLengthMetres(routeWaypoints);
		if (!(total > 0)) return null;
		return Math.max(0, Math.min(100, (distAlongRouteM / total) * 100));
	});

	// `elapsed` only moves when a ping lands, so it freezes the moment the
	// runner drops out of signal. A cut-off deadline does not — advance the
	// race clock by the ping age so a limit that expired during a dead zone
	// actually registers. Distance is deliberately NOT extrapolated: only
	// time that has genuinely passed is added.
	const raceElapsedS = $derived(liveElapsedS(elapsed, freshness?.ageMs ?? null));

	// A runner still pinging from the same spot renders as a fresh LIVE dot
	// and, because the pace delta is zero, drops the pace readout entirely —
	// so "not moving" and "no data" looked the same. State it instead.
	const motion = $derived(
		status === 'live'
			? motionFor({
					samples: recentPings
						.filter((p) => p.at_ms != null)
						.map((p) => ({ distanceM: p.distance_m, atMs: p.at_ms as number })),
					stale: isStale,
				})
			: null,
	);

	// A concluded run has no "next" cut-off — the projection would be a live
	// claim about a runner who has already stopped.
	const eta = $derived(
		hasCutoffRoute && status === 'live'
			? nextCutoffEta({
					distAlongRouteM,
					elapsedS: raceElapsedS,
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

	// Latched on a user drag (or the viewer tracking their own location)
	// so the per-ping follow-cam stops yanking the view back while the
	// viewer explores the course. The re-center button clears it.
	let userPanned = $state(false);

	// Default centre before the first ping arrives so the map isn't
	// blank while `connecting`.
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
			case 'unknown':
				return m('live.updatedUnknown');
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

		// Feed the next-cut-off card + the motion readout: latest fix plus a
		// recent-ping buffer (only pings that carry both odometer fields, so
		// the pace delta is real). Reassigned (not mutated) so the $derived
		// ETA recomputes. Held for an hour so a long stop can be stated as a
		// figure rather than a floor, and hard-capped so a dense backlog
		// replay can't grow it without bound.
		latestPosition = { lat: ping.lat, lng: ping.lng };
		if (ping.distance_m != null && ping.elapsed_s != null) {
			const atMs = Number.isFinite(ts) ? (ts as number) : null;
			const next = [
				...recentPings,
				{ distance_m: ping.distance_m, elapsed_s: ping.elapsed_s, at_ms: atMs },
			].slice(-MOTION_BUFFER_MAX);
			const oldestKeptMs = atMs != null ? atMs - MOTION_BUFFER_MS : null;
			const aged =
				oldestKeptMs == null
					? next
					: next.filter((p) => p.at_ms == null || p.at_ms >= oldestKeptMs);
			// A silence longer than the buffer would age out everything but
			// the newest ping and take the pace readout with it, so never
			// trim below the pace window.
			recentPings =
				aged.length >= PACE_WINDOW_PINGS ? aged : next.slice(-PACE_WINDOW_PINGS);
		}

		if (!map) return;
		ensureMarker(ping.lat, ping.lng);
		if (!centred) {
			map.jumpTo({ center: [ping.lng, ping.lat], zoom: 15 });
			centred = true;
		} else if (!userPanned) {
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
		// Bounded, newest-first — mirrors `fetchRecentRacePings` and the
		// Go-hub's ring replay. A long broadcast (48h retention @ ~5s cadence
		// ≈ 34.5k rows) must not download every row on an anon share-link
		// load, and an ascending fetch would surface the OLDEST 1000 under a
		// PostgREST row cap, freezing the spectator near the run start.
		// Fetch descending + capped, then replay reversed so the newest ping
		// is the last one pushed and wins the trace/pan.
		const { data: rows, error } = await supabase
			.from('live_run_pings')
			.select('lat, lng, distance_m, elapsed_s, at, coarse')
			.eq('run_id', data.id)
			.order('at', { ascending: false })
			.limit(1000);
		if (error || !rows || rows.length === 0) return false;
		for (let i = rows.length - 1; i >= 0; i--) pushPing(rows[i]);
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

	type VisibleRun = {
		user_id: string;
		started_at: string;
		duration_s: number;
		distance_m: number;
		route_id: string | null;
		// Positive terminal marker (migration 20270427_001). Non-null once
		// the recorder concluded the broadcast — the honest finish signal,
		// replacing the started_at + duration_s staleness inference.
		concluded_at: string | null;
	};
	let visibleRun: VisibleRun | null = null;

	async function ensureRunIsVisible(): Promise<boolean> {
		// Visibility check: the spectator surface is a public-broadcast
		// page, so the visible-runs set is exactly what `public_runs`
		// exposes (decisions §33, migration 20260626_001).
		const { data: row, error } = await supabase
			.from('public_runs')
			.select('id, user_id, started_at, duration_s, distance_m, route_id, concluded_at')
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
			concluded_at: (row.concluded_at as string | null) ?? null,
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

			isOwner = viewerId != null && viewerId === row.user_id;
			if (isOwner) {
				// The owner can read their own run row (RLS), so seed the
				// current override — public_runs doesn't carry metadata.
				const { data: mine } = await supabase
					.from(TABLES.runs)
					.select('metadata')
					.eq('id', data.id)
					.maybeSingle();
				const stored = (mine?.metadata as Record<string, unknown> | null)?.[
					'expected_return_at'
				];
				setExpectedReturnLocal(typeof stored === 'string' ? stored : null);
			}
		}
		return true;
	}

	// datetime-local <-> ISO. The input is naive local time; convert to a
	// real instant on save and back to a local-slot string on load.
	function isoToLocalInput(iso: string): string {
		const d = new Date(iso);
		if (!Number.isFinite(d.getTime())) return '';
		const off = d.getTimezoneOffset() * 60_000;
		return new Date(d.getTime() - off).toISOString().slice(0, 16);
	}

	function setExpectedReturnLocal(iso: string | null) {
		expectedReturnIso = iso;
		expectedReturnInput = iso ? isoToLocalInput(iso) : '';
	}

	async function saveExpectedReturn() {
		if (savingReturn || !expectedReturnInput) return;
		const when = new Date(expectedReturnInput);
		if (!Number.isFinite(when.getTime())) return;
		if (when.getTime() <= Date.now()) {
			showToast(m('safety.expectedReturnPast'), 'error');
			return;
		}
		savingReturn = true;
		try {
			const iso = when.toISOString();
			const ok = await setRunExpectedReturn(data.id, iso);
			if (!ok) throw new Error('not updated');
			setExpectedReturnLocal(iso);
			showToast(m('safety.expectedReturnSavedToast'), 'success');
		} catch (_) {
			showToast(m('safety.expectedReturnFailed'), 'error');
		} finally {
			savingReturn = false;
		}
	}

	async function clearExpectedReturn() {
		if (savingReturn) return;
		savingReturn = true;
		try {
			const ok = await setRunExpectedReturn(data.id, null);
			if (!ok) throw new Error('not updated');
			setExpectedReturnLocal(null);
			showToast(m('safety.expectedReturnClearedToast'), 'info');
		} catch (_) {
			showToast(m('safety.expectedReturnFailed'), 'error');
		} finally {
			savingReturn = false;
		}
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

	// Finished/waiting boundaries live in the pure, unit-tested
	// $lib/runs/live_spectator_status helpers (issue #603).
	function freezeOnSavedTotals(run: VisibleRun) {
		distance = run.distance_m;
		elapsed = run.duration_s;
		if (distance > 0 && elapsed > 0) currentPace = formatPace(elapsed, distance);
	}

	function teardownTransports() {
		if (realtimeChannel) {
			supabase.removeChannel(realtimeChannel);
			realtimeChannel = null;
		}
		liveHubHandle?.close();
		liveHubHandle = null;
	}

	// While live, poll the row for the positive concluded_at marker. The
	// recorder now LEAVES the pings on stop (they're bounded by the 48h
	// retention cron) so the feed no longer vanishes — it would just go
	// stale — which means "no pings" can't be the finish signal anymore.
	// concluded_at is the honest one: when it appears we freeze on the
	// saved totals and switch to the conclusion view for every transport.
	async function checkConcluded() {
		if (status !== 'live' || !visibleRun) return;
		const { data: row } = await supabase
			.from('public_runs')
			.select('concluded_at, distance_m, duration_s')
			.eq('id', data.id)
			.maybeSingle();
		if (!row?.concluded_at || status !== 'live' || !visibleRun) return;
		visibleRun = {
			...visibleRun,
			distance_m: Number(row.distance_m ?? visibleRun.distance_m),
			duration_s: Number(row.duration_s ?? visibleRun.duration_s),
			concluded_at: row.concluded_at as string,
		};
		freezeOnSavedTotals(visibleRun);
		teardownTransports();
		status = 'finished';
	}

	onMount(() => {
		// Honour the global banner choice. The "Load map" button below
		// is the per-page acceptance path when the banner hasn't been
		// answered yet.
		if (hasAcceptedConsent()) mapConsented = true;
		// Drives the freshness readout / stale-badge transition while no
		// new ping arrives, and every ~15s re-checks the concluded_at marker
		// so a runner who stops mid-watch flips to the conclusion view
		// instead of just going stale.
		freshnessTicker = setInterval(() => {
			nowMs = Date.now();
			if (status === 'live' && ++concludedCheckTick % 15 === 0) {
				void checkConcluded();
			}
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
			const run = visibleRun;
			if (!run) return;
			void loadRouteCutoffs(run);
			// A stamped concluded_at is the positive terminal signal and
			// wins over the pings — the recorder now keeps them, so
			// statusAfterHydrate would otherwise read a concluded run as
			// still live. isFinishedStale stays as the belt-and-braces
			// inference for older runs saved before the marker existed.
			if (run.concluded_at || isFinishedStale(run.started_at, run.duration_s, Date.now())) {
				freezeOnSavedTotals(run);
				// Best-effort backlog hydrate so the map still gets the
				// trace shape, but don't open realtime — the run is over.
				await hydrateBacklog();
				status = 'finished';
				return;
			}
			const hadBacklog = await hydrateBacklog();
			const next = statusAfterHydrate({
				startedAtIso: run.started_at,
				durationS: run.duration_s,
				hadBacklog,
				nowMs: Date.now(),
			});
			if (next === 'finished') {
				// Belt-and-braces no-backlog path: no concluded_at marker
				// caught this above (an old run predating the marker, or one
				// whose pings the 48h retention cron already cleaned) and the
				// saved end has passed with no surviving pings. Freeze on the
				// saved totals — this used to fall through to the synthesised
				// demo loop (issue #603). The recorder no longer wipes pings
				// on stop, so the common just-finished case is now caught by
				// the concluded_at branch above with the trace intact.
				freezeOnSavedTotals(run);
				status = 'finished';
				return;
			}
			subscribeLive();
			if (next === 'live') status = 'live';
			// `waiting` keeps `connecting` — the honest state for a
			// broadcast whose first ping hasn't arrived.
		})();
	});

	// Initialise once the container exists. The `{#if mapConsented}` div
	// only binds after the state flush, so a synchronous initMap() call
	// from onMount ran before `mapContainer` was set and silently left a
	// consented viewer with a blank map — the effect fires after the DOM
	// updates on both the pre-consented and "Load map" paths.
	$effect(() => {
		if (mapConsented && mapContainer) initMap();
	});

	// On a concluded run, frame the whole trace once instead of staying
	// zoomed on the last fix — the spectator's takeaway is the finished
	// route, not where the runner happened to stop. Depends on both status
	// and mapReady ($state) so it fires whichever lands last: the run may
	// be concluded before the viewer loads the map, or conclude mid-watch
	// with the map already up. Guarded so it fits once.
	let fittedTrace = false;
	$effect(() => {
		if (status !== 'finished' || !mapReady || fittedTrace || !map || traceCoords.length < 2) {
			return;
		}
		fittedTrace = true;
		const bounds = traceCoords.reduce(
			(b, c) => b.extend(c),
			new maplibregl.LngLatBounds(traceCoords[0], traceCoords[0]),
		);
		try {
			map.fitBounds(bounds, { padding: 48, maxZoom: 16, duration: 600 });
		} catch {
			// A degenerate bounds (all points coincident) can throw; the
			// last-fix centre from map load is a fine fallback.
		}
	});

	function recentreOnRunner() {
		userPanned = false;
		if (map && latestPosition) {
			map.easeTo({ center: [latestPosition.lng, latestPosition.lat] });
		}
	}

	function loadMapNow() {
		mapConsented = true;
	}

	function prefersDarkOs(): boolean {
		return (
			typeof window !== 'undefined' &&
			window.matchMedia('(prefers-color-scheme: dark)').matches
		);
	}

	// Whether the basemap resolved for this page is dark. NOT the OS
	// preference: the map-style setting decouples the two (see
	// `basemap_contrast.ts`), and the trace's 3:1 is owed to the ground.
	function liveDarkBasemap(): boolean {
		return basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDarkOs());
	}

	function initMap() {
		if (map || !mapContainer) return;
		map = new maplibregl.Map({
			container: mapContainer,
			// Honours PUBLIC_TILE_STYLE_URL override the same way every
			// other map surface does (decisions.md § 68).
			style: mapStyleUrlFromEnv(PUBLIC_MAPTILER_KEY, prefersDarkOs()),
			center: [fallbackLng, fallbackLat],
			zoom: 15,
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		const geolocate = new maplibregl.GeolocateControl({
			positionOptions: { enableHighAccuracy: true },
			trackUserLocation: true,
		});
		// Tracking the viewer's own position must win over the runner
		// follow-cam, or the two camera drivers fight on every ping.
		geolocate.on('trackuserlocationstart', () => {
			userPanned = true;
		});
		map.addControl(geolocate, 'top-right');
		// dragstart fires on user gestures only, never on panTo/jumpTo.
		map.on('dragstart', () => {
			userPanned = true;
		});
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
				paint: { 'line-color': mapLiveLine(liveDarkBasemap()), 'line-width': 3 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
			if (traceCoords.length > 0) {
				const last = traceCoords[traceCoords.length - 1];
				ensureMarker(last[1], last[0]);
				map.jumpTo({ center: [last[0], last[1]], zoom: 15 });
				centred = true;
			}
			// Let the fit-to-trace effect run now that the map exists — it
			// frames the whole route on a concluded run.
			mapReady = true;
		});
	}

	onDestroy(() => {
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

	<!-- Shell-less routes get no <main> from +layout.svelte, so each one owns
	     its landmark — every /share/* sibling already does. Without it this
	     page shipped no main region at all (WCAG 1.3.1). -->
	<main id="main-content">
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
				{#if status === 'live' && recentPaceSecPerKm != null}
					<div class="live-stat" data-testid="recent-pace">
						<span class="live-stat-value">{formatPace(recentPaceSecPerKm, 1000)}</span>
						<span class="live-stat-label"
							>{isStale ? m('live.statRecentPaceStale') : m('live.statRecentPace')}</span
						>
					</div>
				{/if}
			</div>
			{#if motion?.state === 'stopped' && motion.stoppedForMs != null}
				<p class="motion-chip" data-testid="motion-stopped">
					<span class="material-symbols" aria-hidden="true">pause_circle</span>
					{motion.atLeast
						? m('live.motionStoppedAtLeast', {
								n: Math.floor(motion.stoppedForMs / 60000),
							})
						: m('live.motionStopped', { n: Math.floor(motion.stoppedForMs / 60000) })}
				</p>
			{/if}
			{#if status === 'live' && courseProgressPct != null}
				<div
					class="course-progress"
					data-testid="course-progress"
					aria-label={m('live.courseProgress', { p: Math.round(courseProgressPct) })}
				>
					<div class="course-progress-track">
						<div class="course-progress-fill" style="width: {courseProgressPct}%"></div>
					</div>
					<span class="course-progress-label"
						>{m('live.courseProgress', { p: Math.round(courseProgressPct) })}</span
					>
				</div>
			{/if}
		</section>

			{#if status === 'finished'}
				<section class="conclusion-card" data-testid="conclusion-card">
					<span class="material-symbols conclusion-icon" aria-hidden="true">flag_circle</span>
					<div class="conclusion-text">
						<h2>{m('live.concludedTitle')}</h2>
						<p>{m('live.concludedBody')}</p>
					</div>
					<a href={`/share/run/${data.id}`} class="btn btn-primary conclusion-cta">
						{m('live.viewFullRun')}
					</a>
				</section>
			{/if}

			{#if hasCutoffRoute && eta?.checkpoint}
				<section
					class="cutoff-card"
					class:on={eta.status === 'on'}
					class:tight={eta.status === 'tight'}
					class:behind={eta.status === 'behind'}
					class:stale={eta.status === 'unknown' && isStale}
					class:expired={eta.limitPassed}
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
						{#if eta.limitPassed}
							<span class="cutoff-expired" data-testid="cutoff-expired">
								{m('live.cutoffExpired')}
							</span>
						{:else if eta.requiredPaceSecPerKm != null && eta.status !== 'on'}
							<span class="cutoff-required" data-testid="cutoff-required">
								{isStale
									? m('live.cutoffRequiredPaceStale', {
											p: formatPace(eta.requiredPaceSecPerKm, 1000),
										})
									: m('live.cutoffRequiredPace', {
											p: formatPace(eta.requiredPaceSecPerKm, 1000),
										})}
							</span>
						{/if}
						{#if eta.status === 'unknown'}
							<span class="cutoff-waiting"
								>{isStale
									? m('live.cutoffSignalLost')
									: m('live.cutoffWaitingSignal')}</span
							>
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

			{#if isOwner && status !== 'finished'}
				<section class="return-card" data-testid="expected-return-card">
					<div class="return-head">
						<span class="material-symbols" aria-hidden="true">notifications_active</span>
						<div>
							<h2>{m('safety.expectedReturnTitle')}</h2>
							<p class="return-intro">{m('safety.expectedReturnIntro')}</p>
						</div>
					</div>
					<div class="return-controls">
						<input
							type="datetime-local"
							class="return-input"
							bind:value={expectedReturnInput}
							aria-label={m('safety.expectedReturnLabel')}
							data-testid="expected-return-input"
						/>
						<button
							class="btn btn-primary"
							onclick={saveExpectedReturn}
							disabled={savingReturn || !expectedReturnInput}
							data-testid="expected-return-set"
						>
							{m('safety.expectedReturnSave')}
						</button>
						{#if expectedReturnIso}
							<button
								class="btn btn-outline"
								onclick={clearExpectedReturn}
								disabled={savingReturn}
								data-testid="expected-return-clear"
							>
								{m('safety.expectedReturnClear')}
							</button>
						{/if}
					</div>
					{#if expectedReturnIso}
						<p class="return-active" data-testid="expected-return-active">
							{m('safety.expectedReturnActive', { time: expectedReturnDisplay })}
						</p>
					{/if}
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
				{#if userPanned && latestPosition}
					<button
						type="button"
						class="recentre-btn"
						onclick={recentreOnRunner}
						title={m('live.recentre')}
						aria-label={m('live.recentre')}
					>
						<span class="material-symbols" aria-hidden="true">my_location</span>
					</button>
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
	</main>
</div>

<style>
	.live-page {
		display: flex;
		flex-direction: column;
		height: 100vh;
		background: var(--color-bg);
	}

	/* The landmark sits between .live-page's column and the rows that depend on
	 * it — .live-map-wrap is `flex: 1` against the page height — so it has to
	 * carry the column itself, or the map resolves against nothing and its
	 * controls land off-screen. `min-width: 0` for the § 535 reason: a flex
	 * item defaults to `min-width: auto` and floors at its content's
	 * min-content width, which is the page ceasing to be a function of the
	 * viewport. */
	.live-page > main {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-height: 0;
		min-width: 0;
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
		color: var(--color-success-text);
		border-color: color-mix(in srgb, var(--color-success) 35%, transparent);
	}

	.live-badge.stale {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning-text);
		border-color: color-mix(in srgb, var(--color-warning) 35%, transparent);
	}

	.live-badge.not-found {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
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
		/* Independent values, so a row that no longer fits should reflow rather
		 * than push the strip's padding box open: without these the row sits at
		 * its min-content width and overflows the strip it lives in. */
		flex-wrap: wrap;
		justify-content: flex-end;
		min-width: 0;
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
		font-size: var(--font-size-section-label);
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

	/* Neutral, not alarming: a stopped runner is at an aid station far more
	   often than they are in trouble, and the surface states the fact
	   without grading it. */
	.motion-chip {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin: 0;
		padding: 0 var(--space-2xl) var(--space-md);
		font-size: 0.8125rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.motion-chip .material-symbols {
		font-size: 1.125rem;
	}

	.course-progress {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: 0 var(--space-2xl) var(--space-md);
		flex-wrap: wrap;
		min-width: 0;
	}
	.course-progress-track {
		flex: 1;
		height: 6px;
		border-radius: 999px;
		background: var(--color-fill-subtle);
		overflow: hidden;
	}
	.course-progress-fill {
		height: 100%;
		border-radius: 999px;
		background: var(--color-primary);
		transition: width 0.4s ease;
	}
	.course-progress-label {
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.conclusion-card {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		padding: var(--space-lg) var(--space-2xl);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		border-inline-start: 4px solid var(--color-success);
	}
	.conclusion-icon {
		font-size: 2rem;
		color: var(--color-success-text);
		flex-shrink: 0;
	}
	.conclusion-text {
		flex: 1;
		min-width: 0;
	}
	.conclusion-text h2 {
		margin: 0;
		font-size: 1.05rem;
		font-weight: 800;
	}
	.conclusion-text p {
		margin: var(--space-2xs) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.conclusion-cta {
		flex-shrink: 0;
	}
	@media (max-width: 48rem) {
		.conclusion-card {
			flex-wrap: wrap;
		}
		.conclusion-cta {
			width: 100%;
			text-align: center;
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
	/* Signal-lost state: the projection is suppressed because the last fix
	 * is stale, so the card reads amber-delayed — matching the header
	 * DELAYED badge — rather than a neutral "still computing" grey. */
	.cutoff-card.stale {
		border-inline-start-color: var(--color-warning);
	}
	.cutoff-card.stale .cutoff-waiting {
		color: var(--color-warning-text);
		font-style: normal;
		font-weight: 600;
	}
	/* An expired limit outranks every other edge state, including the amber
	 * stale one: the deadline is gone whether or not the fix is current, and
	 * that is the fact the crew at the checkpoint is deciding on. Declared
	 * after `.stale` so it wins at equal specificity. */
	.cutoff-card.expired {
		border-inline-start-color: var(--color-danger);
	}
	.cutoff-head {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.cutoff-title {
		font-size: var(--font-size-section-label);
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
		color: var(--color-success-text);
		border-color: color-mix(in srgb, var(--color-success) 35%, transparent);
	}
	.cutoff-card.tight .cutoff-chip {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: var(--color-warning-text);
		border-color: color-mix(in srgb, var(--color-warning) 35%, transparent);
	}
	.cutoff-card.behind .cutoff-chip {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
		border-color: color-mix(in srgb, var(--color-danger) 35%, transparent);
	}
	.cutoff-waiting {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		font-style: italic;
	}
	.cutoff-expired {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2xs) var(--space-md);
		border-radius: 9999px;
		font-size: 0.78rem;
		font-weight: 700;
		background: var(--color-danger-light);
		color: var(--color-danger-text);
		border: 1px solid color-mix(in srgb, var(--color-danger) 35%, transparent);
	}
	.cutoff-required {
		font-size: 0.8rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
	}

	.return-card {
		margin: 0 var(--space-md) var(--space-md);
		padding: var(--space-md) var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg, 12px);
		background: var(--color-surface);
	}
	.return-head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.return-head .material-symbols {
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.return-head h2 {
		margin: 0;
		font-size: 1rem;
	}
	.return-intro {
		margin: var(--space-2xs) 0 0;
		font-size: 0.84rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}
	.return-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.return-input {
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md, 8px);
		font-size: 0.9rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.return-active {
		margin: var(--space-md) 0 0;
		font-size: 0.84rem;
		font-weight: 600;
		color: var(--color-primary);
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
	.recentre-btn {
		position: absolute;
		inset-inline-end: var(--space-md);
		inset-block-end: var(--space-2xl);
		z-index: 5;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 44px;
		height: 44px;
		border: 1px solid var(--color-border);
		border-radius: 50%;
		background: var(--color-surface);
		box-shadow: var(--shadow-md);
		cursor: pointer;
		color: var(--color-text);
	}
	.recentre-btn:hover {
		color: var(--color-primary);
	}
	.recentre-btn .material-symbols {
		font-size: 1.3rem;
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
		color: var(--color-warning-text);
		border: 1px solid color-mix(in srgb, var(--color-warning) 35%, transparent);
	}
	.approx-badge .material-symbols {
		font-size: 1rem;
	}
</style>
