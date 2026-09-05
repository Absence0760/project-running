<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { handleTablistKeydown } from '$lib/util/tablist';
	import { formatDistance } from '$lib/core/mock-data';
	import { getUnit } from '$lib/format/units.svelte';
	import { fetchRoutesWithError, setRouteStar } from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { routeSurfaceLabel } from '$lib/i18n/enum_labels.svelte';
	import ImportRoute from '$lib/components/ImportRoute.svelte';
	import RunSurfaceTabs from '$lib/components/RunSurfaceTabs.svelte';
	import RouteExplorer from '$lib/components/RouteExplorer.svelte';
	import RouteTrackPreview from '$lib/components/RouteTrackPreview.svelte';
	import type { Route } from '$lib/types';
	import type { Snapshot } from './$types';

	let tab = $state<'mine' | 'explore' | 'heatmap'>('mine');
	let routes = $state<Route[]>([]);
	let loading = $state(true);
	let fetchError = $state<string | null>(null);
	let showImport = $state(false);

	// Filter state for the "My routes" tab. Composes a search box, a
	// surface dropdown, a distance bucket, a sort key, and a starred-
	// only toggle. Filtering is client-side because the list is fully
	// resident — pagination is a separate follow-up.
	type SurfaceFilter = 'any' | 'road' | 'trail' | 'mixed';
	type DistanceBucket = 'any' | 'lt5' | '5to10' | '10to20' | 'gt20';
	type SortKey = 'newest' | 'longest' | 'shortest' | 'most_run' | 'az';

	let search = $state('');
	let surfaceFilter = $state<SurfaceFilter>('any');
	let distanceFilter = $state<DistanceBucket>('any');
	let sortKey = $state<SortKey>('newest');
	let starredOnly = $state(false);

	const FILTERS_KEY = 'routes_filters_v1';
	let filtersHydrated = $state(false);

	$effect(() => {
		if (!filtersHydrated) return;
		try {
			localStorage.setItem(
				FILTERS_KEY,
				JSON.stringify({ search, surfaceFilter, distanceFilter, sortKey, starredOnly }),
			);
		} catch (_) {
			/* silent — quota / private mode etc. */
		}
	});

	/// Monotonic generation counter. Matches the /runs page pattern —
	/// snapshot.restore bumps the gen so an in-flight load() kicked off
	/// on mount discards its result instead of clobbering the captured
	/// list on back-nav from a route-detail page.
	let fetchGen = $state(0);

	async function load() {
		loading = true;
		fetchError = null;
		const gen = ++fetchGen;
		const result = await fetchRoutesWithError();
		if (gen !== fetchGen) return;
		routes = result.routes;
		fetchError = result.error;
		loading = false;
	}

	function setTab(next: 'mine' | 'explore' | 'heatmap') {
		// Heatmap moved to its own route (May 2026) so it can own
		// the full layout column without fighting the routes-page
		// flex chain — see `/routes/heatmap/+page.svelte` for the
		// rationale. Tab clicks navigate; the back button still
		// returns to /routes with the previous tab restored.
		if (next === 'heatmap') {
			void goto('/routes/heatmap');
			return;
		}
		tab = next;
		const path = next === 'mine' ? '/routes' : `/routes?tab=${next}`;
		goto(path, {
			replaceState: true,
			noScroll: true,
			keepFocus: true,
		});
	}

	onMount(() => {
		const initial = $page.url.searchParams.get('tab');
		if (initial === 'explore') tab = 'explore';
		else if (initial === 'heatmap') {
			// Deep-link compat: `/routes?tab=heatmap` now bounces to
			// the standalone `/routes/heatmap` page. Use replaceState
			// so the back button skips the redirect hop.
			void goto('/routes/heatmap', { replaceState: true });
			return;
		}
		// Snapshot restore (SvelteKit back-nav) runs BEFORE onMount and
		// will have already flipped filtersHydrated. Skip the localStorage
		// read in that case — the snapshot is authoritative for this paint.
		if (!filtersHydrated) {
			try {
				const raw = localStorage.getItem(FILTERS_KEY);
				if (raw) {
					const saved = JSON.parse(raw);
					if (typeof saved.search === 'string') search = saved.search;
					if (saved.surfaceFilter) surfaceFilter = saved.surfaceFilter;
					if (saved.distanceFilter) distanceFilter = saved.distanceFilter;
					if (saved.sortKey) sortKey = saved.sortKey;
					if (typeof saved.starredOnly === 'boolean') starredOnly = saved.starredOnly;
				}
			} catch (_) {
				/* leave defaults */
			}
			filtersHydrated = true;
		}
		// Snapshot restore populates `routes` synchronously and flips
		// loading=false — only fetch when neither happened.
		if (routes.length === 0 && loading) load();
	});

	// Bucket boundaries are evaluated in the user's preferred unit so
	// "< 5" means "< 5 km" for metric users and "< 5 mi" for imperial
	// users. The bucket KEYS (lt5, 5to10, ...) are unit-agnostic
	// logical labels — switching the user's pref re-buckets every
	// route through the new threshold ladder. Without this an
	// mi-mode user would still see the metric thresholds even though
	// the labels read in miles.
	const METRES_PER_MILE = 1609.344;
	function inDistanceBucket(meters: number, b: DistanceBucket): boolean {
		const unitMetres = getUnit() === 'mi' ? METRES_PER_MILE : 1000;
		const v = meters / unitMetres;
		switch (b) {
			case 'any':
				return true;
			case 'lt5':
				return v < 5;
			case '5to10':
				return v >= 5 && v < 10;
			case '10to20':
				return v >= 10 && v < 20;
			case 'gt20':
				return v >= 20;
		}
	}

	let distanceUnitLabel = $derived(getUnit() === 'mi' ? 'mi' : 'km');

	let filteredRoutes = $derived.by(() => {
		const q = search.trim().toLowerCase();
		const out = routes.filter((r) => {
			if (starredOnly && !r.is_starred) return false;
			if (surfaceFilter !== 'any' && r.surface !== surfaceFilter) return false;
			if (!inDistanceBucket(r.distance_m, distanceFilter)) return false;
			if (q) {
				const name = (r.name ?? '').toLowerCase();
				if (!name.includes(q)) return false;
			}
			return true;
		});
		switch (sortKey) {
			case 'newest':
				out.sort((a, b) =>
					(b.created_at ?? '').localeCompare(a.created_at ?? ''),
				);
				break;
			case 'longest':
				out.sort((a, b) => b.distance_m - a.distance_m);
				break;
			case 'shortest':
				out.sort((a, b) => a.distance_m - b.distance_m);
				break;
			case 'most_run':
				out.sort((a, b) => (b.run_count ?? 0) - (a.run_count ?? 0));
				break;
			case 'az':
				out.sort((a, b) => (a.name ?? '').localeCompare(b.name ?? ''));
				break;
		}
		return out;
	});

	let filtersActive = $derived(
		search.trim().length > 0 ||
			surfaceFilter !== 'any' ||
			distanceFilter !== 'any' ||
			starredOnly,
	);

	function clearFilters() {
		search = '';
		surfaceFilter = 'any';
		distanceFilter = 'any';
		starredOnly = false;
	}

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
			showToast(
				next
					? m('routesPage.starError', { error: String(e) })
					: m('routesPage.unstarError', { error: String(e) }),
				'error',
			);
		}
	}

	export const snapshot: Snapshot<{
		routes: Route[];
		tab: 'mine' | 'explore' | 'heatmap';
		search: string;
		surfaceFilter: SurfaceFilter;
		distanceFilter: DistanceBucket;
		sortKey: SortKey;
		starredOnly: boolean;
		scrollY: number;
	}> = {
		capture: () => ({
			routes,
			tab,
			search,
			surfaceFilter,
			distanceFilter,
			sortKey,
			starredOnly,
			scrollY: typeof window === 'undefined' ? 0 : window.scrollY,
		}),
		restore: (s) => {
			// Invalidate any in-flight load() the mount-time path may have
			// already kicked off so it doesn't overwrite the captured list.
			fetchGen++;
			routes = s.routes;
			tab = s.tab;
			search = s.search;
			surfaceFilter = s.surfaceFilter;
			distanceFilter = s.distanceFilter;
			sortKey = s.sortKey;
			starredOnly = s.starredOnly;
			filtersHydrated = true;
			loading = false;
			// SvelteKit's auto scroll-restoration runs before the list has
			// rendered, so the page is too short and scroll falls back to
			// 0. Re-apply the captured scrollY after the DOM updates.
			if (typeof window !== 'undefined' && s.scrollY > 0) {
				queueMicrotask(() => {
					requestAnimationFrame(() => window.scrollTo(0, s.scrollY));
				});
			}
		},
	};
</script>

<svelte:head>
	<title>{m('routesPage.pageTitle')} — Threkir</title>
</svelte:head>

{#if showImport}
	<ImportRoute onclose={() => (showImport = false)} onimport={load} />
{/if}

<div class="page">
	<RunSurfaceTabs active="routes" />
	<header class="page-header">
		<!-- tabindex=-1: keydown bubbles here from the focused tab; the
		     tablist itself is never tab-stopped (the tabs carry the roving
		     tabindex). Satisfies a11y_interactive_supports_focus. -->
		<div class="tabs" role="tablist" aria-label={m('routesPage.sectionLabel')} tabindex={-1} onkeydown={handleTablistKeydown}>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'mine'}
				aria-selected={tab === 'mine'}
				tabindex={tab === 'mine' ? 0 : -1}
				onclick={() => setTab('mine')}
			>
				{m('routesPage.tabMine')}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'explore'}
				aria-selected={tab === 'explore'}
				tabindex={tab === 'explore' ? 0 : -1}
				onclick={() => setTab('explore')}
			>
				{m('routesPage.tabExplore')}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'heatmap'}
				aria-selected={tab === 'heatmap'}
				tabindex={tab === 'heatmap' ? 0 : -1}
				onclick={() => setTab('heatmap')}
			>
				{m('routesPage.tabHeatmap')}
			</button>
		</div>
	</header>

	{#if tab === 'mine'}
		{#if loading}
			<div class="filter-row filter-row-skel" aria-hidden="true">
				<span class="skel skel-search"></span>
				<span class="skel skel-pill"></span>
				<span class="skel skel-pill"></span>
				<span class="skel skel-pill"></span>
			</div>
			<div class="route-grid" aria-hidden="true">
				{#each Array(6) as _, i (i)}
					<div class="skel-card">
						<span class="skel skel-thumb"></span>
						<div class="skel-card-body">
							<span class="skel skel-line skel-w-60"></span>
							<span class="skel skel-line skel-w-40"></span>
						</div>
					</div>
				{/each}
			</div>
			<p class="sr-only" role="status">{m('routesPage.loadingRoutes')}</p>
		{:else if fetchError}
			<div class="error-banner" role="alert">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{m('routesPage.loadError')}</strong>
					<span class="error-detail">{fetchError}</span>
				</div>
				<button class="btn btn-outline" onclick={load}>{m('routesPage.retry')}</button>
			</div>
		{:else if routes.length === 0}
			<div class="empty-card">
				<span class="material-symbols empty-icon" aria-hidden="true">route</span>
				<h3>{m('routesPage.emptyTitle')}</h3>
				<p class="empty-text">
					{m('routesPage.emptyText')}
				</p>
				<div class="empty-actions">
					<a href="/routes/new" class="btn btn-primary">
						<span class="material-symbols" aria-hidden="true">add</span>
						{m('routesPage.buildRoute')}
					</a>
					<button class="btn btn-outline" type="button" onclick={() => (showImport = true)}>
						<span class="material-symbols" aria-hidden="true">upload_file</span>
						{m('routesPage.importFile')}
					</button>
					<button
						class="btn btn-outline"
						type="button"
						onclick={() => setTab('explore')}
					>
						<span class="material-symbols" aria-hidden="true">explore</span>
						{m('routesPage.browseCommunity')}
					</button>
				</div>
			</div>
		{:else}
			<!-- Single-rail toolbar: search grows to fill, selects + chips +
			     meta share the same row so the toolbar never burns more than
			     one horizontal line on a wide viewport. Matches the
			     filter-row + space-between pattern used by /dashboard and
			     /runs. -->
			<div class="filter-row">
				<div class="search-wrap">
					<span class="material-symbols" aria-hidden="true">search</span>
					<input
						type="text"
						class="search-input"
						placeholder={m('routesPage.searchPlaceholder')}
						bind:value={search}
						aria-label={m('routesPage.searchLabel')}
					/>
					{#if search}
						<button
							type="button"
							class="search-clear"
							aria-label={m('routesPage.clearSearch')}
							onclick={() => (search = '')}
						>
							<span class="material-symbols" aria-hidden="true">close</span>
						</button>
					{/if}
				</div>
				<div class="select-group">
					<select bind:value={surfaceFilter} class="toolbar-select" aria-label={m('routesPage.surfaceLabel')}>
						<option value="any">{m('routesPage.surfaceAny')}</option>
						<option value="road">{routeSurfaceLabel('road')}</option>
						<option value="trail">{routeSurfaceLabel('trail')}</option>
						<option value="mixed">{routeSurfaceLabel('mixed')}</option>
					</select>
					<select bind:value={distanceFilter} class="toolbar-select" aria-label={m('routesPage.distanceLabel')}>
						<option value="any">{m('routesPage.distanceAny')}</option>
						<option value="lt5">&lt; 5 {distanceUnitLabel}</option>
						<option value="5to10">5–10 {distanceUnitLabel}</option>
						<option value="10to20">10–20 {distanceUnitLabel}</option>
						<option value="gt20">20+ {distanceUnitLabel}</option>
					</select>
					<select bind:value={sortKey} class="toolbar-select" aria-label={m('routesPage.sortLabel')}>
						<option value="newest">{m('routesPage.sortNewest')}</option>
						<option value="longest">{m('routesPage.sortLongest')}</option>
						<option value="shortest">{m('routesPage.sortShortest')}</option>
						<option value="most_run">{m('routesPage.sortMostRun')}</option>
						<option value="az">{m('routesPage.sortAz')}</option>
					</select>
					<button
						type="button"
						class="starred-toggle"
						class:active={starredOnly}
						onclick={() => (starredOnly = !starredOnly)}
						aria-pressed={starredOnly}
						aria-label={starredOnly ? m('routesPage.showAll') : m('routesPage.showStarredOnly')}
						title={m('routesPage.starredSyncTitle')}
					>
						<span class="material-symbols" aria-hidden="true">star</span>
						{m('routesPage.starred')}
					</button>
				</div>
				<div class="toolbar-actions">
					<button class="btn btn-outline btn-sm" type="button" onclick={() => (showImport = true)}>
						<span class="material-symbols" aria-hidden="true">upload_file</span>
						{m('routesPage.import')}
					</button>
					<a href="/routes/new" class="btn btn-primary btn-sm">
						<span class="material-symbols" aria-hidden="true">add</span>
						{m('routesPage.newRoute')}
					</a>
				</div>
			</div>

			<div class="filter-meta">
				<span>
					{routes.length === 1
						? m('routesPage.routeCountSingular', { shown: filteredRoutes.length, total: routes.length })
						: m('routesPage.routeCountPlural', { shown: filteredRoutes.length, total: routes.length })}
					{#if filtersActive}<span class="meta-sep"> · </span>{m('routesPage.filtered')}{/if}
				</span>
				{#if filtersActive}
					<button type="button" class="link-btn" onclick={clearFilters}>{m('routesPage.clearFilters')}</button>
				{/if}
			</div>

			{#if filteredRoutes.length === 0}
				<div class="empty-card">
					<span class="material-symbols empty-icon" aria-hidden="true">filter_alt_off</span>
					<h3>{m('routesPage.noMatchTitle')}</h3>
					<p class="empty-text">
						{m('routesPage.noMatchText')}
					</p>
					<div class="empty-actions">
						<button type="button" class="btn btn-primary" onclick={clearFilters}>
							{m('routesPage.clearFilters')}
						</button>
					</div>
				</div>
			{:else}
				<div class="route-grid">
					{#each filteredRoutes as route (route.id)}
						<a href="/routes/{route.id}" class="route-card">
							<div class="route-map-placeholder">
								<RouteTrackPreview
									routeId={route.id}
									waypoints={route.waypoints ?? []}
									ownerUserId={route.user_id}
								/>
								{#if auth.user?.id === route.user_id}
									<button
										type="button"
										class="star-btn"
										class:starred={route.is_starred}
										title={route.is_starred
											? m('routesPage.unstarTitle')
											: m('routesPage.starTitle')}
										aria-label={route.is_starred
											? m('routesPage.unstarRouteLabel', { name: route.name ?? m('routesPage.routeFallback') })
											: m('routesPage.starRouteLabel', { name: route.name ?? m('routesPage.routeFallback') })}
										aria-pressed={route.is_starred}
										onclick={(e) => toggleStar(e, route.id)}
									>
										<span class="material-symbols" aria-hidden="true">star</span>
									</button>
								{/if}
							</div>
							<div class="route-info">
								<h3>{route.name}</h3>
								<div class="route-meta">
									<span>{formatDistance(route.distance_m)}</span>
									{#if route.elevation_m}
										<span class="meta-sep">&middot;</span>
										<span>{m('routesPage.elevation', { m: route.elevation_m })}</span>
									{/if}
									{#if route.surface}
										<span class="meta-sep">&middot;</span>
										<span class="surface-tag">{routeSurfaceLabel(route.surface)}</span>
									{/if}
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		{/if}
	{:else if tab === 'explore'}
		<RouteExplorer />
	{/if}
	<!-- `tab === 'heatmap'` was a fall-through here pre-May-2026.
		 The heatmap moved to its own /routes/heatmap route to
		 escape this page's flex chain; onMount() now redirects
		 the legacy ?tab=heatmap URL via goto() before this
		 template paints. -->
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}

	/* Heatmap moved to its own /routes/heatmap route in the May
	 * 2026 layout fix — the `.page-heatmap` modifier + its
	 * full-bleed flex chain that used to live here are now in
	 * `/routes/heatmap/+page.svelte` instead. Dead-code removed. */

	.page-header {
		margin-bottom: var(--space-xl);
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
		/* Tabs share one underlined baseline, so they scroll rather than
		   wrap. Second strip on this route — `.surface-tabs` above it got
		   the same treatment. */
		max-width: 100%;
		overflow-x: auto;
	}

	.tab {
		flex: 0 0 auto;
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		margin-inline-end: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}

	.tab:hover {
		color: var(--color-text);
	}

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
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
		color: var(--color-danger-text);
		font-size: 1.4rem;
	}

	/* Empty-state card — same shape as /runs, /plans, /dashboard. Card
	   with icon, h3, explainer, primary CTA + secondary actions. */
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.empty-actions .material-symbols {
		font-size: 1.1rem;
	}

	.route-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(22rem, 100%), 1fr));
		gap: var(--space-md);
	}

	.route-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: border-color var(--transition-fast),
			box-shadow var(--transition-fast);
		text-decoration: none;
		color: inherit;
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-map-placeholder {
		position: relative;
		height: 9rem;
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 6%, var(--color-bg-tertiary)),
			var(--color-bg-tertiary) 60%,
			color-mix(in srgb, var(--color-accent-cyan, var(--color-primary)) 5%, var(--color-bg-tertiary))
		);
		border-bottom: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.star-btn {
		position: absolute;
		top: 0.5rem;
		inset-inline-end: 0.5rem;
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
		transition: background var(--transition-fast),
			color var(--transition-fast),
			transform var(--transition-fast);
	}

	.star-btn:hover {
		background: rgba(0, 0, 0, 0.65);
		transform: scale(1.05);
	}

	.star-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
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

	.route-map-placeholder > .material-symbols {
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

	/* Single-rail filter toolbar — mirrors /dashboard's .filter-row.
	   Search grows to fill, the select group + action group sit on the
	   right edge of the same row. Flex-wrap means we collapse to two
	   rails only when the viewport is too narrow to host all three. */
	.filter-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
		margin-bottom: var(--space-sm);
		flex-wrap: wrap;
	}
	.search-wrap {
		position: relative;
		display: flex;
		align-items: center;
		flex: 1 1 18rem;
		min-width: 12rem;
	}
	.search-wrap > .material-symbols:first-child {
		position: absolute;
		inset-inline-start: 0.75rem;
		color: var(--color-text-tertiary);
		pointer-events: none;
		font-size: 1.1rem;
	}
	.search-input {
		width: 100%;
		padding: 0.5rem 2.25rem 0.5rem 2.25rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
	}
	.search-input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11 — pair the
	   focus rule above with :focus-visible so keyboard users keep
	   the outline ring on top of the border-color change. Self-audit
	   round 6 caught this site: my round-5 bulk script skipped the
	   whole file because OTHER :focus-visible blocks already existed,
	   leaving this single selector unpaired. */
	.search-input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.search-clear {
		position: absolute;
		inset-inline-end: 0.5rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.5rem;
		height: 1.5rem;
		padding: 0;
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		border-radius: 50%;
	}
	.search-clear:hover {
		background: var(--color-primary-light);
		color: var(--color-text);
	}
	.search-clear .material-symbols {
		font-size: 1rem;
	}
	.select-group {
		display: inline-flex;
		gap: 0.5rem;
		flex-wrap: wrap;
	}
	.toolbar-select {
		padding: 0.4rem calc(var(--space-md) + var(--space-md)) 0.4rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		cursor: pointer;
		appearance: none;
		background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23999' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='6 9 12 15 18 9'/></svg>");
		background-repeat: no-repeat;
		background-position: right 0.6rem center;
		background-size: 0.75rem;
		transition: border-color var(--transition-fast);
	}
	.toolbar-select:hover {
		border-color: var(--color-primary);
	}
	.toolbar-select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.starred-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.4rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		font-weight: 500;
		cursor: pointer;
	}
	.starred-toggle:hover {
		border-color: var(--color-primary);
	}
	.starred-toggle .material-symbols {
		font-size: 1rem;
		font-variation-settings: 'FILL' 0;
	}
	.starred-toggle.active {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.starred-toggle.active .material-symbols {
		font-variation-settings: 'FILL' 1;
		color: var(--color-crown);
	}
	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-inline-start: auto;
	}
	.toolbar-actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.toolbar-actions .material-symbols {
		font-size: 1.05rem;
	}
	.filter-meta {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		padding: 0.2rem 0.3rem;
	}
	.link-btn:hover {
		color: var(--color-primary-hover);
	}

	/* Skeleton — same shimmer language as /runs + /dashboard. Mirrors
	   the real card layout so the page lands at its true height
	   immediately and the data swap doesn't shift the grid. */
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-search {
		flex: 1 1 18rem;
		min-width: 12rem;
		height: 2.25rem;
		border-radius: var(--radius-md);
	}
	.skel-pill {
		width: 7rem;
		height: 2rem;
		border-radius: var(--radius-md);
	}
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		pointer-events: none;
	}
	.skel-thumb {
		display: block;
		width: 100%;
		height: 9rem;
		border-radius: 0;
	}
	.skel-card-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md) var(--space-lg);
	}
	.skel-line {
		height: 0.75rem;
	}
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.filter-row-skel {
		gap: var(--space-sm);
	}
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	/* <=50rem (small tablet / large phone). Collapse the right-edge
	   action group to its own row so the toolbar reads as two clean
	   rails rather than three crammed ones. */
	@media (max-width: 50rem) {
		.toolbar-actions {
			margin-inline-start: 0;
			width: 100%;
			justify-content: flex-end;
		}
		.search-wrap {
			flex-basis: 100%;
		}
	}

	/* <=30rem (phone). Single column for the toolbar — search, then
	   selects stretched to fill, then actions. */
	@media (max-width: 30rem) {
		.select-group {
			width: 100%;
		}
		.select-group .toolbar-select {
			flex: 1 1 0;
			min-width: 0;
		}
		/* The toggle carries an icon plus a word, so a shared `min-width: 0`
		   crushed its box to 35px and let 31px of label spill out of the
		   document. It keeps its content width and wraps instead. */
		.select-group .starred-toggle {
			flex: 0 0 auto;
		}
		.toolbar-actions .btn {
			flex: 1 1 0;
			justify-content: center;
		}
	}
</style>
