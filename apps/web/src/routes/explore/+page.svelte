<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { searchPublicRoutes } from '$lib/data';
	import type { Route } from '$lib/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';

	let routes = $state<Route[]>([]);
	let loading = $state(true);
	let hasMore = $state(true);
	let query = $state('');
	let distanceFilter = $state<string>('any');
	let surfaceFilter = $state<string>('any');

	const PAGE_SIZE = 30;

	const distanceOptions: Record<string, { min?: number; max?: number; label: string }> = {
		any: { label: 'Any distance' },
		short: { max: 5000, label: 'Under 5 km' },
		medium: { min: 5000, max: 10000, label: '5-10 km' },
		long: { min: 10000, max: 21000, label: '10-21 km' },
		ultra: { min: 21000, label: '21 km+' },
	};

	const surfaceOptions: Record<string, string> = {
		any: 'Any surface',
		road: 'Road',
		trail: 'Trail',
		mixed: 'Mixed',
	};

	async function search() {
		loading = true;
		const opts = distanceOptions[distanceFilter];
		routes = await searchPublicRoutes({
			query: query.trim() || undefined,
			minDistanceM: opts?.min,
			maxDistanceM: opts?.max,
			surface: surfaceFilter === 'any' ? undefined : surfaceFilter,
			limit: PAGE_SIZE,
			offset: 0,
		});
		hasMore = routes.length >= PAGE_SIZE;
		loading = false;
	}

	async function loadMore() {
		if (loading || !hasMore) return;
		loading = true;
		const opts = distanceOptions[distanceFilter];
		const more = await searchPublicRoutes({
			query: query.trim() || undefined,
			minDistanceM: opts?.min,
			maxDistanceM: opts?.max,
			surface: surfaceFilter === 'any' ? undefined : surfaceFilter,
			limit: PAGE_SIZE,
			offset: routes.length,
		});
		routes = [...routes, ...more];
		hasMore = more.length >= PAGE_SIZE;
		loading = false;
	}

	async function saveToLibrary(route: Route) {
		if (!auth.loggedIn) return;
		const userId = auth.user?.id;
		if (!userId) return;

		const { error } = await supabase.from('routes').insert({
			user_id: userId,
			name: route.name,
			waypoints: route.waypoints,
			distance_m: route.distance_m,
			elevation_m: route.elevation_m,
			surface: route.surface,
			is_public: false,
		});
		if (!error) {
			alert(`Saved "${route.name}" to your library`);
		}
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter') search();
	}

	onMount(() => search());
</script>

<svelte:head>
	<title>Explore Routes — Better Runner</title>
	<meta name="description" content="Discover running routes shared by the community. Search by name, distance, and surface type." />
</svelte:head>

<div class="page">
	<header class="page-header">
		<h1>Explore Routes</h1>
		<p class="subtitle">Discover routes shared by the community</p>
	</header>

	<div class="search-bar">
		<span class="material-symbols search-icon">search</span>
		<input
			type="text"
			placeholder="Search routes by name..."
			bind:value={query}
			onkeydown={handleKeydown}
		/>
		{#if query}
			<button class="clear-btn" onclick={() => { query = ''; search(); }}>
				<span class="material-symbols">close</span>
			</button>
		{/if}
	</div>

	<div class="filters">
		<select bind:value={distanceFilter} onchange={() => search()}>
			{#each Object.entries(distanceOptions) as [key, opt]}
				<option value={key}>{opt.label}</option>
			{/each}
		</select>
		<select bind:value={surfaceFilter} onchange={() => search()}>
			{#each Object.entries(surfaceOptions) as [key, label]}
				<option value={key}>{label}</option>
			{/each}
		</select>
		<button class="btn btn-outline" onclick={() => search()}>Search</button>
	</div>

	{#if routes.length === 0 && !loading}
		<div class="empty">
			<span class="material-symbols empty-icon">explore</span>
			<p>{query ? 'No routes match your search' : 'No public routes yet'}</p>
			<p class="empty-sub">Routes shared from the route builder appear here</p>
		</div>
	{:else}
		<div class="route-grid">
			{#each routes as route}
				<div class="route-card">
					<a href="/share/route/{route.id}" class="route-link">
						<div class="route-map-placeholder">
							<span class="material-symbols">{route.surface === 'trail' ? 'terrain' : route.surface === 'mixed' ? 'alt_route' : 'route'}</span>
						</div>
						<div class="route-info">
							<h3>{route.name}</h3>
							<div class="route-meta">
								<span class="meta-item">
									<span class="material-symbols meta-icon">straighten</span>
									{formatDistance(route.distance_m)}
								</span>
								{#if route.elevation_m}
									<span class="meta-item">
										<span class="material-symbols meta-icon">trending_up</span>
										{route.elevation_m}m
									</span>
								{/if}
								<span class="meta-item">
									<span class="material-symbols meta-icon">{route.surface === 'trail' ? 'terrain' : 'add_road'}</span>
									<span class="surface-tag">{route.surface}</span>
								</span>
							</div>
						</div>
					</a>
					{#if auth.loggedIn}
						<button class="save-btn" onclick={() => saveToLibrary(route)} title="Save to your library">
							<span class="material-symbols">bookmark_add</span>
						</button>
					{/if}
				</div>
			{/each}
		</div>

		{#if hasMore}
			<div class="load-more">
				<button class="btn btn-outline" onclick={loadMore} disabled={loading}>
					{loading ? 'Loading...' : 'Load more'}
				</button>
			</div>
		{/if}
	{/if}

	{#if loading && routes.length === 0}
		<p class="loading-text">Searching...</p>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
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

	.search-bar {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		margin-bottom: var(--space-md);
	}

	.search-bar:focus-within {
		border-color: var(--color-primary);
	}

	.search-icon {
		color: var(--color-text-tertiary);
		font-size: 1.25rem;
	}

	.search-bar input {
		flex: 1;
		border: none;
		background: none;
		font-size: 0.9rem;
		color: var(--color-text);
		outline: none;
		padding: var(--space-xs) 0;
	}

	.clear-btn {
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0;
		display: flex;
	}

	.clear-btn:hover {
		color: var(--color-text);
	}

	.filters {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
		flex-wrap: wrap;
	}

	.filters select {
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		cursor: pointer;
	}

	.filters select:focus {
		border-color: var(--color-primary);
		outline: none;
	}

	.btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
		cursor: pointer;
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

	.btn-outline:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}

	.empty-icon {
		font-size: 3rem;
	}

	.empty-sub {
		font-size: 0.85rem;
	}

	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
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
		position: relative;
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-link {
		display: block;
	}

	.route-map-placeholder {
		height: 8rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.route-map-placeholder .material-symbols {
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.route-info {
		padding: var(--space-md) var(--space-lg);
		padding-right: 3rem;
	}

	h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-xs);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.meta-item {
		display: flex;
		align-items: center;
		gap: 0.2rem;
	}

	.meta-icon {
		font-size: 0.85rem;
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.save-btn {
		position: absolute;
		bottom: var(--space-md);
		right: var(--space-md);
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: var(--space-xs);
		border-radius: var(--radius-sm);
		transition: all var(--transition-fast);
	}

	.save-btn:hover {
		color: var(--color-primary);
		background: rgba(79, 70, 229, 0.1);
	}

	.load-more {
		text-align: center;
		padding: var(--space-xl);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
		text-transform: none;
		letter-spacing: normal;
		word-wrap: normal;
		white-space: nowrap;
		direction: ltr;
		-webkit-font-smoothing: antialiased;
	}
</style>
