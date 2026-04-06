<script lang="ts">
	let routeName = $state('');
	let mode = $state<'road' | 'trail'>('road');
	let waypoints = $state(0);
	let distance = $state(0);
	let elevation = $state(0);
</script>

<div class="builder-layout">
	<aside class="sidebar">
		<a href="/routes" class="back-link">
			<span class="material-symbols">arrow_back</span>
			Routes
		</a>

		<h1>Route Builder</h1>

		<div class="controls">
			<label>
				<span class="label-text">Route Name</span>
				<input type="text" placeholder="My Route" bind:value={routeName} />
			</label>

			<fieldset>
				<legend class="label-text">Mode</legend>
				<div class="mode-buttons">
					<button
						class="mode-btn"
						class:active={mode === 'road'}
						onclick={() => (mode = 'road')}
					>
						<span class="material-symbols">directions_car</span>
						Road
					</button>
					<button
						class="mode-btn"
						class:active={mode === 'trail'}
						onclick={() => (mode = 'trail')}
					>
						<span class="material-symbols">forest</span>
						Trail
					</button>
				</div>
			</fieldset>

			<div class="stats-row">
				<div class="builder-stat">
					<span class="builder-stat-value">{(distance / 1000).toFixed(2)} km</span>
					<span class="builder-stat-label">Distance</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{elevation} m</span>
					<span class="builder-stat-label">Elevation</span>
				</div>
				<div class="builder-stat">
					<span class="builder-stat-value">{waypoints}</span>
					<span class="builder-stat-label">Points</span>
				</div>
			</div>

			<!-- Elevation profile preview -->
			<div class="elevation-preview">
				<span class="label-text">Elevation Profile</span>
				<div class="elevation-empty">
					<span class="material-symbols">show_chart</span>
					<span>Add waypoints to see profile</span>
				</div>
			</div>

			<div class="action-row">
				<button class="btn btn-ghost" disabled={waypoints === 0}>
					<span class="material-symbols">undo</span>
					Undo
				</button>
				<button class="btn btn-ghost" disabled={waypoints === 0}>
					<span class="material-symbols">delete</span>
					Clear
				</button>
			</div>

			<div class="action-row">
				<button class="btn btn-primary" disabled={waypoints === 0}>Save Route</button>
				<button class="btn btn-outline" disabled={waypoints === 0}>Export GPX</button>
			</div>
		</div>

		<div class="sidebar-hint">
			<span class="material-symbols">info</span>
			Click on the map to place waypoints. The route will auto-snap to {mode === 'road' ? 'roads' : 'walking paths'}.
		</div>
	</aside>

	<main class="map-area">
		<div class="map-placeholder">
			<span class="material-symbols">map</span>
			<p>Google Maps loads here</p>
			<p class="hint">Click to place waypoints</p>
		</div>
	</main>
</div>

<style>
	.builder-layout {
		display: flex;
		height: 100vh;
	}

	.sidebar {
		width: 22rem;
		border-right: 1px solid var(--color-border);
		padding: var(--space-lg);
		overflow-y: auto;
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
		margin-bottom: var(--space-lg);
	}

	.controls {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		flex: 1;
	}

	.label-text {
		display: block;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xs);
	}

	input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		transition: border-color var(--transition-fast);
		background: var(--color-bg);
	}

	input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	fieldset {
		border: none;
		padding: 0;
	}

	legend {
		margin-bottom: var(--space-sm);
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
		font-size: 1rem;
		font-weight: 700;
	}

	.builder-stat-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.elevation-preview {
		margin-top: var(--space-sm);
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

	.action-row {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		flex: 1;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
	}

	.btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover:not(:disabled) {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-ghost {
		background: transparent;
		border: none;
		color: var(--color-text-secondary);
	}

	.btn-ghost:hover:not(:disabled) {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}

	.sidebar-hint {
		display: flex;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-primary-light);
		border-radius: var(--radius-md);
		font-size: 0.8rem;
		color: var(--color-primary);
		margin-top: var(--space-lg);
		line-height: 1.4;
	}

	.sidebar-hint .material-symbols {
		flex-shrink: 0;
	}

	.map-area {
		flex: 1;
		background: var(--color-bg-tertiary);
	}

	.map-placeholder {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		color: var(--color-text-tertiary);
		gap: var(--space-sm);
	}

	.map-placeholder .material-symbols {
		font-size: 3rem;
	}

	.hint {
		font-size: 0.85rem;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
</style>
