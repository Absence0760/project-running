<script lang="ts">
	import { parseRouteFile, type ImportedRoute } from '$lib/integrations/import';
	import { saveRoute } from '$lib/core/data';
	import { formatDistance } from '$lib/core/mock-data';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { rateLimitErrorMessage } from '$lib/util/rate_limit_errors';
	import Modal from './Modal.svelte';

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
			error = err instanceof Error ? err.message : m('importRoute.failedToParse');
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
				error = m('importRoute.selectAtLeastOne');
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
			const friendly =
				rateLimitErrorMessage(err as { code?: string; message?: string }) ??
				(err instanceof Error ? err.message : m('importRoute.failedToSave'));
			showToast(friendly, 'error');
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

<Modal open={true} title={m('importRoute.title')} {onclose}>
	{@render importBody()}
</Modal>

{#snippet importBody()}
		{#if error}
			<div class="error">{error}</div>
		{/if}

		{#if parsed.length === 0}
			<!-- Drop zone — role=region + aria-label so screen-reader users
			     know what's here; keyboard users use the inner Browse
			     button (the drag/drop is a mouse-only convenience). -->
			<div
				class="drop-zone"
				class:dragging
				role="region"
				aria-label={m('importRoute.dropZoneLabel')}
				ondragover={handleDragOver}
				ondragleave={handleDragLeave}
				ondrop={handleDrop}
			>
				{#if parsing}
					<span class="material-symbols">hourglass_empty</span>
					<p>{m('importRoute.parsingFile')}</p>
				{:else}
					<span class="material-symbols">upload_file</span>
					<p>{m('importRoute.dragDropPrompt')}</p>
					<p class="drop-hint">{m('importRoute.supportedFormats')}</p>
					<p class="drop-hint">{m('importRoute.worksWith')}</p>
					<label class="browse-btn">
						{m('importRoute.browseFiles')}
						<input type="file" accept=".gpx,.kml,.kmz,.geojson,.json,.tcx" onchange={handleFileSelect} hidden />
					</label>
				{/if}
			</div>
		{:else if parsed.length === 1}
			<!-- Single-route preview (current behaviour) -->
			<div class="preview">
				<label>
					<span class="label-text">{m('importRoute.routeName')}</span>
					<input type="text" bind:value={names[0]} />
				</label>

				<div class="stats">
					<div class="stat">
						<span class="stat-value">{formatDistance(parsed[0].distance_m)}</span>
						<span class="stat-label">{m('importRoute.distance')}</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed[0].elevation_m ?? 0} m</span>
						<span class="stat-label">{m('importRoute.elevationGain')}</span>
					</div>
					<div class="stat">
						<span class="stat-value">{parsed[0].waypoints.length}</span>
						<span class="stat-label">{m('importRoute.points')}</span>
					</div>
				</div>

				<div class="actions">
					<button class="btn btn-ghost" onclick={reset}>{m('importRoute.chooseDifferentFile')}</button>
					<button class="btn btn-primary" onclick={handleSave} disabled={saving}>
						{saving ? m('importRoute.saving') : m('importRoute.saveRoute')}
					</button>
				</div>
			</div>
		{:else}
			<!-- Multi-route preview — one card per parsed track. Allows the
			     user to rename or deselect individual tracks before import. -->
			<div class="preview">
				<p class="multi-intro">
					{m('importRoute.multiIntroPrefix')}<strong>{parsed.length}</strong>{m('importRoute.multiIntroSuffix')}
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
									<span>{m('importRoute.metaElev', { m: route.elevation_m ?? 0 })}</span>
									<span class="meta-sep">·</span>
									<span>{m('importRoute.metaPts', { n: route.waypoints.length })}</span>
								</div>
							</div>
						</li>
					{/each}
				</ul>
				<div class="actions">
					<button class="btn btn-ghost" onclick={reset}>{m('importRoute.chooseDifferentFile')}</button>
					<button class="btn btn-primary" onclick={handleSave} disabled={saving}>
						{saving
							? m('importRoute.saving')
							: m(
									selected.filter(Boolean).length === 1
										? 'importRoute.importCountOne'
										: 'importRoute.importCountMany',
									{ n: selected.filter(Boolean).length },
								)}
					</button>
				</div>
			</div>
		{/if}
{/snippet}

<style>
	/* .modal-backdrop / .modal / .modal-header / .modal-close /
	   .modal-body live in app.css. */

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
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
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
