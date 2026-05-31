<script lang="ts" module>
	type Waypoint = { lat: number; lng: number };

	// Module-level cache keyed by route id + clip variant. Same shape as
	// RunTrackPreview's cache; the `raw:` vs `clip:` prefix keeps owner
	// and non-owner reads of the same route from polluting each other.
	const CACHE_MAX = 200;
	const CACHE = new Map<string, Waypoint[] | null>();
	function cacheSet(key: string, value: Waypoint[] | null) {
		if (CACHE.size >= CACHE_MAX && !CACHE.has(key)) {
			const oldest = CACHE.keys().next().value;
			if (oldest !== undefined) CACHE.delete(oldest);
		}
		CACHE.set(key, value);
	}
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import TrackPreview from './TrackPreview.svelte';
	import { fetchClippedRouteForViewer } from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	const PUBLIC_TILE_STYLE_URL = env.PUBLIC_TILE_STYLE_URL ?? '';
	import { buildStaticMapUrl, buildLocalStaticMapUrl } from '$lib/routes/static_map';

	let {
		routeId,
		waypoints,
		ownerUserId,
	}: {
		/// The route's id. Required when the viewer isn't the owner — we
		/// route through clip_route_for_viewer to get privacy-zone-clipped
		/// waypoints (decisions §33). The bare `waypoints` prop is the
		/// unclipped polyline from the row and must not reach the renderer
		/// when ownerUserId !== viewerId.
		routeId: string;
		waypoints: Waypoint[];
		/// `routes.user_id` is `NOT NULL` (every route has an owner), so
		/// this prop is intentionally non-nullable. The shouldClip
		/// expression below relies on that — `viewerId == null && ownerUserId == null`
		/// would otherwise evaluate to "owner" and skip the clip. If the
		/// schema ever permits a nullable `user_id` (e.g. for fully-anon
		/// club routes), update the gate to
		/// `viewerId === null || ownerUserId !== viewerId`.
		ownerUserId: string;
	} = $props();

	const viewerId = $derived(auth.user?.id ?? null);
	// Treat anon (`viewerId == null`) as non-owner so unauthenticated
	// share-link traffic gets the clip pass too.
	const shouldClip = $derived(ownerUserId !== viewerId);
	const cacheKey = $derived(`${shouldClip ? 'clip' : 'raw'}:${routeId}`);

	let el: HTMLDivElement;
	let points = $state<Waypoint[] | null>(null);
	let attempted = $state(false);

	onMount(() => {
		// Owner case + waypoints present: use them directly (no fetch).
		// Some call sites (e.g. RouteExplorer cards, where the
		// `search_public_routes` RPC returns the redacted
		// `public_routes` view with NO waypoints column) pass
		// `waypoints=[]`. Fall through to the clip RPC in that case
		// so the card still gets a polyline — `clip_route_for_viewer`
		// returns the unclipped polyline for the owner anyway.
		if (!shouldClip && waypoints && waypoints.length >= 2) {
			points = waypoints;
			attempted = true;
			return;
		}
		// Cache hit — common when scrolling back through a list.
		if (CACHE.has(cacheKey)) {
			points = CACHE.get(cacheKey) ?? null;
			attempted = true;
			return;
		}
		const io = new IntersectionObserver(
			(entries) => {
				for (const e of entries) {
					if (e.isIntersecting) {
						io.disconnect();
						void load();
						break;
					}
				}
			},
			{ rootMargin: '200px' },
		);
		io.observe(el);
		return () => io.disconnect();
	});

	async function load() {
		if (attempted) return;
		attempted = true;
		try {
			const clipped = await fetchClippedRouteForViewer(routeId);
			cacheSet(cacheKey, clipped);
			points = clipped;
		} catch (_) {
			cacheSet(cacheKey, null);
		}
	}
</script>

<div bind:this={el} class="wrap">
	{#if points && points.length > 1}
		{@const mapUrl =
			buildLocalStaticMapUrl(points, {
				w: 220,
				h: 140,
				styleUrl: PUBLIC_TILE_STYLE_URL,
			}) ??
			buildStaticMapUrl(points, {
				w: 220,
				h: 140,
				style: 'streets-v2',
				key: PUBLIC_MAPTILER_KEY,
			})}
		{#if mapUrl}
			<!-- Static map background: shows the route polyline overlaid
			     on real tiles (roads, parks, water) so users can scan a
			     card and recognise where the route is. Falls back to the
			     bare SVG when PUBLIC_MAPTILER_KEY isn't set or the route
			     has <2 points. The img is lazy-loaded so a long list
			     doesn't fire 50 static-map requests on page load — only
			     the cards inside the viewport hit MapTiler. -->
			<img
				src={mapUrl}
				class="map-img"
				loading="lazy"
				decoding="async"
				alt=""
				data-testid="route-preview-map"
			/>
		{:else}
			<TrackPreview {points} />
		{/if}
	{:else}
		<span class="material-symbols placeholder">map</span>
	{/if}
</div>

<style>
	.wrap {
		width: 100%;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: hidden;
	}
	.map-img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}
	.placeholder {
		font-family: 'Material Symbols Outlined';
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
	}
</style>
