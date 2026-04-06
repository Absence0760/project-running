<script lang="ts">
	import { mockRoutes, formatDistance } from '$lib/mock-data';

	let { data } = $props();

	const route = mockRoutes[0];
</script>

<div class="page">
	<a href="/routes" class="back-link">
		<span class="material-symbols">arrow_back</span>
		Routes
	</a>

	<header class="detail-header">
		<div>
			<h1>{route.name}</h1>
			<div class="route-meta">
				<span>{formatDistance(route.distance_m)}</span>
				{#if route.elevation_m}
					<span class="meta-sep">&middot;</span>
					<span>{route.elevation_m} m elevation gain</span>
				{/if}
				<span class="meta-sep">&middot;</span>
				<span class="surface-tag">{route.surface}</span>
			</div>
		</div>
		<div class="actions">
			<button class="btn btn-outline">Export GPX</button>
			<button class="btn btn-primary">Start Run</button>
		</div>
	</header>

	<div class="map-container">
		<div class="map-placeholder">
			<span class="material-symbols">map</span>
			<p>Route map</p>
		</div>
	</div>

	<!-- Elevation profile placeholder -->
	<section class="card">
		<h2>Elevation Profile</h2>
		<div class="elevation-placeholder">
			<svg viewBox="0 0 400 80" class="elevation-svg">
				<path
					d="M0 70 C50 60, 80 30, 120 40 S180 10, 220 35 S280 55, 320 25 S370 45, 400 50 L400 80 L0 80 Z"
					fill="var(--color-primary-light)"
					stroke="var(--color-primary)"
					stroke-width="2"
				/>
			</svg>
		</div>
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 56rem;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.actions {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
		cursor: pointer;
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
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

	.map-container {
		margin-bottom: var(--space-xl);
	}

	.map-placeholder {
		height: 24rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-lg);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm);
		color: var(--color-text-tertiary);
	}

	.map-placeholder .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 3rem;
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
	}

	.elevation-placeholder {
		height: 5rem;
	}

	.elevation-svg {
		width: 100%;
		height: 100%;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
