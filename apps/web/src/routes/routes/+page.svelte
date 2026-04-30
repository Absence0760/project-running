<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { formatDistance } from '$lib/mock-data';
	import { fetchRoutesWithError, setRouteStar } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ImportRoute from '$lib/components/ImportRoute.svelte';
	import RouteExplorer from '$lib/components/RouteExplorer.svelte';
	import TrackPreview from '$lib/components/TrackPreview.svelte';
	import type { Route } from '$lib/types';
	import type { Snapshot } from './$types';

	let tab = $state<'mine' | 'explore'>('mine');
	let routes = $state<Route[]>([]);
	let loading = $state(true);
	let fetchError = $state<string | null>(null);
	let showImport = $state(false);

	async function load() {
		loading = true;
		fetchError = null;
		const result = await fetchRoutesWithError();
		routes = result.routes;
		fetchError = result.error;
		loading = false;
	}

	function setTab(next: 'mine' | 'explore') {
		tab = next;
		goto(next === 'explore' ? '/routes?tab=explore' : '/routes', {
			replaceState: true,
			noScroll: true,
			keepFocus: true,
		});
	}

	onMount(() => {
		const initial = $page.url.searchParams.get('tab');
		if (initial === 'explore') tab = 'explore';
		// Skip the fetch when snapshot already restored a list — see
		// the snapshot block below.
		if (routes.length === 0 && loading) load();
	});

	async function toggleStar(event: MouseEvent, routeId: string) {
		// Stop the parent <a> from navigating to the detail page when
		// the star button is clicked. The star is a sub-action; the
		// rest of the card still goes to the detail.
		event.preventDefault();
		event.stopPropagation();
		const i = routes.findIndex((r) => r.id === routeId);
		if (i < 0) return;
		const next = !routes[i].is_starred;
		// Optimistic update — the toggle should feel instant. If the
		// network call fails we revert and surface the error.
		routes = routes.map((r) => (r.id === routeId ? { ...r, is_starred: next } : r));
		try {
			await setRouteStar(routeId, next);
		} catch (e) {
			routes = routes.map((r) => (r.id === routeId ? { ...r, is_starred: !next } : r));
			showToast(`Could not ${next ? 'star' : 'unstar'} route: ${e}`, 'error');
		}
	}

	export const snapshot: Snapshot<{ routes: Route[]; tab: 'mine' | 'explore' }> = {
		capture: () => ({ routes, tab }),
		restore: (s) => {
			routes = s.routes;
			tab = s.tab;
			loading = false;
		},
	};
</script>

{#if showImport}
	<ImportRoute onclose={() => (showImport = false)} onimport={load} />
{/if}

<div class="page">
	<header class="page-header">
		<div class="header-actions">
			{#if tab === 'mine'}
				<button class="btn btn-outline" onclick={() => (showImport = true)}>
					<span class="material-symbols">upload_file</span>
					Import
				</button>
				<a href="/routes/new" class="btn btn-primary">
					<span class="material-symbols">add</span>
					New Route
				</a>
			{/if}
		</div>
		<div class="tabs">
			<button class="tab" class:active={tab === 'mine'} onclick={() => setTab('mine')}>
				My routes
			</button>
			<button class="tab" class:active={tab === 'explore'} onclick={() => setTab('explore')}>
				Explore routes
			</button>
		</div>
	</header>

	{#if tab === 'mine'}
		{#if loading}
			<p class="loading">&nbsp;</p>
		{:else if fetchError}
			<div class="error-banner">
				<span class="material-symbols">error</span>
				<div>
					<strong>Couldn't load your routes.</strong>
					<span class="error-detail">{fetchError}</span>
				</div>
				<button class="btn btn-outline" onclick={load}>Retry</button>
			</div>
		{:else if routes.length === 0}
			<div class="empty">
				<span class="material-symbols empty-icon">route</span>
				<p>No routes yet. Create your first route!</p>
				<a href="/routes/new" class="btn btn-primary">New Route</a>
			</div>
		{:else}
			<div class="route-grid">
				{#each routes as route (route.id)}
					<a href="/routes/{route.id}" class="route-card">
						<div class="route-map-placeholder">
							{#if route.waypoints && route.waypoints.length > 1}
								<TrackPreview points={route.waypoints} />
							{:else}
								<span class="material-symbols">route</span>
							{/if}
							{#if auth.user?.id === route.user_id}
								<button
									type="button"
									class="star-btn"
									class:starred={route.is_starred}
									title={route.is_starred ? 'Unstar route' : 'Star route (shows on watch)'}
									aria-label={route.is_starred ? 'Unstar route' : 'Star route'}
									onclick={(e) => toggleStar(e, route.id)}
								>
									<span class="material-symbols">star</span>
								</button>
							{/if}
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
	{:else}
		<RouteExplorer />
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}

	.header-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		flex-wrap: wrap;
		min-height: 2.5rem;
		margin-bottom: var(--space-md);
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
	}

	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		margin-right: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	.loading {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
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
		text-decoration: none;
		color: inherit;
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-map-placeholder {
		position: relative;
		height: 8rem;
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 6%, var(--color-bg-tertiary)),
			var(--color-bg-tertiary) 60%,
			color-mix(in srgb, var(--color-accent-cyan, var(--color-primary)) 5%, var(--color-bg-tertiary))
		);
		border-bottom: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.star-btn {
		position: absolute;
		top: 0.5rem;
		right: 0.5rem;
		width: 2.25rem;
		height: 2.25rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0;
		background: rgba(0, 0, 0, 0.45);
		border: none;
		border-radius: 50%;
		color: rgba(255, 255, 255, 0.7);
		cursor: pointer;
		transition:
			background var(--transition-fast),
			color var(--transition-fast),
			transform var(--transition-fast);
	}

	.star-btn:hover {
		background: rgba(0, 0, 0, 0.65);
		transform: scale(1.05);
	}

	.star-btn.starred {
		background: rgba(0, 0, 0, 0.65);
		color: #fbbf24;
	}

	.star-btn .material-symbols {
		font-size: 1.25rem;
		font-variation-settings: 'FILL' 0;
		transition: font-variation-settings var(--transition-fast);
	}

	.star-btn.starred .material-symbols {
		font-variation-settings: 'FILL' 1;
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
