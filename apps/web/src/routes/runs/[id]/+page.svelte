<script lang="ts">
	let { data } = $props();
</script>

<div class="run-detail-layout">
	<!-- Map (left, ~60%) -->
	<main class="map-panel">
		<!-- TODO: Full GPS trace on Google Maps -->
		<div class="map-placeholder">Run map</div>
	</main>

	<!-- Stats sidebar (right, ~40%) -->
	<aside class="stats-panel">
		<h1>Run Analysis</h1>

		<!-- TODO: Distance, duration, average pace, avg HR, elevation gain -->
		<!-- TODO: Splits table (per km) -->
		<!-- TODO: HR zone breakdown -->
		<!-- TODO: Elevation + pace chart -->
	</aside>
</div>

<style>
	.run-detail-layout { display: flex; height: 100vh; }
	.map-panel { flex: 3; background: #e5e5e5; }
	.map-placeholder { display: flex; align-items: center; justify-content: center; height: 100%; color: #888; }
	.stats-panel { flex: 2; border-left: 1px solid #e5e5e5; padding: 1.5rem; overflow-y: auto; }
	h1 { font-size: 1.25rem; font-weight: 700; margin-bottom: 1.5rem; }
</style>
