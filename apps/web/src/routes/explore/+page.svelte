<script lang="ts">
	import RouteExplorer from '$lib/components/RouteExplorer.svelte';
</script>

<svelte:head>
	<title>Explore Routes — Better Runner</title>
	<meta
		name="description"
		content="Discover running routes shared by the community. Search by name, distance, and surface type."
	/>
</svelte:head>

<div class="page">
	<a href="/routes" class="back-link">
		<span class="material-symbols">arrow_back</span> My routes
	</a>
	<header class="page-header">
		<h1>Explore Routes</h1>
		<p class="subtitle">Discover routes shared by the community</p>
	</header>

	<RouteExplorer />
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		font-weight: 500;
		text-decoration: none;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-lg);
	}
	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
</style>
