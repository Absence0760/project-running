<script lang="ts">
	let routeName = $state('');
	let mode = $state<'road' | 'trail'>('road');

	// TODO: Initialize Google Maps JS API
	// TODO: Click-to-place waypoints with road/trail snapping
	// TODO: Live distance and elevation calculation
</script>

<div class="builder-layout">
	<!-- Sidebar -->
	<aside class="sidebar">
		<h1>Route Builder</h1>

		<div class="controls">
			<label>
				<span>Route Name</span>
				<input type="text" placeholder="My Route" bind:value={routeName} />
			</label>

			<fieldset>
				<legend>Mode</legend>
				<div class="mode-buttons">
					<button
						class="mode-btn"
						class:active={mode === 'road'}
						onclick={() => (mode = 'road')}
					>
						Road
					</button>
					<button
						class="mode-btn"
						class:active={mode === 'trail'}
						onclick={() => (mode = 'trail')}
					>
						Trail
					</button>
				</div>
			</fieldset>

			<div class="stats">
				<p>Distance: 0.00 km</p>
				<p>Elevation: 0 m</p>
			</div>

			<!-- TODO: Elevation profile chart -->

			<div class="action-row">
				<button class="btn-sm">Undo</button>
				<button class="btn-sm">Clear</button>
			</div>

			<div class="action-row">
				<button class="btn btn-primary">Save</button>
				<button class="btn btn-outline">Export GPX</button>
			</div>
		</div>
	</aside>

	<!-- Map area -->
	<main class="map-area">
		<!-- TODO: Google Maps JS API with click-to-place waypoints -->
		<div class="map-placeholder">Map loads here (Google Maps JavaScript API)</div>
	</main>
</div>

<style>
	.builder-layout { display: flex; height: 100vh; }
	.sidebar { width: 20rem; border-right: 1px solid #e5e5e5; padding: 1.5rem; overflow-y: auto; }
	h1 { font-size: 1.25rem; font-weight: 700; margin-bottom: 1.5rem; }
	.controls { display: flex; flex-direction: column; gap: 1rem; }
	label span { display: block; font-size: 0.875rem; font-weight: 500; margin-bottom: 0.25rem; }
	input { width: 100%; padding: 0.5rem 0.75rem; border: 1px solid #ddd; border-radius: 0.5rem; }
	fieldset { border: none; padding: 0; }
	legend { font-size: 0.875rem; font-weight: 500; margin-bottom: 0.25rem; }
	.mode-buttons { display: flex; gap: 0.5rem; }
	.mode-btn { padding: 0.25rem 0.75rem; border: 1px solid #ddd; border-radius: 0.25rem; cursor: pointer; background: white; }
	.mode-btn.active { background: #1E88E5; color: white; border-color: #1E88E5; }
	.stats { font-size: 0.875rem; color: #888; }
	.action-row { display: flex; gap: 0.5rem; }
	.btn-sm { padding: 0.25rem 0.75rem; border: 1px solid #ddd; border-radius: 0.25rem; font-size: 0.875rem; cursor: pointer; background: white; }
	.btn { flex: 1; padding: 0.5rem 1rem; border-radius: 0.5rem; cursor: pointer; font-size: 0.875rem; }
	.btn-primary { background: #1E88E5; color: white; border: none; }
	.btn-outline { background: white; border: 1px solid #ddd; }
	.map-area { flex: 1; background: #e5e5e5; }
	.map-placeholder { display: flex; align-items: center; justify-content: center; height: 100%; color: #888; }
</style>
