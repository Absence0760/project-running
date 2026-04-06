<script lang="ts">
	import { mockRoutes, formatDistance } from '$lib/mock-data';
</script>

<div class="page">
	<header class="page-header">
		<h1>Routes</h1>
		<a href="/routes/new" class="btn btn-primary">
			<span class="material-symbols">add</span>
			New Route
		</a>
	</header>

	<div class="route-grid">
		{#each mockRoutes as route}
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
