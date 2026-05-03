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
	import { fetchClippedRouteForViewer } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';

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
		// Owner case: use the row's waypoints directly. No RPC, no fetch.
		if (!shouldClip) {
			points = waypoints ?? [];
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
		<TrackPreview {points} />
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
	}
	.placeholder {
		font-family: 'Material Symbols Outlined';
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
	}
</style>
