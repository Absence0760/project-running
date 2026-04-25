<script lang="ts">
	import { parseRouteFile, type ImportedRoute } from '$lib/import';
	import { saveRoute } from '$lib/data';
	import { formatDistance } from '$lib/mock-data';
	import { goto } from '$app/navigation';

	let {
		onclose = () => {},
		onimport = (_ids: string[]) => {},
	}: {
		onclose?: () => void;
		onimport?: (ids: string[]) => void;
	} = $props();

	let dragging = $state(false);
	let parsing = $state(false);
	let saving = $state(false);
	let error = $state('');
	// Every parsed file yields an array — a single-route file is just a
	// one-element list. `names` and `selected` are parallel to `parsed`
	// so the user can rename and deselect individual tracks before save.
	let parsed = $state<ImportedRoute[]>([]);
	let names = $state<string[]>([]);
	let selected = $state<boolean[]>([]);

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
		parsed = [];
		try {
			const routes = await parseRouteFile(file);
			parsed = routes;
			names = routes.map((r) => r.name);
			selected = routes.map(() => true);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to parse file';
		} finally {
			parsing = false;
		}
	}

	async function handleSave() {
		if (parsed.length === 0) return;
		saving = true;
		error = '';
		try {
			const toSave = parsed
				.map((r, i) => ({ route: r, name: names[i] || r.name, keep: selected[i] }))
				.filter((x) => x.keep);
			if (toSave.length === 0) {
				error = 'Select at least one route to import.';
				saving = false;
				return;
			}
			const savedIds: string[] = [];
			for (const item of toSave) {
				const saved = await saveRoute({
					name: item.name,
					waypoints: item.route.waypoints,
					distance_m: item.route.distance_m,
					elevation_m: item.route.elevation_m,
					surface: 'road',
					is_public: false,
				});
				savedIds.push(saved.id);
			}
			// Single import → jump to the new route; multi-import → hand
			// control back to the parent so it can refetch + close the
			// modal. `goto('/routes')` is a no-op when the modal is
			// already opened from the routes list (same URL, no state
			// refresh), so we rely on the callback instead.
			if (savedIds.length === 1) {
				goto(`/routes/${savedIds[0]}`);
			} else {
				onimport(savedIds);
				onclose();
			}
		} catch (err) {
			error = err instanceof Error ? err.message : 'Failed to save route';
		} finally {
			saving = false;
		}
	}

	function reset() {
		parsed = [];
		names = [];
		selected = [];
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

		{#if parsed.length === 0}
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
		{:else if parsed.length === 1}
			<!-- Single-route preview (current behaviour) -->
			<div class="preview">
				<label>
					<span class="label-text">Route Name</span>
					<input type="text" bind:value={names[0]} />
				</label>

				<div class="stats">
					<div class="stat">
						<span class="stat-value">{formatDistance(parsed[0].distance_m)}</span>
						<span class="stat-label">Distance</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed[0].elevation_m ?? 0} m</span>
						<span class="stat-label">Elevation Gain</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed[0].waypoints.length}</span>
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
		{:else}
			<!-- Multi-route preview — one card per parsed track. Allows the
			     user to rename or deselect individual tracks before import. -->
			<div class="preview">
				<p class="multi-intro">
					Found <strong>{parsed.length}</strong> routes in this file. Pick which
					ones to import — each becomes its own route in Better Runner.
				</p>
				<ul class="multi-list">
					{#each parsed as route, i (i)}
						<li class="multi-item">
							<label class="multi-toggle">
								<input type="checkbox" bind:checked={selected[i]} />
							</label>
							<div class="multi-fields">
								<input type="text" bind:value={names[i]} disabled={!selected[i]} />
								<div class="multi-meta">
									<span>{formatDistance(route.distance_m)}</span>
									<span class="meta-sep">·</span>
									<span>{route.elevation_m ?? 0} m elev</span>
									<span class="meta-sep">·</span>
									<span>{route.waypoints.length} pts</span>
								</div>
							</div>
						</li>
					{/each}
				</ul>
				<div class="actions">
					<button class="btn btn-ghost" onclick={reset}>Choose different file</button>
					<button class="btn btn-primary" onclick={handleSave} disabled={saving}>
						{saving
							? 'Saving...'
							: `Import ${selected.filter(Boolean).length} route${selected.filter(Boolean).length === 1 ? '' : 's'}`}
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

	.multi-intro {
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.multi-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-height: 20rem;
		overflow-y: auto;
	}
	.multi-item {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.5rem 0.75rem;
		background: var(--color-bg-secondary, var(--color-bg));
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.multi-toggle {
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.multi-toggle input {
		width: 1rem;
		height: 1rem;
		margin: 0;
		padding: 0;
	}
	.multi-fields {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		min-width: 0;
	}
	.multi-fields input {
		width: 100%;
	}
	.multi-meta {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.multi-meta .meta-sep {
		color: var(--color-text-tertiary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
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
