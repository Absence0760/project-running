<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { fetchRoutes } from '$lib/data';
	import ImportRoute from '$lib/components/ImportRoute.svelte';
	import type { Route } from '$lib/types';

	let routes = $state<Route[]>([]);
	let loading = $state(true);
	let showImport = $state(false);

	onMount(async () => {
		routes = await fetchRoutes();
		loading = false;
	});
</script>

{#if showImport}
	<ImportRoute onclose={() => (showImport = false)} />
{/if}

<div class="page">
	<header class="page-header">
		<h1>Routes</h1>
		<div class="header-actions">
			<button class="btn btn-outline" onclick={() => (showImport = true)}>
				<span class="material-symbols">upload_file</span>
				Import
			</button>
			<a href="/routes/new" class="btn btn-primary">
				<span class="material-symbols">add</span>
				New Route
			</a>
		</div>
	</header>

	{#if loading}
		<p class="loading">Loading routes...</p>
	{:else if routes.length === 0}
		<div class="empty">
			<span class="material-symbols empty-icon">route</span>
			<p>No routes yet. Create your first route!</p>
			<a href="/routes/new" class="btn btn-primary">New Route</a>
		</div>
	{:else}
		<div class="route-grid">
			{#each routes as route}
				<a href="/routes/{route.id}" class="route-card">
					<div class="route-map-placeholder">
						<span class="material-symbols">route</span>
					</div>
					<div class="route-info">
						<h3>{route.name}</h3>
						<div class="route-meta">
							<span>{formatDistance(route.distance_m)}</span>
							{#if route.elevation_m}
								<span class="meta-sep">&middot;</span>
								<span>{route.elevation_m} m elev</span>
							{/if}
							<span class="meta-sep">&middot;</span>
							<span class="surface-tag">{route.surface}</span>
						</div>
					</div>
				</a>
			{/each}
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
	}

	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}

	.btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.875rem;
		transition: all var(--transition-fast);
		border: none;
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.header-actions {
		display: flex;
		gap: var(--space-sm);
	}

	.loading {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}

	.empty-icon {
		font-size: 3rem;
	}

	.route-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
		gap: var(--space-md);
	}

	.route-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: all var(--transition-fast);
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-map-placeholder {
		height: 8rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.route-map-placeholder .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.route-info {
		padding: var(--space-md) var(--space-lg);
	}

	h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-xs);
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
