<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY } from '$env/static/public';

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/streets-v2/style.json?key=${PUBLIC_MAPTILER_KEY}`,
			center: [144.9631, -37.8136], // Melbourne default
			zoom: 13
		});

		map.addControl(new maplibregl.NavigationControl(), 'top-right');

		// TODO: On each waypoint click -> request directions segment -> append to GeoJSON line
		// TODO: Export final line -> encode as GPX -> upload to Supabase Storage
	});

	onDestroy(() => {
		map?.remove();
	});
</script>

<div bind:this={mapContainer} style="width: 100%; height: 100%;"></div>
