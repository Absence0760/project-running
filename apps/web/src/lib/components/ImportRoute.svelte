<script lang="ts">
	import { parseRouteFile, type ImportedRoute } from '$lib/import';
	import { saveRoute } from '$lib/data';
	import { formatDistance } from '$lib/mock-data';
	import { goto } from '$app/navigation';

	let { onclose = () => {} }: { onclose?: () => void } = $props();

	let dragging = $state(false);
	let parsing = $state(false);
	let saving = $state(false);
	let error = $state('');
	let parsed = $state<ImportedRoute | null>(null);
	let routeName = $state('');

	function handleDragOver(e: DragEvent) {
		e.preventDefault();
		dragging = true;
	}

	function handleDragLeave() {
		dragging = false;
	}

	async function handleDrop(e: DragEvent) {
		e.preventDefault();
		dragging = false;
		const file = e.dataTransfer?.files[0];
		if (file) await processFile(file);
	}

	async function handleFileSelect(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		if (file) await processFile(file);
	}

	async function processFile(file: File) {
		error = '';
		parsing = true;
		parsed = null;
		try {
			parsed = await parseRouteFile(file);
			routeName = parsed.name;
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to parse file';
		} finally {
			parsing = false;
		}
	}

	async function handleSave() {
		if (!parsed) return;
		saving = true;
		error = '';
		try {
			const saved = await saveRoute({
				name: routeName || parsed.name,
				waypoints: parsed.waypoints,
				distance_m: parsed.distance_m,
				elevation_m: parsed.elevation_m,
				surface: 'road',
				is_public: false,
			});
			goto(`/routes/${saved.id}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to save route';
		} finally {
			saving = false;
		}
	}

	function reset() {
		parsed = null;
		routeName = '';
		error = '';
	}
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="overlay" onclick={onclose}>
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="modal" onclick={(e) => e.stopPropagation()}>
		<header class="modal-header">
			<h2>Import Route</h2>
			<button class="close-btn" onclick={onclose}>&times;</button>
		</header>

		{#if error}
			<div class="error">{error}</div>
		{/if}

		{#if !parsed}
			<!-- Drop zone -->
			<div
				class="drop-zone"
				class:dragging
				ondragover={handleDragOver}
				ondragleave={handleDragLeave}
				ondrop={handleDrop}
			>
				{#if parsing}
					<span class="material-symbols">hourglass_empty</span>
					<p>Parsing file...</p>
				{:else}
					<span class="material-symbols">upload_file</span>
					<p>Drag & drop a route file here</p>
					<p class="drop-hint">GPX, KML, KMZ, GeoJSON, or TCX</p>
					<p class="drop-hint">Works with Google Maps, Google Earth, Strava, Garmin, and more</p>
					<label class="browse-btn">
						Browse files
						<input type="file" accept=".gpx,.kml,.kmz,.geojson,.json,.tcx" onchange={handleFileSelect} hidden />
					</label>
				{/if}
			</div>
		{:else}
			<!-- Preview -->
			<div class="preview">
				<label>
					<span class="label-text">Route Name</span>
					<input type="text" bind:value={routeName} />
				</label>

				<div class="stats">
					<div class="stat">
						<span class="stat-value">{formatDistance(parsed.distance_m)}</span>
						<span class="stat-label">Distance</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed.elevation_m ?? 0} m</span>
						<span class="stat-label">Elevation Gain</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed.waypoints.length}</span>
						<span class="stat-label">Points</span>
					</div>
				</div>

				<div class="actions">
					<button class="btn btn-ghost" onclick={reset}>Choose different file</button>
					<button class="btn btn-primary" onclick={handleSave} disabled={saving}>
						{saving ? 'Saving...' : 'Save Route'}
					</button>
				</div>
			</div>
		{/if}
	</div>
</div>

<style>
	.overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 100;
	}

	.modal {
		background: var(--color-surface);
		border-radius: var(--radius-lg);
		width: 100%;
		max-width: 32rem;
		padding: var(--space-xl);
		box-shadow: var(--shadow-lg, 0 8px 32px rgba(0, 0, 0, 0.2));
	}

	.modal-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-lg);
	}

	h2 {
		font-size: 1.25rem;
		font-weight: 700;
	}

	.close-btn {
		background: none;
		border: none;
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0;
		line-height: 1;
	}

	.close-btn:hover {
		color: var(--color-text);
	}

	.error {
		background: var(--color-danger-light, #fef2f2);
		border: 1px solid rgba(229, 57, 53, 0.3);
		color: var(--color-danger, #e53935);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin-bottom: var(--space-md);
	}

	.drop-zone {
		border: 2px dashed var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-2xl);
		text-align: center;
		color: var(--color-text-tertiary);
		transition: all var(--transition-fast);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
	}

	.drop-zone.dragging {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		color: var(--color-primary);
	}

	.drop-zone .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 2.5rem;
	}

	.drop-zone p {
		margin: 0;
	}

	.drop-hint {
		font-size: 0.8rem;
	}

	.browse-btn {
		display: inline-block;
		margin-top: var(--space-md);
		padding: var(--space-sm) var(--space-lg);
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
	}

	.browse-btn:hover {
		background: var(--color-primary-hover);
	}

	.preview {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
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
		background: var(--color-bg);
		font-family: inherit;
	}

	input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-sm);
	}

	.stat {
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		padding: var(--space-sm) var(--space-md);
		text-align: center;
	}

	.stat-value {
		display: block;
		font-size: 1rem;
		font-weight: 700;
	}

	.stat-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}

	.btn {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.btn:disabled {
		opacity: 0.5;
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-ghost {
		background: none;
		border: none;
		color: var(--color-text-secondary);
	}

	.btn-ghost:hover {
		color: var(--color-text);
	}
</style>
