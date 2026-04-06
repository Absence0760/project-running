<script lang="ts">
	let { data } = $props();
</script>

<main class="route-detail">
	<h1>Route Detail</h1>

	<!-- TODO: Fetch route from Supabase using data.id -->
	<!-- TODO: Route map -->
	<div class="map-placeholder"></div>

	<!-- TODO: Route stats: distance, elevation, surface -->
</main>

<style>
	.route-detail { max-width: 56rem; margin: 0 auto; padding: 2rem; }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 1rem; }
	.map-placeholder { aspect-ratio: 16/9; background: #e5e5e5; border-radius: 0.5rem; margin-bottom: 2rem; }
</style>
