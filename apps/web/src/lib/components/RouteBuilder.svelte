<script lang="ts">
	import { onMount } from 'svelte';

	let mapContainer: HTMLDivElement;

	onMount(() => {
		// TODO: Initialize Google Maps JS API
		// const map = new google.maps.Map(mapContainer, { ... });
		// const directionsService = new google.maps.DirectionsService();
		// const poly = new google.maps.Polyline({ map, path: [] });
		//
		// On each waypoint click -> request directions segment -> append to polyline
		// Export final polyline -> encode as GPX -> upload to Supabase Storage
	});
</script>

<div bind:this={mapContainer} class="w-full h-full"></div>
